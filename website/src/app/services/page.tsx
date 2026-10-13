import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Check, Lock, ScrollText, Zap } from "lucide-react";
import { Reveal } from "@/components/reveal";
import { ServiceIcon } from "@/components/service-icon";
import { Container, SectionHeading } from "@/components/ui";
import { SERVICES } from "@/content/site";

export const metadata: Metadata = {
  title: "Services & features",
  description:
    "Everything TapDesk provides: wireless mouse with analog stick, presentation slide control, a full on-screen keyboard, QR pairing and local-first secure networking — and the problem each one solves.",
  alternates: { canonical: "/services" },
};

const SUPPORT_MATRIX = [
  { app: "Microsoft PowerPoint", detail: "Windows + macOS", status: "Full slide control" },
  { app: "Google Slides (browser)", detail: "Chrome / Edge", status: "Arrow keys work" },
  { app: "LibreOffice Impress", detail: "Windows / Linux", status: "Full slide control" },
  { app: "PDF viewers", detail: "Any", status: "Scrolling + typing" },
  { app: "Video players & browsers", detail: "Any", status: "Mouse + keyboard" },
  { app: "Code editors & terminals", detail: "Any", status: "Keyboard + Safe Mode aware" },
];

const ROADMAP = [
  ["Touchpad mode & gestures", "Drag-to-move, pinch zoom, three-finger swipe"],
  ["Teacher security", "PIN or biometric lock, classroom device whitelist"],
  ["Auto-discovery & fallback", "mDNS discovery plus a Bluetooth transport"],
  ["More platforms", "macOS and Linux companions, then an iOS app"],
  ["Presenter extras", "Laser pointer, on-screen timer, speaker notes"],
  ["Multi-PC switching", "Move between classroom and hall laptops in one tap"],
];

