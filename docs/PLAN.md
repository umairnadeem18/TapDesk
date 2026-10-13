# TapDesk — build plan

The working plan for turning TapDesk from a marketing site into a working
product: a Flutter controller app for Android and a Python companion that runs
on the computer.

This document is the source of truth for build order. Each phase has a clear
definition of done, and we do not start a phase until the previous one is
finished and verified.

**Status:** Phase 0 has not started.

---

## Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Theme | Dark only | Black background, green on every accent, control and border |
| Build order | App UI first, then the companion | Get visual sign-off on the design before any transport work |
| PC-side QR | Native desktop window only | Browsers are sandboxed and cannot inject OS input, so the companion must be a real app regardless |
| Toolchain | Minimal — no Android Studio | Disk space; a graphical SDK manager and emulator are not needed for phone testing |
| Test device | A physical Android 8+ phone | The only way to genuinely verify pairing and input control |

### Why the PC side cannot be a web page

The companion must be able to synthesise OS-level mouse and keyboard events,
show a tray icon, register a global "panic" hotkey, and put an Allow/Deny
dialog in front of the user. Browsers cannot do any of these reliably — input
injection is sandboxed, WebHID only covers a narrow set of HID devices, global
hotkeys do not exist, and window focus is not available. So the PC side is a
native desktop app. A browser may later be used as an extra *viewer* for the
status page, but never as the implementation.

---

## Phase 0 — Toolchain

**Nothing Android or Flutter related is currently installed.** This is the
disk-consuming phase, so it runs first and on its own.

### Currently on the machine

| Component | Status |
|---|---|
| git | 2.54.0 |
| Python | 3.14.4 |
| Node | 24.15.0 |
| VS Code | installed |
| winget / chocolatey | available |
| Flutter | **not installed** |
| JDK | **not installed** |
| Android SDK | **not installed** |
| Free disk on C: | **11.3 GB** |
| RAM / CPU | 8 GB, Intel i7-5600U |

### Install list

| # | Task | Size | Notes |
|---|---|---|---|
| 0.1 | Install Flutter stable (Windows x64) to `C:\dev\flutter` | ~3 GB | bundles the Dart SDK |
| 0.2 | Install Temurin JDK 17 via winget (`EclipseAdoptium.Temurin.17.JDK`) | ~300 MB | required by the Android Gradle Plugin |
| 0.3 | Install Android command-line tools to `C:\dev\android-sdk` | ~150 MB | no Android Studio |
| 0.4 | `sdkmanager`: `platform-tools`, `platforms;android-35`, `build-tools;35.0.0`; accept all licences | ~400 MB | licences must be accepted non-interactively |
| 0.5 | Set `ANDROID_HOME` / `ANDROID_SDK_ROOT` / `PATH`; `flutter config --android-sdk` | — | persist at the user level |
| 0.6 | Run `flutter doctor` until clean | — | verification gate |
| 0.7 | Create a Python venv for the companion | ~150 MB | see risk below |

**Total: ~4–4.5 GB**, leaving roughly 7 GB for Gradle caches and build outputs.

### Risks

- **Disk space is the binding constraint.** Gradle's first build will also
  download dependencies. If free space drops below ~2 GB, stop and free space
  rather than risk a half-finished SDK install.
- **Python 3.14 is very new.** `pynput` and `PySide6` may not have wheels for
  it. If installation fails, install Python 3.12 alongside and use that for the
  companion rather than forcing it.
- **First Gradle build is slow** on this i7-5600U. Expected, not a fault.

### Done when

`flutter doctor` reports no errors for the Flutter and Android toolchain items,
and a test project builds a debug APK.

---

## Phase 1 — Freeze the contract

Both apps must agree exactly, so the protocol is specified before any app code
is written. This prevents the phone and the PC drifting apart.

| # | Task |
|---|---|
| 1.1 | `docs/protocol.md` — QR payload schema and the `tapdesk://pair` deep link |
| 1.2 | `docs/protocol.md` — full JSON event catalogue |
| 1.3 | `docs/protocol.md` — handshake sequence, error codes, rate limits |
| 1.4 | `docs/design-system.md` — dark theme tokens for the app |

### QR payload

```json
{
  "v": 1,
  "name": "Teacher-Laptop",
  "ips": ["192.168.1.15"],
  "port": 8765,
  "token": "one-time-random-32-bytes",
  "fp": "sha256-fingerprint-of-pc-cert"
}
```

Encoded as `tapdesk://pair?data=<base64url(json)>`. The token expires after two
minutes or on first use, whichever comes first, and the QR refreshes
automatically.

### Event catalogue

