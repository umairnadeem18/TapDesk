import Link from "next/link";

export default function NotFound() {
  return (
    <section className="flex min-h-[70svh] items-center pt-28">
      <div className="mx-auto max-w-xl px-5 text-center sm:px-8">
        <p className="font-display text-7xl font-bold text-brand">404</p>
        <h1 className="mt-4 font-display text-3xl font-bold tracking-tight">
          That page never got paired.
        </h1>
        <p className="mt-4 leading-relaxed text-muted">
          The link you followed does not exist. Try scanning the QR code
          instead — that is the one place TapDesk always points you.
        </p>
        <Link
          href="/"
          className="mt-8 inline-flex min-h-12 items-center rounded-full bg-brand px-7 font-semibold text-white transition-colors hover:bg-brand-dark"
        >
          Back to the home page
        </Link>
      </div>
    </section>
  );
}