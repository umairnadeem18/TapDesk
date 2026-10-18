/**
 * The one place the site's own address is decided.
 *
 * This existed because the same default was written into three files -
 * layout.tsx, robots.ts and sitemap.ts - and when it was wrong it was wrong in
 * all three at once. Every canonical URL, every sitemap entry, robots.txt and
 * every Open Graph image pointed at `https://tapdesk.app`, which is an
 * unrelated Polish hotel QR product somebody else owns. Search engines would
 * have been told the canonical home of this site was somebody else's, and any
 * link we handed out would have pointed there.
 *
 * So the rule is now: there is no hard-coded production address. It comes from
 * the environment, and a production build without it fails loudly rather than
 * quietly shipping a wrong canonical to every page.
 */

/** Used only when running `next dev` locally, where no domain exists yet. */
const LOCAL = "http://localhost:3000";

export function siteUrl(): string {
  const configured = process.env.NEXT_PUBLIC_SITE_URL?.trim();

  if (configured) {
    // Trailing slashes here would double up in every generated URL, which is
    // the kind of small thing that is much cheaper to prevent than to find.
    return configured.replace(/\/+$/, "");
  }

  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "NEXT_PUBLIC_SITE_URL is not set. Set it to the address this site is " +
        "served from - it becomes every canonical URL, the sitemap and " +
        "robots.txt. Refusing to build rather than guessing, because a wrong " +
        "canonical is far harder to notice than a failed build.",
    );
  }

  return LOCAL;
}