import type { Metadata } from "next";
import { Container } from "@/components/ui";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "TapDesk collects no personal data, runs no analytics and sends nothing to any server. Full privacy policy.",
  alternates: { canonical: "/privacy" },
};

const UPDATED = "13 October 2026";

export default function PrivacyPage() {
  return (
    <section className="pt-32 pb-24 sm:pt-40">
      <Container>
        <div className="mx-auto max-w-3xl">
          <h1 className="font-display text-4xl font-bold tracking-tight sm:text-5xl">
            Privacy Policy
          </h1>
          <p className="mt-3 text-muted">Last updated: {UPDATED}</p>

          <div className="mt-8 rounded-2xl bg-brand/8 px-6 py-5">
            <p className="font-display font-semibold text-brand-dark">
              The short version
            </p>
            <p className="mt-2 leading-relaxed text-ink/80">
              TapDesk has no accounts and collects no personal data. Your phone
              talks directly to your computer over your own network. Nothing you
              click or type is ever transmitted to us, logged, or shared.
            </p>
          </div>

          <div className="prose-td mt-10 space-y-9">
            <section>
              <h2 className="font-display text-2xl font-bold">
                1. What we collect
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                We collect nothing. TapDesk does not ask for a name, an email
                address, a phone number, or any account credentials, because it
                has no account system. We do not collect device identifiers,
                advertising IDs, contacts, photos, location or file contents.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">
                2. What the apps store on your device
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                The Android app stores the names and addresses of computers you
                have paired, plus a device key held in the Android Keystore. The
                desktop companion stores a hashed key for each paired phone. This
                information stays on your devices, is required for the product to
                work, and is deleted when you remove the app or revoke a device.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">
                3. Permissions
              </h2>
              <ul className="mt-3 list-disc space-y-2 pl-5 leading-relaxed text-muted">
                <li>
                  <strong className="text-ink">Camera</strong> — used only to
                  scan the pairing QR code, and only on the pairing screen.
                </li>
                <li>
                  <strong className="text-ink">Network</strong> — used to connect
                  directly to your computer on your local Wi-Fi.
                </li>
                <li>
                  <strong className="text-ink">Vibration</strong> — used for the
                  optional haptic feedback when you press a slide button.
                </li>
              </ul>
              <p className="mt-3 leading-relaxed text-muted">
                No location, microphone, contacts, storage, phone-state or
                background-location permission is requested.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">
                4. How your input data moves
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                Mouse movements, clicks, scroll events and keystrokes are sent
                over an encrypted WebSocket connection directly from your phone
                to your own computer. TapDesk operates no servers and relays no
                traffic. Input data is never persisted to disk and never written
                to any log.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">
                5. Website analytics
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                This website uses a privacy-friendly, cookieless analytics
                provider to count anonymous page views and download clicks. It
                records no cookies, builds no cross-site profile and cannot
                identify you. There is no analytics SDK inside the TapDesk
                mobile or desktop apps.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">6. Children</h2>
              <p className="mt-3 leading-relaxed text-muted">
                TapDesk is intended for teachers, presenters and adult users. We
                do not knowingly collect information from children, because we
                do not collect information from anyone.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">
                7. Your control
              </h2>
              <p className="mt-3 leading-relaxed text-muted">
                You can revoke any paired phone at any time from the desktop
                app, which immediately invalidates its key. Uninstalling either
                app removes all locally stored data. Because we hold no data
                about you, there is nothing for us to export or delete on your
                behalf.
              </p>
            </section>

            <section>
              <h2 className="font-display text-2xl font-bold">8. Changes</h2>
              <p className="mt-3 leading-relaxed text-muted">
                If this policy ever changes, the revised version and its date
                will appear on this page. Contact us at{" "}
                <a
                  className="text-brand-dark underline"
                  href="mailto:privacy@tapdesk.app"
                >
                  privacy@tapdesk.app
                </a>
                .
              </p>
            </section>
          </div>
        </div>
      </Container>
    </section>
  );
}