| Event | Message |
|---|---|
| Auth | `{"t":"auth","token":"…","device":"Pixel 7"}` |
| Stick (continuous) | `{"t":"stick","x":0.42,"y":-0.15}` — ~60 Hz, values in −1..1 |
| Relative move | `{"t":"move","dx":5,"dy":-3}` — touchpad mode |
| Click | `{"t":"click","b":"left","a":"down\|up\|click\|double"}` |
| Scroll | `{"t":"scroll","dy":-3}` |
| Key | `{"t":"key","k":"right","a":"press"}` |
| Combo | `{"t":"combo","keys":["ctrl","c"]}` |
| Text | `{"t":"text","s":"Hello"}` |
| Slides | `{"t":"slide","a":"next\|prev\|start\|end\|blank"}` |
| Ping | `{"t":"ping","ts":…}` |

All messages are small, validated and rate-limited on the PC side. Unknown or
malformed messages are dropped silently.

### Done when

`docs/protocol.md` and `docs/design-system.md` are committed, and every event
either app will send or receive is defined in them.

---

## Phase 2 — Flutter app foundation

| # | Task |
|---|---|
| 2.1 | `flutter create --org app.tapdesk --platforms android mobile/` |
| 2.2 | Set `minSdk 26` (Android 8.0) and the current target SDK |
| 2.3 | Add dependencies: `mobile_scanner`, `web_socket_channel`, `provider` or `riverpod`, `shared_preferences`, `flutter_secure_storage` |
| 2.4 | Build the dark theme with green accents |
| 2.5 | Build the app shell: top tabs, connection indicator, settings entry |

### Theme tokens — dark only

| Token | Hex | Used for |
|---|---|---|
| Background | `#0A0A0A` | screen background |
| Surface | `#171717` | cards, tab bar, sheets |
| Elevated surface | `#1F1F1F` | pressed states, keyboard keys |
| Primary | `#16A34A` | buttons, **button borders**, active tab pill, focus rings |
| Primary pressed | `#15803D` | pressed buttons |
| Highlight / glow | `#86EFAC` | active accents, connection dot glow |
| Text | `#FAFAFA` | labels and headings |
| Muted text | `#9CA3AF` | secondary labels |
| Error | `#DC2626` | disconnected state, validation |

Typography: Poppins for headings, Inter for body. Rounded corners at 16 px for
cards and fully rounded for buttons, minimum 56 dp touch targets, outlined
icons.

### App shell

A top tab bar with **Slides · Mouse · Keyboard**, the active tab marked by a
green pill or underline, a green dot for connection state, and a settings icon
in the app bar — matching the hand-drawn sketch.

### Done when

The app launches on a real device in dark mode with the green design system,
the three tabs switch correctly, and there are no layout overflows on a small
screen.

---

## Phase 3 — Screens

Built in the order shown in the sketch.

### 3.1 QR pairing screen

| # | Task |
|---|---|
| 3.1.1 | Full-screen camera with a QR scanning frame in green corners |
| 3.1.2 | Permission rationale screen explaining why the camera is needed |
| 3.1.3 | "Enter code manually" fallback — IP address plus a 6-digit PIN |
| 3.1.4 | Parse the `tapdesk://pair` deep link and extract the payload |
| 3.1.5 | Success state: "Connected to *&lt;PC name&gt;*" then route to the Mouse tab |
| 3.1.6 | Remember paired PCs and offer auto-reconnect on next launch |

### 3.2 Slides tab

| # | Task |
|---|---|
| 3.2.1 | Two large `<` Previous and `>` Next buttons side by side |
| 3.2.2 | Secondary row: Start slideshow (F5), End (Esc), Black screen (B) |
| 3.2.3 | Haptic feedback on every press |
| 3.2.4 | Optional volume-key control so the phone can stay pocketed |
| 3.2.5 | Slide timer for pacing a lecture |

### 3.3 Mouse tab

| # | Task |
|---|---|
| 3.3.1 | Analog stick centred on screen — direction follows the thumb, distance sets speed, snaps back on release |
| 3.3.2 | Stream stick values at 60 Hz |
| 3.3.3 | **Left** button: tap to click, hold to drag, double-tap to double-click |
| 3.3.4 | **Right** button: tap to right-click |
| 3.3.5 | Vertical scroll strip alongside the stick |
| 3.3.6 | Cursor speed slider and acceleration curve |
| 3.3.7 | Left-handed layout that swaps the buttons |

### 3.4 Keyboard tab

| # | Task |
|---|---|
| 3.4.1 | Full QWERTY grid with a number row |
| 3.4.2 | Shift, Ctrl, Alt, Win, Tab, Esc, Backspace, Enter, Space |
| 3.4.3 | Arrow keys and an F1–F12 toggle row |
| 3.4.4 | Sticky modifiers, so tapping Ctrl then C sends Ctrl+C |
| 3.4.5 | Text-injection field using the phone's native keyboard — supports voice typing and Urdu |
| 3.4.6 | Shortcut row: Copy, Paste, Undo, Alt+Tab, Win+D, Ctrl+S |

