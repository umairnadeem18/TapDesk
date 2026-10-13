import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Heart, Lightbulb, ShieldCheck, Users } from "lucide-react";
import { Reveal } from "@/components/reveal";
import { Container, SectionHeading } from "@/components/ui";
import { PROBLEMS } from "@/content/site";

export const metadata: Metadata = {
  title: "About us",
  description:
    "TapDesk is built by people who teach and present. Learn why the phone in your pocket should be the input device, and what we refuse to build.",
  alternates: { canonical: "/about" },
};

const VALUES = [
  {
    icon: Heart,
    title: "Built for the room, not the desk",
    body: "Every feature starts from one question: does this help the person standing in front of a class, or the person sitting at the keyboard?",
  },
  {
    icon: ShieldCheck,
    title: "Local means local",
    body: "If a feature needs a server, it does not ship. Your keystrokes and clicks stay between your phone and your computer.",
  },
  {
    icon: Lightbulb,
    title: "Boring where it should be",
    body: "Input should feel instant and invisible. We optimise for latency and reliability, not for a feature count.",
  },
  {
    icon: Users,
    title: "Teachers first",
    body: "Every classroom has an awkward Wi-Fi setup. We design for the worst network in the building, not the best.",
  },
];

export default function AboutPage() {
  return (
    <>
      <section className="relative overflow-hidden pt-32 pb-16 sm:pt-40 sm:pb-24">
        <div className="td-grid pointer-events-none absolute inset-0" />
        <Container className="relative">
          <div className="max-w-3xl">
            <p className="text-sm font-semibold tracking-widest text-brand uppercase">
              About TapDesk
            </p>
            <h1 className="mt-4 font-display text-4xl font-bold tracking-tight sm:text-5xl lg:text-6xl lg:leading-[1.05]">
              We built TapDesk because the clicker was always in the wrong
              pocket.
            </h1>
            <p className="mt-7 text-lg leading-relaxed text-muted sm:text-xl">
              Somewhere between the lectern and the student is the place where a
              teacher actually wants to be. TapDesk exists to close the distance
              between that place and the computer — using hardware you already
              carry, and software we refuse to route through a server.
            </p>
          </div>
        </Container>
      </section>

      {/* Story */}
      <section className="py-16 sm:py-20">
        <Container>
          <div className="grid gap-12 lg:grid-cols-[1.1fr_0.9fr] lg:gap-20">
            <div className="space-y-6 text-lg leading-relaxed text-ink/80">
              <p>
                The idea is disarmingly simple. Open a small companion app on
                the computer. It shows a QR code. You scan it with your phone.
                Now the phone is a mouse, a slide clicker and a keyboard — and
                you can walk the entire room while presenting.
              </p>
              <p>
                Every existing solution got one of the three parts wrong. USB
                clickers are cheap but they walk away, lost, in the pocket of a
                colleague. Bluetooth presenters need pairing menus and charge
                batteries. Cloud remotes send your keystrokes through someone
                else&apos;s data centre, which is a difficult thing to accept for
                a machine that holds your students&apos; marks.
              </p>
              <p>
                TapDesk takes the opposite approach on each front. Pairing is a
                QR scan, because you should never type an IP address into a
                phone keyboard. The connection is direct and encrypted with a
                certificate the phone pins from the QR itself. And nothing is
                ever sent anywhere: there is no TapDesk account, no dashboard,
                and no server holding your traffic.
              </p>
              <p>
                The first version supports Android phones and Windows computers,
                which is where the need is sharpest — packed lecture theatres
                and schools whose Wi-Fi cannot be changed easily. macOS, Linux,
                iOS, Bluetooth fallback and mDNS discovery are on the roadmap,
                and the desktop companion will be open source so schools can
                audit exactly what it does.
              </p>
            </div>

            <aside className="space-y-6">
              <div className="rounded-[2rem] bg-ink p-8 text-white">
                <h2 className="font-display text-xl font-bold">Our mission</h2>
                <p className="mt-4 leading-relaxed text-white/75">
                  Make the computer controllable from anywhere in the room,
                  without adding hardware to the budget, a receiver to lose, or
                  a cloud service to trust.
                </p>
              </div>
              <div className="rounded-[2rem] bg-surface p-8">
                <h2 className="font-display text-xl font-bold">
                  What we are not building
                </h2>
                <ul className="mt-4 space-y-3 text-muted">
                  {[
                    "Screen mirroring or remote-desktop streaming",
                    "Accounts, subscriptions or classroom dashboards",
                    "Analytics, telemetry or keystroke logging",
                    "Control from outside your local network (yet)",
                  ].map((item) => (
                    <li key={item} className="flex gap-3">
                      <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </aside>
          </div>
        </Container>
      </section>

      {/* Values */}
      <section className="bg-surface py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="How we build"
            title="Four rules we do not break"
          />
          <div className="mt-14 grid gap-6 sm:grid-cols-2">
            {VALUES.map((v, i) => (
              <Reveal key={v.title} delay={i * 80}>
                <article className="td-card h-full bg-white p-7">
                  <span className="inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-brand/10 text-brand-dark">
                    <v.icon className="h-6 w-6" strokeWidth={1.75} aria-hidden />
                  </span>
                  <h3 className="mt-5 font-display text-xl font-bold">
                    {v.title}
                  </h3>
                  <p className="mt-3 leading-relaxed text-muted">{v.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Problems recap */}
      <section className="py-20 sm:py-24">
        <Container>
          <SectionHeading
            eyebrow="Why it exists"
            title="The four problems TapDesk is answerable for"
            lead="If none of these sound like your classroom, we probably are not the right tool yet — and we would rather say so."
          />
          <div className="mt-14 grid gap-6 sm:grid-cols-2">
            {PROBLEMS.map((p, i) => (
              <Reveal key={p.title} delay={i * 70}>
                <article className="td-card h-full p-7">
                  <h3 className="font-display text-lg font-bold">{p.title}</h3>
                  <p className="mt-3 leading-relaxed text-muted">{p.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Container>
      </section>

      {/* Contact */}
      <section id="contact" className="scroll-mt-24 pb-24">
        <Container>
          <Reveal>
            <div className="rounded-[2rem] bg-ink px-8 py-14 text-white sm:px-14">
              <h2 className="font-display text-3xl font-bold tracking-tight sm:text-4xl">
                Talk to us
              </h2>
              <p className="mt-4 max-w-2xl leading-relaxed text-white/70">
                Running a school or university cohort? We are actively looking
                for teachers to test TapDesk in real classrooms, especially on
                the awkward Wi-Fi that breaks everything else. Tell us about your
                setup and we will help you get it running.
              </p>
              <div className="mt-8 flex flex-wrap gap-3">
                <a
                  href="mailto:hello@tapdesk.app"
                  className="inline-flex min-h-12 items-center rounded-full bg-brand px-7 font-semibold transition-colors hover:bg-brand-dark"
                >
                  hello@tapdesk.app
                </a>
                <Link
                  href="/download"
                  className="inline-flex min-h-12 items-center gap-2 rounded-full border border-white/25 px-7 font-semibold transition-colors hover:border-brand-light hover:text-brand-light"
                >
                  Download TapDesk
                  <ArrowRight className="h-4 w-4" aria-hidden />
                </Link>
              </div>
            </div>
          </Reveal>
        </Container>
      </section>
    </>
  );
}