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
| `companion/` | Companion that shows the QR code and drives the real mouse and keyboard | Python 3.12 — *not started* |
| `docs/` | Product requirements, protocol spec, design system, build plan | Markdown |

## Current status

- [x] **Website** — built and building clean. See [`website/README.md`](website/README.md).
- [x] **Toolchain** — Flutter, Android SDK, JDK, Python 3.12, Git, all on `D:`. Verify with `D:\DevTools\verify.ps1`.
- [x] **Protocol v1** — [`docs/protocol.md`](docs/protocol.md) and [`docs/design-system.md`](docs/design-system.md) frozen.
- [ ] **Desktop companion** — WebSocket server, QR pairing, input simulation.
- [ ] **Mobile app** — QR scanner, analog stick, slide buttons, on-screen keyboard.
- [ ] Release pipeline — signed APK and Windows installer, GitHub Releases.
- [ ] Google Play closed test.

## Getting started

### Website

```bash
cd website
npm install
npm run dev      # http://localhost:3000
```

### Toolchain (already installed on the development PC)

Everything third-party lives on `D:` under `D:\DevTools`, one folder per tool.
To remove a tool, delete its folder and re-run `D:\DevTools\env.ps1`.

| Path | What it is |
|---|---|
| `D:\DevTools\flutter` | Flutter 3.47.7 + Dart 3.13.5 |
| `D:\DevTools\jdk-17` | Temurin JDK 17 — required by the Android Gradle Plugin |
| `D:\DevTools\android-sdk` | Android SDK (platform-tools, platform 36, build-tools 36) |
| `D:\DevTools\python312` | Python 3.12 — base for the companion venv |
| `D:\DevTools\git` | Portable Git |
| `D:\DevTools\gradle`, `D:\DevTools\pub-cache` | build caches, kept off `C:` |
| `D:\DevTools\downloads` | installer archives, safe to delete |

Check the whole setup at any time:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\DevTools\verify.ps1
```

### Desktop companion

The companion uses its own virtualenv, so the machine-wide Python does not
matter — always run it through the venv:

```bash
companion\.venv\Scripts\python.exe -m companion
```

Full setup notes, including two gotchas that cost us time, are in
[`docs/PLAN.md`](docs/PLAN.md).

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