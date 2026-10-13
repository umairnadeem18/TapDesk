import type { Metadata } from "next";
import { QrCode, ScanLine, ShieldCheck } from "lucide-react";
import { DownloadCards } from "@/components/download-cards";
import { Reveal } from "@/components/reveal";
import { Container, SectionHeading } from "@/components/ui";
import { FAQ } from "@/content/site";

export const metadata: Metadata = {
  title: "Download",
  description:
    "Download TapDesk for Android (APK) and the TapDesk desktop companion for Windows 10/11. Both free, no account, install in about a minute.",
  alternates: { canonical: "/download" },
};

const QUICK_STEPS = [
  {
    icon: ScanLine,
    title: "Install the phone app",
    body: "Grab the APK on your Android phone. Google Play version coming soon.",
  },
  {
    icon: QrCode,
    title: "Open the desktop app",
    body: "TapDesk starts in the system tray and displays a pairing QR code.",
  },
  {
    icon: ShieldCheck,
    title: "Scan and approve",
    body: "Your computer asks for permission. Tap Allow — that is the whole setup.",
  },
];

export default function DownloadPage() {
  return (
    <>
      <section className="relative overflow-hidden pt-32 pb-14 sm:pt-40">
        <div className="td-grid pointer-events-none absolute inset-0" />
        <Container className="relative">
          <div className="max-w-3xl">
            <p className="text-sm font-semibold tracking-widest text-brand uppercase">
              Download
            </p>
            <h1 className="mt-4 font-display text-4xl font-bold tracking-tight sm:text-5xl lg:text-6xl lg:leading-[1.05]">
              Two downloads. One minute.
            </h1>
            <p className="mt-7 text-lg leading-relaxed text-muted sm:text-xl">
              An APK installs on your Android <strong>phone</strong>; the .exe
              installs on your Windows <strong>computer</strong>. You need both
              — the phone app sends input, the desktop companion receives it and
              drives your actual mouse and keyboard.
            </p>
          </div>
        </Container>
      </section>

      <section className="pb-20">
        <Container>
          <DownloadCards />
        </Container>
      </section>

      <section className="bg-surface py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="Quick start"
            title="Running in three steps"
          />
          <div className="mt-14 grid gap-6 md:grid-cols-3">
            {QUICK_STEPS.map((s, i) => (
              <Reveal key={s.title} delay={i * 90}>
                <article className="td-card h-full bg-white p-7">
                  <span className="inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-brand text-white">
                    <s.icon className="h-6 w-6" strokeWidth={1.75} aria-hidden />
                  </span>
                  <h3 className="mt-5 font-display text-lg font-bold">
                    {s.title}
                  </h3>
                  <p className="mt-2.5 leading-relaxed text-muted">{s.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      <section id="faq" className="scroll-mt-24 py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="Install FAQ"
            title="Before you download"
            lead="The two questions that trip everyone up: unknown sources on Android, and client-isolated school Wi-Fi."
          />
          <div className="mx-auto mt-14 max-w-3xl divide-y divide-black/8">
            {FAQ.map((item, i) => (
              <Reveal key={item.q} delay={i * 50}>
                <details className="group py-5">
                  <summary className="flex cursor-pointer list-none items-center justify-between gap-6 font-display text-lg font-semibold">
                    {item.q}
                    <span
                      aria-hidden
                      className="shrink-0 text-brand transition-transform group-open:rotate-45"
                    >
                      +
                    </span>
                  </summary>
                  <p className="mt-4 leading-relaxed text-muted">{item.a}</p>
                </details>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>
    </>
  );
}