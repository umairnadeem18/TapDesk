# TapDesk â€” build plan

The working plan for turning TapDesk from a marketing site into a working
product: a Flutter controller app for Android and a Python companion that runs
on the computer.

This document is the source of truth for build order. Each phase has a clear
definition of done, and we do not start a phase until the previous one is
finished and verified.

**Status:** Phase 0 complete on both machines (laptop and desktop PC).
Phase 1 has not started.

> **This section was rewritten on the desktop PC.** The laptop ran out of disk
> during development, so the toolchain was rebuilt from scratch on a second
> machine with everything on `D:`. The table below describes the **desktop PC**,
> which is now the development machine. Paths differ from the laptop.

---

## Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Theme | Dark only | Black background, green on every accent, control and border |
| Build order | App UI first, then the companion | Get visual sign-off on the design before any transport work |
| PC-side QR | Native desktop window only | Browsers are sandboxed and cannot inject OS input, so the companion must be a real app regardless |
| Toolchain | Minimal â€” no Android Studio | Disk space; a graphical SDK manager and emulator are not needed for phone testing |
| Test device | A physical Android 8+ phone | The only way to genuinely verify pairing and input control |

### Why the PC side cannot be a web page

The companion must be able to synthesise OS-level mouse and keyboard events,
show a tray icon, register a global "panic" hotkey, and put an Allow/Deny
dialog in front of the user. Browsers cannot do any of these reliably â€” input
injection is sandboxed, WebHID only covers a narrow set of HID devices, global
hotkeys do not exist, and window focus is not available. So the PC side is a
native desktop app. A browser may later be used as an extra *viewer* for the
status page, but never as the implementation.

---

## Phase 0 â€” Toolchain

The desktop PC had only C++ installed, so the toolchain was built from
scratch. This is the disk-consuming phase, so it runs first and on its own.

### Installed on the desktop PC â€” everything on `D:`

Every tool is a self-contained folder under `D:\DevTools`, so removing one is
delete-the-folder plus re-running `D:\DevTools\env.ps1`.

| Component | Version | Location |
|---|---|---|
| git | 2.51.0 | `D:\DevTools\git\cmd` |
| Python | 3.12.10 | `D:\DevTools\python312` |
| Flutter | 3.47.7 stable (Dart 3.13.5) | `D:\DevTools\flutter` |
| JDK | Temurin 17.0.20.1 | `D:\DevTools\jdk-17` |
| Android SDK | cmdline-tools, platform-tools 37.0.1, `platforms/android-36`, `build-tools/36.0.0` | `D:\DevTools\android-sdk` |
| Gradle cache | â€” | `D:\DevTools\gradle` |
| Pub cache | â€” | `D:\DevTools\pub-cache` |
| VS Code extensions | Flutter, Dart, Live Server, Live Sass | user profile |
| Free disk on C: | 34.9 GB | kept clear on purpose |

