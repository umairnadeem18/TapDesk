import type { Metadata } from "next";
import Link from "next/link";
import { Container } from "@/components/ui";

export const metadata: Metadata = {
  title: "Terms of Use",
  description:
    "Terms governing the use of the TapDesk website, Android app and desktop companion.",
  alternates: { canonical: "/terms" },
};

const UPDATED = "13 October 2026";

export default function TermsPage() {
  return (
    <section className="pt-32 pb-24 sm:pt-40">
      <Container>
        <div className="mx-auto max-w-3xl">
          <h1 className="font-display text-4xl font-bold tracking-tight sm:text-5xl">
            Terms of Use
          </h1>
          <p className="mt-3 text-muted">Last updated: {UPDATED}</p>

          <div className="mt-10 space-y-9">
            {[
              [
                "1. Acceptance",
                "By downloading or using TapDesk you agree to these terms. If you do not agree, please do not use the software.",
              ],
              [
                "2. Licence",
                "TapDesk is licensed for your personal or internal organisational use. You may install it on any device you are authorised to administer. You may not resell, sublicense, or redistribute modified builds of the software.",
              ],
              [
                "3. Beta software",
                "Current releases are beta software provided as-is. Features may change, bugs may exist, and builds may be withdrawn or replaced at any time. We recommend testing on a non-critical machine before relying on TapDesk for a live presentation.",
              ],
              [
                "4. Acceptable use",
                "You may only control a computer that you own or have explicit permission to administer. Do not use TapDesk to access a device you are not authorised to control, to bypass another person's security, or for any unlawful purpose. Enabling Safe Mode on classroom machines is recommended.",
              ],
              [
                "5. Network requirements",
                "TapDesk requires the phone and computer to be on the same local network. Some networks isolate clients and will prevent the connection from working; that is a limitation of the network, not a fault in the software.",
              ],
              [
                "6. Third-party software",
                "TapDesk sends standard operating-system input events. You are responsible for complying with the licences of the applications you control with it, including presentation software and commercial productivity suites.",
              ],
              [
                "7. Warranty and liability",
                "TapDesk is provided without warranty of any kind. To the maximum extent permitted by law, the authors are not liable for any loss arising from use of the software, including lost presentations, data loss or missed classes.",
              ],
              [
                "8. Changes to these terms",
                "We may update these terms as the product evolves. The date at the top of this page always reflects the current version.",
              ],
            ].map(([title, body]) => (
              <section key={title}>
                <h2 className="font-display text-2xl font-bold">{title}</h2>
                <p className="mt-3 leading-relaxed text-muted">{body}</p>
              </section>
            ))}
          </div>

          <p className="mt-12 text-sm text-muted">
            Questions?{" "}
            <Link href="/about#contact" className="text-brand-dark underline">
              Get in touch
            </Link>
            .
          </p>
        </div>
      </Container>
    </section>
  );
}