# TapDesk — website

Marketing site for **TapDesk**: the phone-as-mouse / slide-clicker / keyboard
companion described in the product requirements document.

Built with Next.js 16 (App Router), Tailwind CSS v4 and TypeScript.

## Running it

```bash
npm install
npm run dev     # http://localhost:3000
npm run lint
npm run build
npm start
```

Set `NEXT_PUBLIC_SITE_URL` (see `.env.example`) before deploying so canonical
links, `sitemap.xml` and `robots.txt` point at the real domain.

## Structure

```
src/
├── app/
│   ├── layout.tsx           root layout, metadata, header/footer, fonts
│   ├── page.tsx             home
│   ├── about/page.tsx
│   ├── services/page.tsx
│   ├── download/page.tsx
│   ├── privacy/page.tsx
│   ├── terms/page.tsx
│   ├── not-found.tsx
│   ├── icon.tsx             generated app icon
│   ├── opengraph-image.tsx  generated OG image
│   ├── sitemap.ts / robots.ts
│   └── globals.css          design tokens + shared utilities
├── components/
│   ├── hero/
│   │   ├── hero.tsx                 scroll-driven hero (mouse → pixels → CTA)
│   │   ├── mouse-geometry.ts        shared mouse artwork + canvas painter
│   │   └── mouse-svg.tsx            static SVG fallback / reduced motion
│   ├── site-header.tsx, site-footer.tsx, logo.tsx
│   ├── download-cards.tsx           device detection, install modals, checksums
│   ├── reveal.tsx                   scroll reveal + reduced-motion helper
│   ├── service-icon.tsx, ui.tsx
├── content/site.ts          all copy, release metadata, FAQs, roadmap
```

## The hero animation

`src/components/hero/hero.tsx` renders a tall scroll track (`340vh`) with a
sticky viewport. Scroll progress `0 → 1` over that track drives:

| Progress | What happens |
|---|---|
| 0.00 – 0.42 | The pixel mouse slides from the left to the centre; a pointer arrow glides onto the right button and it lights green. The slogan blurs and fades out. |
| 0.46 – 0.88 | The mouse shatters into its individual pixels and scatters outward with gravity and spin, plus an expanding shockwave ring. |
| 0.80 – 1.00 | The download CTA fades in. |

Implementation notes:

- The mouse is vector artwork (`mouse-geometry.ts`) rasterised once into an
  offscreen canvas, then sampled on a 40 × 52 grid with 5× supersampling. Each
  sampled pixel becomes a particle carrying its own colour, delay, direction,
  spin and size.
- The explosion is **analytically derived from scroll progress**, not integrated
  over time, so scrubbing backwards replays it exactly and it stays in sync with
  the scrollbar.
- `prefers-reduced-motion: reduce` swaps the whole thing for a static hero with
  an SVG mouse and the CTA visible.
- With JavaScript disabled the page still renders the full, readable content —
  reveal-on-scroll is gated behind a `.js` class added by an inline script.

## Content

All copy, release versions, sizes and checksums live in `src/content/site.ts`
so the marketing text can be edited without touching components. **Replace the
placeholder download URLs and SHA-256 values there** when the real binaries are
published.

## Design system

White / green / black, per the design spec:

| Token | Value |
|---|---|
| Background | `#FFFFFF` |
| Surface | `#F5F7F6` |
| Primary | `#16A34A` |
| Primary dark | `#15803D` |
| Highlight | `#86EFAC` |
| Ink | `#0A0A0A` |
| Muted | `#6B7280` |

Headings use Poppins, body text Inter (both self-hosted via `next/font`).