| Path | Purpose |
|---|---|
| `D:\Development\TAPDESK` | the repository |
| `D:\DevTools\` | all third-party tooling |
| `D:\DevTools\downloads` | installer archives â€” safe to delete, reclaims ~2.2 GB |
| `D:\DevTools\env.ps1` | rebuilds the user PATH and the Android/Flutter variables |
| `D:\DevTools\verify.ps1` | one-command health check of the whole toolchain |

### Install list â€” as actually carried out

| # | Task | Size | Notes |
|---|---|---|---|
| 0.1 | Flutter stable (Windows x64) â†’ `D:\DevTools\flutter` | ~3.3 GB | bundles the Dart SDK |
| 0.2 | Temurin JDK 17 â†’ `D:\DevTools\jdk-17` | ~300 MB | required by the Android Gradle Plugin |
| 0.3 | Android command-line tools â†’ `D:\DevTools\android-sdk` | ~150 MB | no Android Studio |
| 0.4 | `platform-tools`, `platforms/android-36`, `build-tools/36.0.0`; accept licences | ~430 MB | see the syntax note below |
| 0.5 | Set `ANDROID_HOME` / `ANDROID_SDK_ROOT` / `PATH`; `flutter config --android-sdk` | â€” | user level only, no admin needed |
| 0.6 | Run `flutter doctor` until clean | â€” | verification gate â€” **passed** |
| 0.7 | Create a Python venv for the companion and install its packages | ~400 MB | see below |

**Total: ~4.6 GB, all on `D:`.** `C:` gained almost nothing â€” even Gradle's and
Pub's caches were redirected to `D:`.

`flutter doctor` result: **No issues found** â€” Flutter, Android toolchain,
Windows, Chrome, connected device and network all clean.

All companion packages installed cleanly on Python 3.12 as prebuilt wheels
(`websockets cryptography qrcode pillow pynput pystray PySide6`), and each one
was import-tested. The Python 3.12 fallback turned out to be necessary rather
than optional, because 3.15 is the machine-wide interpreter and is too new for
these wheels.

### Things that bit us on this PC

- **`sdkmanager` syntax changed.** The current cmdline-tools replaced it with
  the "Android CLI", which uses **slash** notation: `platforms/android-36`, not
  `platforms;android-36`. The old form fails with a misleading "Package not
  found", so verify SDK installs by checking that `adb.exe`, `android.jar` and
  `aapt2.exe` exist on disk rather than trusting the exit code.
- **Never trust a download by its byte count.** Two archives were truncated and
  still looked plausible. The downloader now verifies each file by opening it as
  a zip, and resumes with `curl -C -`.
- **Long downloads must run detached.** Started as child processes of a tool
  session, they were killed when that session's temp folder was cleaned up,
  losing 898 MB of Flutter. `D:\DevTools\downloads\resume.ps1` now runs
  detached and logs to `download.log`.
- **The connection is slow** â€” about 250 KB/s, and that cap applies to total
  bandwidth rather than per stream, so parallel downloads do not help. Flutter
  alone took roughly two hours.

### Risks

- **Disk space.** Far healthier than the laptop (125 GB free on `D:`), so the
  Gradle download is no longer a risk.
- **Python resolution.** `C:\Python315` is in the *machine* PATH, which
  outranks the user PATH, so a bare `python` in a fresh terminal still
  gives 3.15. This does not affect the companion: its venv is built from
  `D:\DevTools\python312`, and inside the venv `python` is 3.12. Always activate the venv.
- **First Gradle build is slow** on this machine. Expected, not a fault.

### Done when

`flutter doctor` reports no errors for the Flutter and Android toolchain items,
and a test project builds a debug APK.

---

## Phase 1 â€” Freeze the contract

Both apps must agree exactly, so the protocol is specified before any app code
is written. This prevents the phone and the PC drifting apart.

| # | Task |
|---|---|
| 1.1 | `docs/protocol.md` â€” QR payload schema and the `tapdesk://pair` deep link |
| 1.2 | `docs/protocol.md` â€” full JSON event catalogue |
| 1.3 | `docs/protocol.md` â€” handshake sequence, error codes, rate limits |
| 1.4 | `docs/design-system.md` â€” dark theme tokens for the app |

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
| Auth | `{"t":"auth","token":"â€¦","device":"Pixel 7"}` |
| Stick (continuous) | `{"t":"stick","x":0.42,"y":-0.15}` â€” ~60 Hz, values in âˆ’1..1 |
| Relative move | `{"t":"move","dx":5,"dy":-3}` â€” touchpad mode |
| Click | `{"t":"click","b":"left","a":"down\|up\|click\|double"}` |
| Scroll | `{"t":"scroll","dy":-3}` |
| Key | `{"t":"key","k":"right","a":"press"}` |
| Combo | `{"t":"combo","keys":["ctrl","c"]}` |
| Text | `{"t":"text","s":"Hello"}` |
| Slides | `{"t":"slide","a":"next\|prev\|start\|end\|blank"}` |
| Ping | `{"t":"ping","ts":â€¦}` |

All messages are small, validated and rate-limited on the PC side. Unknown or
malformed messages are dropped silently.

### Done when

`docs/protocol.md` and `docs/design-system.md` are committed, and every event
either app will send or receive is defined in them.

---

## Phase 2 â€” Flutter app foundation

| # | Task |
|---|---|
| 2.1 | `flutter create --org app.tapdesk --platforms android mobile/` |
| 2.2 | Set `minSdk 26` (Android 8.0) and the current target SDK |
| 2.3 | Add dependencies: `mobile_scanner`, `web_socket_channel`, `provider` or `riverpod`, `shared_preferences`, `flutter_secure_storage` |
| 2.4 | Build the dark theme with green accents |
| 2.5 | Build the app shell: top tabs, connection indicator, settings entry |

### Theme tokens â€” dark only

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

A top tab bar with **Slides Â· Mouse Â· Keyboard**, the active tab marked by a
green pill or underline, a green dot for connection state, and a settings icon
in the app bar â€” matching the hand-drawn sketch.

### Done when

The app launches on a real device in dark mode with the green design system,
the three tabs switch correctly, and there are no layout overflows on a small
screen.

