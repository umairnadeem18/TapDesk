"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import clsx from "clsx";
import {
  Apple,
  Check,
  Copy,
  Download,
  ExternalLink,
  HardDrive,
  Hash,
  Laptop,
  Smartphone,
  X,
} from "lucide-react";
import { RELEASES } from "@/content/site";

type Platform = "android" | "desktop" | "unknown";

function subscribeToNothing() {
  return () => {};
}

function detect(): Platform {
  if (typeof navigator === "undefined") return "unknown";
  const ua = navigator.userAgent;
  if (/android/i.test(ua)) return "android";
  if (/iphone|ipad|ipod/i.test(ua)) return "unknown";
  if (/windows|mac os x|linux|cros/i.test(ua)) return "desktop";
  return "unknown";
}

const ANDROID_STEPS = [
  "Download the TapDesk APK to your phone.",
  "Open Settings → Apps → Special access → Install unknown apps, choose your browser and allow it.",
  "Tap the downloaded file and choose Install.",
  "Open TapDesk, tap Scan QR, and point at the QR on your computer.",
];

const DESKTOP_STEPS = [
  "Run TapDesk-Setup.exe and follow the prompts. It installs in seconds.",
  "The installer adds the Windows Firewall rule TapDesk needs — approve it if prompted.",
  "TapDesk starts in the system tray. Click its icon to open the QR window.",
  "Keep the window visible for your phone to scan, then minimise it.",
];