export default function ServicesPage() {
  return (
    <>
      <section className="relative overflow-hidden pt-32 pb-16 sm:pt-40 sm:pb-24">
        <div className="td-grid pointer-events-none absolute inset-0" />
        <Container className="relative">
          <div className="max-w-3xl">
            <p className="text-sm font-semibold tracking-widest text-brand uppercase">
              Services
            </p>
            <h1 className="mt-4 font-display text-4xl font-bold tracking-tight sm:text-5xl lg:text-6xl lg:leading-[1.05]">
              What TapDesk gives you, and what it fixes
            </h1>
            <p className="mt-7 text-lg leading-relaxed text-muted sm:text-xl">
              Six things ship in v1. Each one exists because of a specific moment
              in a real lecture — the click you cannot reach, the cursor that
              is stuck behind a laptop, the word you have to walk back to type.
            </p>
          </div>
        </Container>
      </section>

      {/* Service blocks */}
      <section className="pb-8">
        <Container>
          <div className="space-y-6">
            {SERVICES.map((s, i) => (
              <Reveal key={s.title} delay={i * 60}>
                <article
                  id={s.title.toLowerCase().replace(/\s+/g, "-")}
                  className="td-card scroll-mt-28 overflow-hidden bg-white"
                >
                  <div className="grid gap-8 p-7 sm:p-9 lg:grid-cols-[1.15fr_0.85fr] lg:gap-14">
                    <div>
                      <span className="inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-brand text-white">
                        <ServiceIcon name={s.icon as never} />
                      </span>
                      <h2 className="mt-6 font-display text-2xl font-bold tracking-tight sm:text-3xl">
                        {s.title}
                      </h2>
                      <p className="mt-1.5 font-display text-base font-semibold text-brand-dark">
                        {s.tagline}
                      </p>
                      <p className="mt-5 leading-relaxed text-muted">
                        {s.description}
                      </p>
                      <p className="mt-6 rounded-2xl bg-surface px-5 py-4 text-sm font-medium text-ink/75">
                        {s.pain}
                      </p>
                    </div>

                    <ul className="space-y-3.5 self-center">
                      {s.bullets.map((b) => (
                        <li key={b} className="flex gap-3 leading-relaxed">
                          <span className="mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand/12 text-brand-dark">
                            <Check className="h-3.5 w-3.5" strokeWidth={3} aria-hidden />
                          </span>
                          <span className="text-ink/80">{b}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Security deep dive */}
      <section id="security" className="scroll-mt-24 py-20 sm:py-24">
        <Container>
          <div className="grid gap-12 lg:grid-cols-2 lg:gap-20">
            <div>
              <p className="text-sm font-semibold tracking-widest text-brand uppercase">
                Security model
              </p>
              <h2 className="mt-3 font-display text-3xl font-bold tracking-tight sm:text-4xl">
                Remote control, without handing over your machine
              </h2>
              <p className="mt-5 leading-relaxed text-muted">
                Anything that can drive your keyboard can, in principle, do
                anything you can. TapDesk treats that as the baseline threat and
                layers consent, pinning and revocation on top of it.
              </p>
              <ol className="mt-9 space-y-6">
                {[
                  ["Desktop shows a QR", "The QR carries the PC name, local IPs, port, a one-time 32-byte token and a SHA-256 certificate fingerprint. The token expires after two minutes or on first use, and the code refreshes automatically."],
                  ["Phone pins the certificate", "The phone opens a TLS WebSocket to that address and pins the fingerprint from the QR — so a machine in the middle of your Wi-Fi is rejected, not trusted."],
                  ["You approve on the computer", "The desktop shows “Allow this phone to control this computer?” with the device name. Nothing is accepted silently, and Deny is one click."],
                  ["A long-lived device key", "After approval the phone stores a device key in the Android Keystore and the computer stores only its hash. Next launch reconnects automatically — and you can revoke that key at any time."],
                ].map(([title, body], i) => (
                  <li key={title} className="flex gap-5">
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-ink font-display text-sm font-bold text-white">
                      {i + 1}
                    </span>
                    <div>
                      <h3 className="font-display font-semibold">{title}</h3>
                      <p className="mt-1.5 leading-relaxed text-muted">{body}</p>
                    </div>
                  </li>
                ))}
              </ol>
            </div>

            <div className="space-y-5">
              <div className="rounded-[2rem] bg-ink p-8 text-white">
                <h3 className="flex items-center gap-3 font-display text-lg font-bold">
                  <Lock className="h-5 w-5 text-brand-light" aria-hidden />
                  Hardening on the computer
                </h3>
                <ul className="mt-5 space-y-3 text-white/75">
                  {[
                    "Rate limiting and a sanity filter on every input event",
                    "Maximum events per second and maximum text length",
                    "Unknown or malformed messages are dropped silently",
                    "Pressed keys and buttons are always released on disconnect",
                    "Safe Mode can block risky shortcuts such as Win+R",
                    "The desktop companion ships open source for audit",
                  ].map((item) => (
                    <li key={item} className="flex gap-3">
                      <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-light" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>

              <div className="rounded-[2rem] bg-surface p-8">
                <h3 className="flex items-center gap-3 font-display text-lg font-bold">
                  <ScrollText className="h-5 w-5 text-brand-dark" aria-hidden />
                  Data handling
                </h3>
                <p className="mt-4 leading-relaxed text-muted">
                  TapDesk collects nothing. There is no account system, no
                  analytics SDK in the apps, and no keystroke logging. The
                  mobile app requests only Camera (to scan the QR) and Network
                  access. Traffic goes directly from your phone to your
                  computer on your local network, so there is no TapDesk server
                  that could be compromised or subpoenaed.
                </p>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Compatibility */}
      <section className="bg-surface py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="Compatibility"
            title="What it can drive"
            lead="Anything that answers arrow keys, mouse input or keystrokes works. TapDesk sends plain input events — it does not need an integration."
          />
          <div className="mx-auto mt-14 max-w-4xl overflow-hidden rounded-2xl border border-black/8 bg-white">
            <table className="w-full text-left text-[15px]">
              <thead className="bg-white/60 text-sm tracking-wide text-muted uppercase">
                <tr>
                  <th scope="col" className="px-6 py-4 font-semibold">
                    Application
                  </th>
                  <th scope="col" className="px-6 py-4 font-semibold">
                    Platform
                  </th>
                  <th scope="col" className="px-6 py-4 font-semibold">
                    What works
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-black/6">
                {SUPPORT_MATRIX.map((row) => (
                  <tr key={row.app}>
                    <th
                      scope="row"
                      className="px-6 py-4 font-display font-semibold"
                    >
                      {row.app}
                    </th>
                    <td className="px-6 py-4 text-muted">{row.detail}</td>
                    <td className="px-6 py-4 text-brand-dark">{row.status}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Container>
      </section>

      {/* Roadmap */}
      <section className="py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="Roadmap"
            title="What comes after v1"
            lead="None of this is required to use TapDesk today — it is simply what we are building next."
          />
          <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {ROADMAP.map(([title, body], i) => (
              <Reveal key={title} delay={i * 60}>
                <article className="td-card h-full p-6">
                  <h3 className="flex items-center gap-2.5 font-display font-semibold">
                    <Zap className="h-4 w-4 text-brand" aria-hidden />
                    {title}
                  </h3>
                  <p className="mt-2.5 text-[15px] leading-relaxed text-muted">
                    {body}
                  </p>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      <section className="pb-24">
        <Container>
          <Reveal>
            <div className="flex flex-col items-center gap-6 rounded-[2rem] bg-ink px-8 py-14 text-center">
              <h2 className="font-display text-3xl font-bold tracking-tight text-white sm:text-4xl">
                Ready to try it in your room?
              </h2>
              <Link
                href="/download"
                className="inline-flex min-h-14 items-center gap-2 rounded-full bg-brand px-9 text-lg font-semibold text-white transition-colors hover:bg-brand-dark"
              >
                Download TapDesk
                <ArrowRight className="h-5 w-5" aria-hidden />
              </Link>
            </div>
          </Reveal>
        </Container>
      </section>
    </>
  );
}