#!/usr/bin/env node
/**
 * Ensures every native binding this build needs is actually installed.
 *
 * THE PROBLEM
 *
 * Tailwind v4 and Next.js ship platform binaries as optionalDependencies:
 *
 *   lightningcss              -> lightningcss-linux-x64-gnu
 *   @tailwindcss/oxide        -> @tailwindcss/oxide-linux-x64-gnu
 *   next                      -> @next/swc-linux-x64-gnu
 *
 * npm has a long-standing bug (npm/cli#4828) where those optional packages are
 * silently not installed in some environments. Vercel's Linux builder hits it,
 * and each missing package then fails the build in turn - we fixed
 * lightningcss and immediately hit @tailwindcss/oxide.
 *
 * It cannot be fixed from a Windows dev machine: npm writes lockfile entries
 * only for the platform it runs on, so a lockfile generated here contains no
 * Linux entry, and no npm flag changes that. Confirmed by running
 * `npm install --package-lock-only --include=optional` and still finding none.
 *
 * THE FIX
 *
 * Read each parent's own optionalDependencies, work out which of them suits the
 * machine we are actually running on, and install any that are missing by
 * fetching the tarball and unpacking it into node_modules.
 *
 * Reading the versions out of the parent's package.json rather than hardcoding
 * them means this keeps working when the dependencies are upgraded - there is
 * no version list here to fall out of date.
 *
 * Runs from `npm run prebuild`, which every Vercel log shows is executed.
 */

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const https = require("node:https");

/** Packages whose optionalDependencies contain native binaries we need. */
const PARENTS = ["lightningcss", "@tailwindcss/oxide", "next"];

/**
 * Every node_modules that could hold these packages.
 *
 * This is an npm workspace, so most dependencies are hoisted to the
 * repository root while some stay in website/node_modules. Checking only one
 * of them silently finds nothing, which is exactly what happened the first
 * time this was written.
 */
const roots = [
  path.resolve(__dirname, "..", "node_modules"),
  path.resolve(__dirname, "..", "..", "node_modules"),
].filter((dir) => fs.existsSync(dir));

/** Where to unpack a missing package. The website's own, which always exists. */
const installRoot = roots[0];

/** Test seam: force a specific package, e.g. TAPDESK_FORCE_PACKAGE. */
const forced = process.env.TAPDESK_FORCE_PACKAGE || null;

function say(msg) {
  console.log(`[tapdesk] ${msg}`);
}

/** The platform token npm uses in these package names. */
function platformSuffixes() {
  const { platform, arch } = process;
  if (platform === "win32") return [`win32-${arch}-msvc`];
  if (platform === "darwin") return [`darwin-${arch}`];
  // Linux ships both a glibc and a musl build; installing both is cheap and
  // removes any need to detect which libc we landed on.
  return [`linux-${arch}-gnu`, `linux-${arch}-musl`];
}

function resolves(pkg) {
  for (const root of roots) {
    try {
      require.resolve(pkg, { paths: [root] });
      return true;
    } catch {
      /* try the next root */
    }
  }
  return false;
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const go = (target) => {
      https
        .get(target, (res) => {
          if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
            file.close();
            res.resume();
            return go(res.headers.location).then(resolve, reject);
          }
          if (res.statusCode !== 200) {
            file.close();
            return reject(new Error(`HTTP ${res.statusCode}`));
          }
          res.pipe(file);
          file.on("finish", () => file.close(resolve));
        })
        .on("error", (err) => {
          file.close();
          reject(err);
        });
    };
    go(url);
  });
}

/** Registry tarball URL. Scoped packages drop the scope from the filename. */
function tarballUrl(pkg, version) {
  const bare = pkg.startsWith("@") ? pkg.split("/")[1] : pkg;
  return `https://registry.npmjs.org/${pkg}/-/${bare}-${version}.tgz`;
}

async function install(pkg, version) {
  const target = path.join(installRoot, pkg);
  const tgz = path.join(installRoot, `.${pkg.replace(/[@/]/g, "_")}-${version}.tgz`);

  say(`fetching ${pkg}@${version}`);
  await download(tarballUrl(pkg, version), tgz);

  fs.mkdirSync(target, { recursive: true });
  execFileSync("tar", ["-xzf", tgz, "-C", target, "--strip-components=1"], {
    stdio: "inherit",
  });
  fs.rmSync(tgz, { force: true });
}

function readOptional(name) {
  for (const root of roots) {
    const file = path.join(root, name, "package.json");
    if (!fs.existsSync(file)) continue;
    try {
      return JSON.parse(fs.readFileSync(file, "utf8")).optionalDependencies || null;
    } catch {
      return null;
    }
  }
  return null;
}

/** Optional deps of [parent] whose names match this platform. */
function wanted(parent) {
  const optional = readOptional(parent);
  if (!optional) return [];

  const suffixes = platformSuffixes();
  return Object.entries(optional).filter(([name]) =>
    suffixes.some((suffix) => name.endsWith(`-${suffix}`)),
  );
}

async function main() {
  if (forced) {
    // Test path: verify the download/unpack mechanism for one package.
    // Split on the LAST '@' so a scoped name keeps its leading '@'.
    const at = forced.lastIndexOf("@");
    const pkg = forced.slice(0, at);
    const version = forced.slice(at + 1);
    await install(pkg, version);
    say(`${pkg} resolves now: ${resolves(pkg)}`);
    return;
  }

  let installed = 0;
  let already = 0;

  for (const parent of PARENTS) {
    for (const [pkg, version] of wanted(parent)) {
      if (resolves(pkg)) {
        already++;
        continue;
      }
      try {
        await install(pkg, version);
        if (resolves(pkg)) {
          say(`installed ${pkg}`);
          installed++;
        } else {
          say(`installed ${pkg} but it still does not resolve`);
        }
      } catch (err) {
        say(`could not install ${pkg}: ${err.message}`);
      }
    }
  }

  say(
    installed === 0
      ? `native bindings already present (${already} checked)`
      : `prepared ${installed} native binding(s), ${already} already present`,
  );

  // Deliberately does not exit non-zero. If a binding is genuinely missing,
  // Next reports the real error; failing here would replace a clear message
  // with a vague one.
}

main().catch((err) => {
  say(`ensure-native-bindings failed: ${err.message}`);
});