export function DownloadCards() {
  const platform = useSyncExternalStore(
    subscribeToNothing,
    detect,
    () => "unknown" as Platform,
  );
  const [modal, setModal] = useState<null | "android" | "desktop">(null);
  const [copied, setCopied] = useState<string | null>(null);

  useEffect(() => {
    if (!modal) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setModal(null);
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [modal]);

  const copy = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(text);
      window.setTimeout(() => setCopied(null), 2000);
    } catch {
      setCopied(null);
    }
  };

  const steps = modal === "android" ? ANDROID_STEPS : DESKTOP_STEPS;
  const isRecommended = (id: "android" | "desktop") =>
    platform === id ||
    (platform === "unknown" && id === "desktop");

  return (
    <>
      <div className="grid gap-8 lg:grid-cols-2">
        {/* Android */}
        <article
          className={clsx(
            "relative flex flex-col rounded-[2rem] border bg-white p-8 transition-all sm:p-10",
            isRecommended("android")
              ? "border-brand/50 shadow-xl shadow-brand/10"
              : "border-black/8",
          )}
        >
          {isRecommended("android") ? (
            <span className="absolute -top-3 left-8 rounded-full bg-brand px-3.5 py-1 text-xs font-semibold tracking-wide text-white uppercase">
              Recommended for you
            </span>
          ) : null}

          <div className="flex items-start justify-between gap-4">
            <span className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-brand/10 text-brand-dark">
              <Smartphone className="h-7 w-7" strokeWidth={1.75} aria-hidden />
            </span>
            <span className="rounded-full bg-surface px-3.5 py-1.5 text-sm font-medium text-ink/70">
              {RELEASES.android.version}
            </span>
          </div>

          <h2 className="mt-6 font-display text-2xl font-bold">
            TapDesk for Android
          </h2>
          <p className="mt-1 text-sm font-medium text-brand-dark">
            The controller that runs on your phone
          </p>
          <p className="mt-4 leading-relaxed text-muted">
            Slides, Mouse and Keyboard in one app with three big tabs. Needs
            the free desktop companion running on the computer it controls.
          </p>

          <dl className="mt-7 space-y-2.5 text-sm">
            {[
              ["Size", RELEASES.android.size],
              ["Requires", RELEASES.android.minAndroid],
              ["Permissions", "Camera, Network"],
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between gap-4">
                <dt className="text-muted">{k}</dt>
                <dd className="font-medium">{v}</dd>
              </div>
            ))}
          </dl>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <a
              href={RELEASES.android.url}
              download
              className="inline-flex min-h-13 flex-1 items-center justify-center gap-2 rounded-full bg-brand px-6 font-semibold text-white transition-colors hover:bg-brand-dark"
            >
              <Download className="h-5 w-5" aria-hidden />
              Download APK
            </a>
            <button
              type="button"
              onClick={() => setModal("android")}
              className="inline-flex min-h-13 items-center justify-center rounded-full border border-ink/15 px-6 font-semibold transition-colors hover:border-brand hover:text-brand-dark"
            >
              How to install
            </button>
          </div>

          <Checksum value={RELEASES.android.sha256} onCopy={copy} copied={copied} />
        </article>

        {/* Desktop */}
        <article
          id="desktop"
          className={clsx(
            "relative flex scroll-mt-28 flex-col rounded-[2rem] border bg-white p-8 transition-all sm:p-10",
            isRecommended("desktop")
              ? "border-brand/50 shadow-xl shadow-brand/10"
              : "border-black/8",
          )}
        >
          {isRecommended("desktop") ? (
            <span className="absolute -top-3 left-8 rounded-full bg-brand px-3.5 py-1 text-xs font-semibold tracking-wide text-white uppercase">
              Recommended for you
            </span>
          ) : null}

          <div className="flex items-start justify-between gap-4">
            <span className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-brand/10 text-brand-dark">
              <Laptop className="h-7 w-7" strokeWidth={1.75} aria-hidden />
            </span>
            <span className="rounded-full bg-surface px-3.5 py-1.5 text-sm font-medium text-ink/70">
              {RELEASES.windows.version}
            </span>
          </div>

          <h2 className="mt-6 font-display text-2xl font-bold">
            TapDesk for Windows
          </h2>
          <p className="mt-1 text-sm font-medium text-brand-dark">
            The companion that shows the QR code
          </p>
          <p className="mt-4 leading-relaxed text-muted">
            Runs in the system tray, starts with Windows if you want, and shows
            the pairing QR code. This is what actually drives your mouse and
            keyboard.
          </p>

          <dl className="mt-7 space-y-2.5 text-sm">
            {[
              ["Size", RELEASES.windows.size],
              ["Requires", RELEASES.windows.minWindows],
              ["Extra permissions", "Local network (firewall rule added by installer)"],
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between gap-4">
                <dt className="shrink-0 text-muted">{k}</dt>
                <dd className="text-right font-medium">{v}</dd>
              </div>
            ))}
          </dl>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <a
              href={RELEASES.windows.url}
              download
              className="inline-flex min-h-13 flex-1 items-center justify-center gap-2 rounded-full bg-brand px-6 font-semibold text-white transition-colors hover:bg-brand-dark"
            >
              <Download className="h-5 w-5" aria-hidden />
              Download .exe
            </a>
            <button
              type="button"
              onClick={() => setModal("desktop")}
              className="inline-flex min-h-13 items-center justify-center rounded-full border border-ink/15 px-6 font-semibold transition-colors hover:border-brand hover:text-brand-dark"
            >
              How to install
            </button>
          </div>

          <Checksum value={RELEASES.windows.sha256} onCopy={copy} copied={copied} />
        </article>
      </div>

      <div className="mt-8 grid gap-6 sm:grid-cols-2">
        <div className="flex items-start gap-4 rounded-2xl border border-black/8 bg-surface p-6">
          <Apple className="h-6 w-6 shrink-0 text-ink/40" aria-hidden />
          <div>
            <h3 className="font-display font-semibold">macOS</h3>
            <p className="mt-1 text-sm leading-relaxed text-muted">
              Companion coming. It will request Accessibility and Screen
              Recording permissions, and we will guide you through both.
            </p>
          </div>
        </div>
        <div className="flex items-start gap-4 rounded-2xl border border-black/8 bg-surface p-6">
          <HardDrive className="h-6 w-6 shrink-0 text-ink/40" aria-hidden />
          <div>
            <h3 className="font-display font-semibold">Linux</h3>
            <p className="mt-1 text-sm leading-relaxed text-muted">
              Planned for Ubuntu after the Windows release settles. The
              companion is open source, so early testers can build it now.
            </p>
          </div>
        </div>
      </div>

      <p className="mt-8 text-center text-sm text-muted">
        Prefer an app store?{" "}
        <span className="inline-flex items-center gap-1.5 font-medium text-ink/70">
          Google Play release — coming soon
          <ExternalLink className="h-3.5 w-3.5" aria-hidden />
        </span>
      </p>

      {/* Install modal */}
      {modal ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="install-title"
          className="fixed inset-0 z-100 flex items-end justify-center bg-ink/40 p-4 backdrop-blur-sm sm:items-center"
          onClick={() => setModal(null)}
        >
          <div
            className="w-full max-w-lg rounded-3xl bg-white p-8 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-4">
              <h2
                id="install-title"
                className="font-display text-2xl font-bold"
              >
                Installing on{" "}
                {modal === "android" ? "Android" : "Windows"}
              </h2>
              <button
                type="button"
                onClick={() => setModal(null)}
                aria-label="Close"
                className="inline-flex h-10 w-10 items-center justify-center rounded-full border border-black/10"
              >
                <X className="h-4 w-4" aria-hidden />
              </button>
            </div>

            <ol className="mt-6 space-y-4">
              {steps.map((step, i) => (
                <li key={step} className="flex gap-4">
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brand/12 font-display text-xs font-bold text-brand-dark">
                    {i + 1}
                  </span>
                  <span className="leading-relaxed text-ink/80">{step}</span>
                </li>
              ))}
            </ol>

            {modal === "desktop" ? (
              <p className="mt-6 rounded-2xl bg-surface px-5 py-4 text-sm leading-relaxed text-muted">
                Windows SmartScreen may warn you that the publisher is unknown
                while TapDesk is in beta and unsigned. Choose{" "}
                <strong className="text-ink">More info → Run anyway</strong>, and
                verify the SHA-256 checksum shown on the download card.
              </p>
            ) : (
              <p className="mt-6 rounded-2xl bg-surface px-5 py-4 text-sm leading-relaxed text-muted">
                Android only shows the &ldquo;allow unknown apps&rdquo; setting
                for the app you downloaded from — here, your browser. You can
                turn it back off afterwards.
              </p>
            )}

            <button
              type="button"
              onClick={() => setModal(null)}
              className="mt-7 inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-ink font-semibold text-white transition-colors hover:bg-charcoal"
            >
              <Check className="h-4 w-4" aria-hidden />
              Got it
            </button>
          </div>
        </div>
      ) : null}
    </>
  );
}

function Checksum({
  value,
  onCopy,
  copied,
}: {
  value: string;
  onCopy: (v: string) => void;
  copied: string | null;
}) {
  const [open, setOpen] = useState(false);
  const isCopied = copied === value;

  return (
    <div className="mt-7 border-t border-black/8 pt-5">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="flex w-full items-center gap-2 text-sm font-medium text-muted transition-colors hover:text-ink"
      >
        <Hash className="h-4 w-4" aria-hidden />
        SHA-256 checksum
        <span className="ml-auto">{open ? "Hide" : "Show"}</span>
      </button>
      {open ? (
        <div className="mt-3 flex items-start gap-2">
          <code className="min-w-0 flex-1 break-all rounded-xl bg-surface px-4 py-3 font-mono text-xs leading-relaxed text-ink/70">
            {value}
          </code>
          <button
            type="button"
            onClick={() => onCopy(value)}
            aria-label="Copy checksum"
            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-black/10 transition-colors hover:border-brand hover:text-brand-dark"
          >
            {isCopied ? (
              <Check className="h-4 w-4 text-brand" aria-hidden />
            ) : (
              <Copy className="h-4 w-4" aria-hidden />
            )}
          </button>
        </div>
      ) : null}
    </div>
  );
}