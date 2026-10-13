"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { Download, Menu, X } from "lucide-react";
import clsx from "clsx";
import { Logo } from "@/components/logo";

const LINKS = [
  { href: "/", label: "Home" },
  { href: "/about", label: "About" },
  { href: "/services", label: "Services" },
  { href: "/download", label: "Download" },
];

export function SiteHeader() {
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const [lastPath, setLastPath] = useState(pathname);

  if (lastPath !== pathname) {
    setLastPath(pathname);
    if (open) setOpen(false);
  }

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      className={clsx(
        "fixed inset-x-0 top-0 z-50 transition-all duration-300",
        scrolled
          ? "border-b border-black/8 bg-white/85 backdrop-blur-xl"
          : "border-b border-transparent bg-transparent",
      )}
    >
      <nav
        aria-label="Main"
        className="mx-auto flex h-16 max-w-7xl items-center justify-between gap-4 px-5 sm:h-18 sm:px-8"
      >
        <Link
          href="/"
          className="flex items-center gap-2.5"
          aria-label="TapDesk home"
        >
          <Logo className="h-8 w-8" />
          <span className="font-display text-xl font-bold tracking-tight">
            Tap<span className="text-brand">Desk</span>
          </span>
        </Link>

        <ul className="hidden items-center gap-1 md:flex">
          {LINKS.filter((l) => l.href !== "/download").map((link) => {
            const active =
              link.href === "/" ? pathname === "/" : pathname.startsWith(link.href);
            return (
              <li key={link.href}>
                <Link
                  href={link.href}
                  aria-current={active ? "page" : undefined}
                  className={clsx(
                    "rounded-full px-4 py-2 text-[15px] font-medium transition-colors",
                    active
                      ? "bg-surface text-brand-dark"
                      : "text-ink/70 hover:bg-surface hover:text-ink",
                  )}
                >
                  {link.label}
                </Link>
              </li>
            );
          })}
        </ul>

        <div className="flex items-center gap-2">
          <Link
            href="/download"
            className="hidden items-center gap-2 rounded-full bg-brand px-5 py-2.5 text-[15px] font-semibold text-white transition-all hover:bg-brand-dark hover:shadow-lg hover:shadow-brand/30 sm:inline-flex"
          >
            <Download className="h-4 w-4" aria-hidden />
            Download
          </Link>

          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={open ? "Close menu" : "Open menu"}
            className="inline-flex h-11 w-11 items-center justify-center rounded-full border border-black/10 text-ink md:hidden"
          >
            {open ? (
              <X className="h-5 w-5" aria-hidden />
            ) : (
              <Menu className="h-5 w-5" aria-hidden />
            )}
          </button>
        </div>
      </nav>

      <div
        id="mobile-nav"
        hidden={!open}
        className="border-t border-black/8 bg-white/95 backdrop-blur-xl md:hidden"
      >
        <ul className="mx-auto flex max-w-7xl flex-col gap-1 px-5 py-4">
          {LINKS.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                className="flex min-h-12 items-center justify-between rounded-xl px-4 text-base font-medium text-ink/80 hover:bg-surface"
              >
                {link.label}
                {link.href === "/download" ? (
                  <Download className="h-4 w-4 text-brand" aria-hidden />
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </header>
  );
}