### 3.5 Settings

Cursor speed, acceleration curve, haptics on/off, left-handed layout,
keep-screen-awake, Safe Mode, disconnect, and the list of paired devices with
revoke.

### Done when

Every screen matches the sketch, works with the design system, and is fully
usable with no connection — inputs queue or disable cleanly with a clear
"not connected" state rather than appearing broken.

---

## Phase 4 — Transport layer

| # | Task |
|---|---|
| 4.1 | WebSocket client over TLS, pinning the certificate fingerprint from the QR |
| 4.2 | Connection state machine: idle → connecting → connected → reconnecting |
| 4.3 | Auto-reconnect with backoff: 1s, 2s, 4s, up to 10s |
| 4.4 | "Reconnecting…" banner that disables controls |
| 4.5 | Ping/pong round-trip latency readout |
| 4.6 | Device key storage in the Android Keystore via `flutter_secure_storage` |
| 4.7 | Typed event builders matching `docs/protocol.md` |

TLS validation is never disabled globally. The self-signed certificate is
trusted only because the phone pinned its fingerprint from the QR.

### Done when

The app can pair against a stub server, hold a connection, report latency, and
recover from a dropped connection without user intervention.

---

## Phase 5 — Desktop companion (Python, Windows)

| # | Task |
|---|---|
| 5.1 | venv with `websockets`, `cryptography`, `qrcode`, `pillow`, `pynput`, `pystray`, `PySide6` |
| 5.2 | Generate a self-signed TLS certificate at install; fingerprint = SHA-256 of the DER cert |
| 5.3 | WebSocket server on port 8765, bound to the local network |
| 5.4 | Verify the one-time token; show an Allow / Deny prompt with the phone name |
| 5.5 | Issue a long-lived device key on Allow; store only its hash |
| 5.6 | List paired devices with Revoke |
| 5.7 | Input simulation: move, click (down/up/double), scroll, key, combo, Unicode text, slide actions |
| 5.8 | Rate limiting and input sanity filters — max events/sec, max text length |
| 5.9 | Safe Mode blocking risky shortcuts such as Win+R |
| 5.10 | Tray icon, status window, paired-device list |
| 5.11 | Instant Disconnect button plus a global hotkey |
| 5.12 | QR auto-refresh after 2 minutes or first use; auto-detect IP changes |
| 5.13 | Start on login option; always release pressed keys on disconnect |
| 5.14 | Package with PyInstaller, then an Inno Setup installer that adds the firewall rule |

### Done when

The companion runs on a Windows machine, shows a QR, and reliably receives and
performs mouse, keyboard and slide input from a paired phone.

---

## Phase 6 — Integration and testing

| # | Task |
|---|---|
| 6.1 | End-to-end on the physical phone: pair, then exercise all three tabs |
| 6.2 | Latency measurement on home Wi-Fi and on a phone hotspot |
| 6.3 | Real applications: PowerPoint, Google Slides in a browser, PDF viewers, LibreOffice Impress |
| 6.4 | Failure cases: Wi-Fi drop, PC sleep, app backgrounded, IP change, firewall block |
| 6.5 | Security tests: connect with no token, replay an old token, wrong fingerprint, event flood, revoked device |
| 6.6 | Verify no stuck keys or clicks after any disconnect |
| 6.7 | Test on at least three Android versions and screen sizes |

### Done when

A teacher installs the desktop app, scans the QR with the phone app, and can
move slides, use the mouse and type on the PC — securely and with no
noticeable lag.

---

## Phase 7 — Release

| # | Task |
|---|---|
| 7.1 | Build a signed release APK with our own keystore |
| 7.2 | Back up the keystore securely — losing it means losing the ability to update the app |
| 7.3 | Build and test the Windows installer, including code signing if available |
| 7.4 | Upload both binaries to GitHub Releases with checksums |
| 7.5 | Update `website/src/content/site.ts` with the real URLs, file sizes and SHA-256 values |
| 7.6 | Verify the download page links resolve and the checksums match |
| 7.7 | Play Store preparation: listing assets, Data safety form, closed test |

### Done when

A fresh user can download from the website, install on both devices, pair, and
work — with nothing but the public website as instructions.

---

## Task index

| Phase | Tasks | Status |
|---|---|---|
| 0 — Toolchain | 7 | Not started |
| 1 — Freeze the contract | 4 | Not started |
| 2 — App foundation | 5 | Not started |
| 3 — Screens | 4 screens + settings | Not started |
| 4 — Transport | 7 | Not started |
| 5 — Desktop companion | 14 | Not started |
| 6 — Integration and test | 7 | Not started |
| 7 — Release | 7 | Not started |

## Reference

- Requirements: [`PRD.md`](PRD.md)
- Website: [`../website/README.md`](../website/README.md)