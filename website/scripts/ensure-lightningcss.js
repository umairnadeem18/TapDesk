#!/usr/bin/env node
/**
 * Guarantees lightningcss has its native binary before Next.js builds.
 *
 * WHY THIS EXISTS
 *
 * Tailwind v4 pulls in lightningcss, whose native binary is an
 * optionalDependency named per platform, e.g. `lightningcss-linux-x64-gnu`.
 * On Vercel's Linux builder that package has never been installed, and the
 * build dies with:
 *
 *   Cannot find module '../lightningcss.linux-x64-gnu.node'
 *
 * That message is misleading. lightningcss resolves its binary in two steps:
 *
 *   try   { require('lightningcss-linux-x64-gnu'); }       // the package
 *   catch { require('../lightningcss.linux-x64-gnu.node'); } // a bare file
 *
 * We only ever see the SECOND failure, because the first is swallowed by the
 * catch. So the real problem - the package is missing - is invisible.
 *
 * npm on Windows cannot help: it writes lockfile entries only for the platform
 * it runs on, so a lockfile generated here contains no Linux entry at all and
 * cannot be made to contain one.
 *
 * So this script stops trusting npm to install an optional dependency:
 * if the binary is not resolvable, it fetches the tarball and unpacks it into
 * node_modules itself. That works regardless of npm's optional-dependency
 * behaviour, of vercel.json being read, and of build caching.
 *
 * It runs from `npm run build`, which Vercel demonstrably executes, rather than
 * from `installCommand`, which this deployment has evidently ignored.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const https = require("node:https");

const VERSION = "1.32.0";

/** Which lightningcss package suits this machine. Mirrors lightningcss's own logic. */
function targetPackage() {
  const { platform, arch } = process;
  if (platform === "win32") return "lightningcss-win32-x64-msvc";
  if (platform === "darwin") return arch === "arm64" ? "lightningcss-darwin-arm64" : "lightningcss-darwin-x64";
  // Linux: glibc and musl both ship a package, so try gnu first and fall back.
  return arch === "arm64" ? "lightningcss-linux-arm64-gnu" : "lightningcss-linux-x64-gnu";
}

function muslFallback() {
  const { platform, arch } = process;
  if (platform !== "linux" || arch !== "x64") return null;
  return "lightningcss-linux-x64-musl";
}

/** Already installed and loadable? Then there is nothing to do. */
function alreadyResolves(pkg) {
  try {
    require.resolve(pkg);
    return true;
  } catch {
    return false;
  }
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https
      .get(url, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          file.close();
          res.resume();
          return download(res.headers.location, dest).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          file.close();
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        res.pipe(file);
        file.on("finish", () => file.close(resolve));
      })
      .on("error", (err) => {
        file.close();
        reject(err);
      });
  });
}

async function install(pkg) {
  const root = path.resolve(__dirname, "..", "..", "node_modules");
  const target = path.join(root, pkg);
  if (fs.existsSync(path.join(target, "package.json"))) {
    console.log(`[tapdesk] ${pkg} already on disk`);
    return true;
  }

  const url = `https://registry.npmjs.org/${pkg}/-/${pkg}-${VERSION}.tgz`;
  const tmp = path.join(root, `.${pkg}-${VERSION}.tgz`);

  console.log(`[tapdesk] fetching ${pkg}@${VERSION}`);
  await download(url, tmp);

  fs.mkdirSync(target, { recursive: true });
  // `tar` ships with Windows 10+, macOS and every Linux image Vercel uses.
  execFileSync("tar", ["-xzf", tmp, "-C", target, "--strip-components=1"], {
    stdio: "inherit",
  });
  fs.rmSync(tmp, { force: true });
  console.log(`[tapdesk] installed ${pkg}`);
  return true;
}

async function main() {
  const candidates = [targetPackage(), muslFallback()].filter(Boolean);

  for (const pkg of candidates) {
    if (alreadyResolves(pkg)) {
      console.log(`[tapdesk] lightningcss native binding present: ${pkg}`);
      return;
    }
  }

  for (const pkg of candidates) {
    try {
      await install(pkg);
      if (alreadyResolves(pkg)) {
        console.log(`[tapdesk] lightningcss native binding ready: ${pkg}`);
        return;
      }
    } catch (err) {
      console.error(`[tapdesk] could not install ${pkg}: ${err.message}`);
    }
  }

  // Fall through rather than fail the build here: on Windows the win32
  // binding is normally already present, and a hard failure would mask the
  // real error. Next will report the underlying problem if it still cannot
  // resolve a binary.
  console.warn("[tapdesk] no lightningcss native binding could be prepared");
}

main().catch((err) => {
  console.error("[tapdesk] ensure-lightningcss failed:", err.message);
});
