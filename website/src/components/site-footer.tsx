import Link from "next/link";
import { Mail, ShieldCheck } from "lucide-react";
import { Logo } from "@/components/logo";

const COLUMNS = [
  {
    title: "Product",
    links: [
      { href: "/services", label: "Services" },
      { href: "/#how-it-works", label: "How it works" },
      { href: "/download", label: "Download" },
      { href: "/#faq", label: "FAQ" },
    ],
  },
  {
    title: "Company",
    links: [
      { href: "/about", label: "About us" },
      { href: "/services#security", label: "Security" },
      { href: "/about#contact", label: "Contact" },
    ],
  },
  {
    title: "Legal",
    links: [
      { href: "/privacy", label: "Privacy Policy" },
      { href: "/terms", label: "Terms of Use" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-black/8 bg-surface">
      <div className="mx-auto max-w-7xl px-5 py-14 sm:px-8 sm:py-18">
        <div className="grid gap-10 md:grid-cols-[1.4fr_repeat(3,1fr)]">
          <div>
            <Link href="/" className="flex items-center gap-2.5">
              <Logo className="h-9 w-9" />
              <span className="font-display text-xl font-bold tracking-tight">
                Tap<span className="text-brand">Desk</span>
              </span>
            </Link>
            <p className="mt-4 max-w-sm text-[15px] leading-relaxed text-muted">
              Your phone becomes a wireless mouse, slide clicker and keyboard for
              your computer. Pair with a QR code, control over your own Wi-Fi.
            </p>
            <p className="mt-5 inline-flex items-center gap-2 rounded-full bg-white px-3.5 py-2 text-sm font-medium text-brand-dark ring-1 ring-brand/20">
              <ShieldCheck className="h-4 w-4" aria-hidden />
              No accounts. No cloud. No tracking.
            </p>
          </div>

          {COLUMNS.map((col) => (
            <div key={col.title}>
              <h2 className="font-display text-sm font-semibold tracking-wide text-ink uppercase">
                {col.title}
              </h2>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((link) => (
                  <li key={link.href + link.label}>
                    <Link
                      href={link.href}
                      className="text-[15px] text-muted transition-colors hover:text-brand-dark"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col gap-4 border-t border-black/8 pt-7 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-muted">
            &copy; 2026 TapDesk. All rights reserved.
          </p>
          <div className="flex items-center gap-5">
            <a
              href="mailto:hello@tapdesk.app"
              className="inline-flex items-center gap-2 text-sm text-muted transition-colors hover:text-brand-dark"
            >
              <Mail className="h-4 w-4" aria-hidden />
              hello@tapdesk.app
            </a>
            <span className="inline-flex items-center gap-2 text-sm text-muted">
              <ShieldCheck className="h-4 w-4" aria-hidden />
              Open source companion
            </span>
          </div>
        </div>
      </div>
    </footer>
  );
}