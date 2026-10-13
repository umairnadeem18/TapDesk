import type { Metadata, Viewport } from "next";
import { Inter, Poppins } from "next/font/google";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const poppins = Poppins({
  subsets: ["latin"],
  weight: ["500", "600", "700", "800"],
  variable: "--font-poppins",
  display: "swap",
});

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://tapdesk.app";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "TapDesk — Turn your phone into a wireless mouse, slide clicker & keyboard",
    template: "%s | TapDesk",
  },
  description:
    "TapDesk turns your Android phone into a wireless mouse, presentation clicker and keyboard for your PC. Pair by QR code in under 10 seconds over your own Wi-Fi. No cables, no accounts, no cloud.",
  keywords: [
    "wireless mouse",
    "phone as mouse",
    "presentation clicker",
    "remote control pc",
    "TapDesk",
    "QR pairing",
  ],
  applicationName: "TapDesk",
  authors: [{ name: "TapDesk" }],
  creator: "TapDesk",
  openGraph: {
    type: "website",
    url: siteUrl,
    siteName: "TapDesk",
    title: "TapDesk — Your phone is the mouse. Your desk is the stage.",
    description:
      "Pair in seconds with a QR code. Move slides, click, scroll and type on your PC from your phone — securely, on your own Wi-Fi.",
  },
  twitter: {
    card: "summary_large_image",
    title: "TapDesk — Your phone is the mouse.",
    description:
      "Pair by QR code in under 10 seconds. Slides, mouse and keyboard for your PC from your phone.",
  },
  robots: { index: true, follow: true },
  alternates: { canonical: "/" },
};

export const viewport: Viewport = {
  themeColor: "#16a34a",
  colorScheme: "light",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${inter.variable} ${poppins.variable}`}
    >
      <head>
        <script
          // Reveal-on-scroll is opt-in, so the content stays visible without JS.
          dangerouslySetInnerHTML={{
            __html: "document.documentElement.classList.add('js')",
          }}
        />
      </head>
      <body className="min-h-screen bg-white text-ink antialiased">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-100 focus:rounded-full focus:bg-brand focus:px-5 focus:py-3 focus:text-base focus:font-semibold focus:text-white"
        >
          Skip to content
        </a>
        <SiteHeader />
        <main id="main">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}