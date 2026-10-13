import Link from "next/link";
import {
  ArrowRight,
  ChevronDown,
  GraduationCap,
  MonitorPlay,
  Sofa,
} from "lucide-react";
import { Hero } from "@/components/hero/hero";
import { Reveal } from "@/components/reveal";
import { ServiceIcon } from "@/components/service-icon";
import { Container, SectionHeading } from "@/components/ui";
import { FAQ, HOW_IT_WORKS, PROBLEMS, SERVICES, STATS } from "@/content/site";

const PERSONAS = [
  {
    icon: GraduationCap,
    title: "Teachers & lecturers",
    body: "Move through the whole lecture hall instead of standing behind a desk. Point at the board, click through a deck, type a word — all from your pocket.",
  },
  {
    icon: MonitorPlay,
    title: "Presenters & speakers",
    body: "A dependable clicker replacement with previous/next, start, end and blank screen. Replaces the USB dongle that vanishes when you need it.",
  },
  {
    icon: Sofa,
    title: "Media at home",
    body: "Control a media PC or a laptop from the couch — full keyboard, volume keys and shortcuts for the apps you actually use.",
  },
];

export default function HomePage() {
  return (
    <>
      <Hero />

      {/* Personas */}
      <section className="py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="Who it is for"
            title="Built for people who have to leave the desk"
            lead="TapDesk exists for one reason: the computer is in the room, but you are not behind it."
          />
          <div className="mt-14 grid gap-6 md:grid-cols-3">
            {PERSONAS.map((p, i) => (
              <Reveal key={p.title} delay={i * 90}>
                <article className="td-card h-full p-7">
                  <span className="inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-brand/10 text-brand-dark">
                    <p.icon className="h-6 w-6" strokeWidth={1.75} aria-hidden />
                  </span>
                  <h3 className="mt-5 font-display text-xl font-bold">
                    {p.title}
                  </h3>
                  <p className="mt-3 leading-relaxed text-muted">{p.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Stats */}
      <section className="border-y border-black/8 bg-ink py-14 text-white">
        <Container>
          <div className="grid grid-cols-2 gap-8 lg:grid-cols-4">
            {STATS.map((s, i) => (
              <Reveal key={s.label} delay={i * 70}>
                <div className="text-center">
                  <p className="font-display text-3xl font-bold text-brand-light sm:text-4xl">
                    {s.value}
                  </p>
                  <p className="mt-2 text-sm text-white/60">{s.label}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Problems */}
      <section className="py-20 sm:py-28">
        <Container>
          <SectionHeading
            eyebrow="The problem"
            title="Four ways a lecture goes sideways"
            lead="None of this is about your slides. It is about the four metres of desk between you and the thing you need to press."
          />
          <div className="mt-14 grid gap-6 sm:grid-cols-2">
            {PROBLEMS.map((p, i) => (
              <Reveal key={p.title} delay={i * 80}>
                <article className="td-card relative h-full overflow-hidden p-7">
                  <span className="absolute top-6 right-6 font-display text-5xl font-bold text-black/5">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <h3 className="font-display text-lg font-bold">{p.title}</h3>
                  <p className="mt-3 leading-relaxed text-muted">{p.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Services preview */}
      <section className="bg-surface py-20 sm:py-28">
        <Container>
          <SectionHeading
            eyebrow="What you get"
            title="One phone. Three superpowers."
            lead="Everything below ships in v1 — no roadmap items, no waitlist."
          />
          <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {SERVICES.slice(0, 3).map((s, i) => (
              <Reveal key={s.title} delay={i * 80}>
                <article className="td-card h-full bg-white p-7">
                  <span className="inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-brand text-white">
                    <ServiceIcon name={s.icon as never} />
                  </span>
                  <h3 className="mt-5 font-display text-xl font-bold">
                    {s.title}
                  </h3>
                  <p className="mt-1 text-sm font-medium text-brand-dark">
                    {s.tagline}
                  </p>
                  <p className="mt-4 leading-relaxed text-muted">
                    {s.description}
                  </p>
                </article>
              </Reveal>
            ))}
          </div>
          <Reveal>
            <div className="mt-12 text-center">
              <Link
                href="/services"
                className="inline-flex min-h-12 items-center gap-2 rounded-full border border-ink/15 px-7 text-base font-semibold transition-all hover:border-brand hover:text-brand-dark"
              >
                See every feature in detail
                <ArrowRight className="h-4 w-4" aria-hidden />
              </Link>
            </div>
          </Reveal>
        </Container>
      </section>

      {/* How it works */}
      <section id="how-it-works" className="scroll-mt-24 py-20 sm:py-28">
        <Container>
          <SectionHeading
            eyebrow="How it works"
            title="Three steps and you are presenting"
          />
          <ol className="mt-14 grid gap-6 lg:grid-cols-3">
            {HOW_IT_WORKS.map((s, i) => (
              <Reveal key={s.step} delay={i * 100}>
                <li className="td-card relative h-full list-none p-7">
                  <span className="font-display text-sm font-bold tracking-widest text-brand">
                    STEP {s.step}
                  </span>
                  <h3 className="mt-4 font-display text-xl font-bold">
                    {s.title}
                  </h3>
                  <p className="mt-3 leading-relaxed text-muted">{s.body}</p>
                  <p className="mt-5 inline-block rounded-full bg-surface px-3.5 py-1.5 text-sm font-medium text-ink/70">
                    {s.minutes}
                  </p>
                </li>
              </Reveal>
            ))}
          </ol>
          <Reveal>
            <p className="mt-10 text-center text-base text-muted">
              Phone and computer only need to share a Wi-Fi network. No internet,
              no account, no cloud.
            </p>
          </Reveal>
        </Container>
      </section>

      {/* Security */}
      <section className="py-20 sm:py-24">
        <Container>
          <div className="grid items-center gap-12 rounded-[2rem] bg-ink p-10 text-white sm:p-14 lg:grid-cols-2">
            <div>
              <p className="text-sm font-semibold tracking-widest text-brand-light uppercase">
                Security
              </p>
              <h2 className="mt-3 font-display text-3xl font-bold tracking-tight sm:text-4xl">
                Nothing happens to your computer until you say yes.
              </h2>
              <p className="mt-5 leading-relaxed text-white/70">
                TapDesk pairs over a certificate the phone pins from the QR
                itself, so nobody can sit in the middle of your connection. Your
                computer always shows which phone is connected, and one click
                (or one hotkey) ends control instantly.
              </p>
              <Link
                href="/services#security"
                className="mt-8 inline-flex min-h-12 items-center gap-2 rounded-full bg-brand px-7 font-semibold transition-colors hover:bg-brand-dark"
              >
                How pairing works
                <ArrowRight className="h-4 w-4" aria-hidden />
              </Link>
            </div>
            <dl className="grid gap-5 sm:grid-cols-2">
              {[
                ["Pinned TLS", "Fingerprint taken from the QR, not from the network"],
                ["One-time tokens", "Random, single-use, expire after 2 minutes"],
                ["Explicit consent", "Allow / Deny prompt on the computer"],
                ["Instant revoke", "Disconnect button plus a global hotkey"],
                ["Input filters", "Rate limits and sanity checks on every event"],
                ["Zero collection", "No analytics, no keystroke logging, ever"],
              ].map(([title, body]) => (
                <div key={title} className="rounded-2xl bg-white/5 p-5">
                  <dt className="font-display font-semibold text-brand-light">
                    {title}
                  </dt>
                  <dd className="mt-1.5 text-sm leading-relaxed text-white/70">
                    {body}
                  </dd>
                </div>
              ))}
            </dl>
          </div>
        </Container>
      </section>

      {/* FAQ */}
      <section id="faq" className="scroll-mt-24 bg-surface py-20 sm:py-28">
        <Container>
          <SectionHeading
            eyebrow="FAQ"
            title="Questions teachers actually ask"
          />
          <div className="mx-auto mt-14 max-w-3xl divide-y divide-black/8">
            {FAQ.map((item, i) => (
              <Reveal key={item.q} delay={i * 50}>
                <details className="group py-5">
                  <summary className="flex cursor-pointer list-none items-center justify-between gap-6 font-display text-lg font-semibold">
                    {item.q}
                    <ChevronDown
                      className="h-5 w-5 shrink-0 text-brand transition-transform group-open:rotate-180"
                      aria-hidden
                    />
                  </summary>
                  <p className="mt-4 leading-relaxed text-muted">{item.a}</p>
                </details>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Final CTA */}
      <section className="py-20 sm:py-28">
        <Container>
          <Reveal>
            <div className="relative overflow-hidden rounded-[2rem] bg-surface px-8 py-16 text-center">
              <div className="td-grain pointer-events-none absolute inset-0 opacity-40" />
              <div className="relative">
                <h2 className="font-display text-3xl font-bold tracking-tight sm:text-4xl">
                  Put the phone in your pocket.
                  <br />
                  <span className="td-gradient-text">Keep the room.</span>
                </h2>
                <p className="mx-auto mt-5 max-w-xl text-lg text-muted">
                  Download the Android controller and the Windows companion. Free,
                  no account, no cloud.
                </p>
                <div className="mt-9 flex flex-col justify-center gap-3 sm:flex-row">
                  <Link
                    href="/download"
                    className="inline-flex min-h-14 items-center justify-center rounded-full bg-brand px-8 text-lg font-semibold text-white transition-colors hover:bg-brand-dark"
                  >
                    Get TapDesk free
                  </Link>
                  <Link
                    href="/services"
                    className="inline-flex min-h-14 items-center justify-center rounded-full border border-ink/15 px-8 text-lg font-semibold transition-colors hover:border-brand hover:text-brand-dark"
                  >
                    Explore features
                  </Link>
                </div>
              </div>
            </div>
          </Reveal>
        </Container>
      </section>
    </>
  );
}