---

## Phase 3 â€” Screens

Built in the order shown in the sketch.

### 3.1 QR pairing screen

| # | Task |
|---|---|
| 3.1.1 | Full-screen camera with a QR scanning frame in green corners |
| 3.1.2 | Permission rationale screen explaining why the camera is needed |
| 3.1.3 | "Enter code manually" fallback â€” IP address plus a 6-digit PIN |
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
| 3.3.1 | Analog stick centred on screen â€” direction follows the thumb, distance sets speed, snaps back on release |
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
| 3.4.3 | Arrow keys and an F1â€“F12 toggle row |
| 3.4.4 | Sticky modifiers, so tapping Ctrl then C sends Ctrl+C |
| 3.4.5 | Text-injection field using the phone's native keyboard â€” supports voice typing and Urdu |
| 3.4.6 | Shortcut row: Copy, Paste, Undo, Alt+Tab, Win+D, Ctrl+S |

### 3.5 Settings

Cursor speed, acceleration curve, haptics on/off, left-handed layout,
keep-screen-awake, Safe Mode, disconnect, and the list of paired devices with
revoke.

### Done when

Every screen matches the sketch, works with the design system, and is fully
usable with no connection â€” inputs queue or disable cleanly with a clear
"not connected" state rather than appearing broken.

---

## Phase 4 â€” Transport layer

| # | Task |
|---|---|
| 4.1 | WebSocket client over TLS, pinning the certificate fingerprint from the QR |
| 4.2 | Connection state machine: idle â†’ connecting â†’ connected â†’ reconnecting |
| 4.3 | Auto-reconnect with backoff: 1s, 2s, 4s, up to 10s |
| 4.4 | "Reconnectingâ€¦" banner that disables controls |
| 4.5 | Ping/pong round-trip latency readout |
| 4.6 | Device key storage in the Android Keystore via `flutter_secure_storage` |
| 4.7 | Typed event builders matching `docs/protocol.md` |

TLS validation is never disabled globally. The self-signed certificate is
trusted only because the phone pinned its fingerprint from the QR.

### Done when

The app can pair against a stub server, hold a connection, report latency, and
recover from a dropped connection without user intervention.

---

## Phase 5 â€” Desktop companion (Python, Windows)

| # | Task |
|---|---|
| 5.1 | venv with `websockets`, `cryptography`, `qrcode`, `pillow`, `pynput`, `pystray`, `PySide6` |
| 5.2 | Generate a self-signed TLS certificate at install; fingerprint = SHA-256 of the DER cert |
| 5.3 | WebSocket server on port 8765, bound to the local network |
| 5.4 | Verify the one-time token; show an Allow / Deny prompt with the phone name |
| 5.5 | Issue a long-lived device key on Allow; store only its hash |
| 5.6 | List paired devices with Revoke |
| 5.7 | Input simulation: move, click (down/up/double), scroll, key, combo, Unicode text, slide actions |
| 5.8 | Rate limiting and input sanity filters â€” max events/sec, max text length |
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

## Phase 6 â€” Integration and testing

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
move slides, use the mouse and type on the PC â€” securely and with no
noticeable lag.

---

## Phase 7 â€” Release

| # | Task |
|---|---|
| 7.1 | Build a signed release APK with our own keystore |
| 7.2 | Back up the keystore securely â€” losing it means losing the ability to update the app |
| 7.3 | Build and test the Windows installer, including code signing if available |
| 7.4 | Upload both binaries to GitHub Releases with checksums |
| 7.5 | Update `website/src/content/site.ts` with the real URLs, file sizes and SHA-256 values |
| 7.6 | Verify the download page links resolve and the checksums match |
| 7.7 | Play Store preparation: listing assets, Data safety form, closed test |

### Done when

A fresh user can download from the website, install on both devices, pair, and
work â€” with nothing but the public website as instructions.

---

## Task index

| Phase | Tasks | Status |
|---|---|---|
| 0 â€” Toolchain | 7 | Complete |
| 1 â€” Freeze the contract | 4 | Not started |
| 2 â€” App foundation | 5 | Not started |
| 3 â€” Screens | 4 screens + settings | Not started |
| 4 â€” Transport | 7 | Not started |
| 5 â€” Desktop companion | 14 | Not started |
| 6 â€” Integration and test | 7 | Not started |
| 7 â€” Release | 7 | Not started |

## Reference

- Requirements: [`PRD.md`](PRD.md)
- Website: [`../website/README.md`](../website/README.md)
