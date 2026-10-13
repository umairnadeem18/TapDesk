# TapDesk

**Your phone is the mouse, clicker and keyboard.**

TapDesk turns an Android phone into a wireless mouse, presentation clicker and
full keyboard for a PC or laptop. A small desktop companion shows a QR code,
the phone scans it, and within ten seconds you are controlling the computer from
anywhere in the room. No cables, no receivers, no accounts, no cloud.

---

## Repository layout

This is a monorepo. Each directory is deployed or shipped independently.

| Path | What it is | Stack |
|---|---|---|
| `website/` | Marketing site — home, about, services, download, privacy, terms | Next.js 16, Tailwind CSS v4, TypeScript |
| `mobile/` | Phone controller: Slides / Mouse / Keyboard tabs | Flutter (Dart) — *not started* |
| `desktop/` | Companion that shows the QR code and drives the real mouse and keyboard | Python 3.11+ — *not started* |
| `docs/` | Product requirements, protocol spec, privacy policy source | Markdown |

## Current status

- [x] **Website** — built and building clean. See [`website/README.md`](website/README.md).
- [ ] **Desktop companion** — WebSocket server, QR pairing, input simulation.
- [ ] **Mobile app** — QR scanner, analog stick, slide buttons, on-screen keyboard.
- [ ] Release pipeline — signed APK and Windows installer, GitHub Releases.
- [ ] Google Play closed test.

## Getting started

```bash
cd website
npm install
npm run dev      # http://localhost:3000
```

## How the product works

1. Install the desktop companion on your computer. It runs in the system tray
   and displays a QR code containing the PC name, local IP, port, a single-use
   pairing token and a certificate fingerprint.
2. Open the TapDesk app on your phone and scan the QR. The phone pins the
   certificate fingerprint, so a man-in-the-middle is rejected rather than
   trusted.
3. The computer asks **"Allow this phone to control this computer?"** — nothing is
   accepted silently. Once approved, the phone stores a long-lived device key
   and reconnects automatically next time.
4. Use the three tabs: **Slides** (previous/next, start, end, blank screen),
   **Mouse** (analog stick, left/right click, scroll) and **Keyboard** (full
   QWERTY plus arrows and F-keys, sticky modifiers, Unicode text injection).

Phone and computer need to be on the same Wi-Fi or LAN. Client-isolated guest
networks will not work — use a phone hotspot instead.

## Design system

White / green / black, applied consistently across the site and both apps.

| Role | Hex |
|---|---|
| Background | `#FFFFFF` |
| Surface | `#F5F7F6` |
| Primary | `#16A34A` |
| Primary dark | `#15803D` |
| Highlight | `#86EFAC` |
| Ink | `#0A0A0A` |
| Muted | `#6B7280` |

Typography: Poppins for headings, Inter for body. Rounded corners, soft shadows,
minimum 56 dp touch targets, outlined icons.

## Privacy stance

TapDesk has no accounts and collects no personal data. Input goes directly from
the phone to the computer over the local network — there is no TapDesk server.
No keystroke logging, no analytics in the apps. Full detail in
[`website/src/app/privacy/page.tsx`](website/src/app/privacy/page.tsx).

## License

Private repository. All rights reserved.