# TapDesk — build plan

The working plan for turning TapDesk from a marketing site into a working
product: a Flutter controller app for Android and a Python companion that runs
on the computer.

This document is the source of truth for build order. Each phase has a clear
definition of done, and we do not start a phase until the previous one is
finished and verified.

**Status:** Phases 0–5 complete. Phase 6 underway - the product works on real
hardware. Phase 7 in progress: site live, binaries published, keystore still
needs backing up. The outstanding work is almost entirely failure cases.

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

The desktop PC had only a C++ compiler, so the toolchain was built from
scratch. This is the disk-consuming phase, so it runs first and on its own.

### Installed on the desktop PC — everything on `D:`

Every tool is a self-contained folder under `D:\DevTools`, so removing one is
delete-the-folder plus re-running `D:\DevTools\env.ps1`.

| Component | Version | Location |
|---|---|---|
| git | 2.51.0 | `D:\DevTools\git\cmd` |
| Python | 3.12.10 | `D:\DevTools\python312` |
| Flutter | 3.47.7 stable (Dart 3.13.5) | `D:\DevTools\flutter` |
| JDK | Temurin 17.0.20.1 | `D:\DevTools\jdk-17` |
| Android SDK | cmdline-tools, platform-tools 37.0.1, `platforms/android-36`, `build-tools/36.0.0` | `D:\DevTools\android-sdk` |
| Gradle cache | — | `D:\DevTools\gradle` |
| Pub cache | — | `D:\DevTools\pub-cache` |
| VS Code extensions | Flutter, Dart, Live Server, Live Sass | user profile |
| Free disk on C: | 34.9 GB | kept clear on purpose |

| Path | Purpose |
|---|---|
| `D:\Development\TAPDESK` | the repository |
| `D:\DevTools\` | all third-party tooling |
| `D:\DevTools\downloads` | installer archives — safe to delete, reclaims ~2.2 GB |
| `D:\DevTools\env.ps1` | rebuilds the user PATH and the Android/Flutter variables |
| `D:\DevTools\verify.ps1` | one-command health check of the whole toolchain |

### Install list — as actually carried out

| # | Task | Size | Notes |
|---|---|---|---|
| 0.1 | Flutter stable (Windows x64) to `D:\DevTools\flutter` | ~3.3 GB | bundles the Dart SDK |
| 0.2 | Temurin JDK 17 to `D:\DevTools\jdk-17` | ~300 MB | required by the Android Gradle Plugin |
| 0.3 | Android command-line tools to `D:\DevTools\android-sdk` | ~150 MB | no Android Studio |
| 0.4 | `platform-tools`, `platforms/android-36`, `build-tools/36.0.0`; accept licences | ~430 MB | see the syntax note below |
| 0.5 | Set `ANDROID_HOME` / `ANDROID_SDK_ROOT` / `PATH`; `flutter config --android-sdk` | — | user level only, no admin needed |
| 0.6 | Run `flutter doctor` until clean | — | verification gate — **passed** |
| 0.7 | Create the companion venv and install its packages | ~400 MB | see below |

**Total: ~4.6 GB, all on `D:`.** `C:` gained almost nothing — even Gradle's and
Pub's caches were redirected to `D:`.

`flutter doctor` result: **No issues found** — Flutter, Android toolchain,
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
- **The connection is slow** — about 250 KB/s, and that cap applies to total
  bandwidth rather than per stream, so parallel downloads do not help. Flutter
  alone took roughly two hours.

### Risks

- **Python resolution.** `C:\Python315` is in the *machine* PATH, which outranks
  the user PATH, so a bare `python` in a fresh terminal still gives 3.15.
  Changing that needs admin rights, which we deliberately do not use. It does
  not affect the companion: its venv is built from `D:\DevTools\python312`, and
  inside the venv `python` is 3.12. Always activate the venv.
- **Disk space.** Far healthier than the laptop, with 125 GB free on `D:`, so
  the Gradle download is no longer a risk.
- **First Gradle build is slow** on this machine. Expected, not a fault.

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
| 0 - Toolchain | 7 | Complete |
| 1 - Freeze the contract | 4 | Complete |
| 2 - App foundation | 5 | Complete |
| 3 - Screens | 4 screens done, **settings not built** | The four tabs are complete. Task 3.5 is still the placeholder screen - see below |
| 4 - Transport | 7 | Complete, 175 tests |
| 5 - Desktop companion | 14 | Complete, 190 tests, installer built and published |
| 6 - Integration and test | 7 | In progress - happy path verified on hardware, failure cases outstanding |
| 7 - Release | 7 | In progress; site live, binaries published, keystore backed up **locally only** |
| 8 - iOS and macOS | - | Deferred on purpose, see below |

### Phase 3 correction

Phase 3 was previously marked complete. It is not, and the error was mine:
I read "four screens built and working" as "Phase 3 done" without noticing that
**task 3.5, Settings, is still a placeholder**. The screen says so — "Settings
arrive in Phase 3.5" — and behind it are the tasks the plan filed under 3.5:

- Cursor speed (the simulator supports it; nothing in the app sets it)
- Acceleration curve
- Haptics on/off
- Left-handed layout (MouseTab takes `leftHanded` and the layout already mirrors,
  but nothing passes it a value)
- Keep-screen-awake (currently hardcoded on while connected, with no way to turn
  it off)
- Safe Mode (exists on the PC only)
- Disconnect (now reachable via the back button instead)
- The paired-device list with revoke (the store has it; there is no UI for it)

The keyboard's type-and-dictate field is also unfinished: the plan calls for
voice input and Urdu via the phone's native keyboard, and the field has never
been confirmed to receive on-screen key input.

None of this blocks the product working, and the four tabs that people actually
use during a lecture are done. But "complete" was the wrong word and it should
not have been written down as such.

### What "complete" means here, and what it does not

Phases 4 and 5 are complete in the sense that both halves of the product are
built, tested against each other, and work: a real phone app that pins a
certificate and speaks the protocol, and a real companion that listens, asks
its user for permission, and performs input. 175 Flutter tests and 190 Python
tests, including tests that drive the actual Dart socket against the actual
Python companion over real TLS.

None of that is Phase 6. Every number above was produced by a machine talking
to itself. Phase 6 is where the product is actually judged.

### Verified on real hardware

Confirmed working by a person, on a physical phone driving a real Windows
machine. This is the list that matters — everything else above is a machine
agreeing with itself.

| Check | Result |
|---|---|
| Pairing from the QR code, Allow on the PC | works |
| Slides: Previous, Next, Start, End, Black | works |
| Mouse: left and right click, drag | works |
| Mouse: analog stick moves the cursor | works |
| Keyboard: letters, modifiers, shortcuts | works |
| Back button, disconnect, return to pairing | works |
| Exit from the app | works |
| Reconnecting after the screen sleeps | works |
| Start with Windows | works |

Bugs found only by this testing, all of which had passed every automated test:

- Mouse and keyboard were dead for the whole session. The tabs were built while
  the PC was still deciding whether to allow the phone, and nothing rebuilt
  them afterwards: the sink was not a `Listenable`, and the tab children were
  `const`, so Flutter skipped their subtrees. Slides only *looked* alive
  because disabled buttons still animate.
- The analog stick reached the companion and stopped there. `stick` and `move`
  were stored on the connection state and returned without ever being forwarded
  to the input layer, so 60 well-formed frames a second were accepted and
  discarded. Every other event type was forwarded, which is why only the stick
  appeared broken.
- Reconnecting never reconnected. The backoff timer fired and set the status to
  "connecting"; nothing dialled the PC.

The lesson, recorded because it cost three separate rounds of testing: a test
that asserts nothing *complained* is not a test that something *happened*.

### Pairing failure after the beta.3 PC reinstall - DIAGNOSED (2026-10-19)

**Reported by the user on real hardware 2026-10-18. Diagnosed 2026-10-19.
Cause found and the product/harness hardened accordingly.**

What happened, in the user's terms: after reinstalling `TapDesk-1.0.0-setup.exe`
from v1.0.0-beta.3 and installing the matching APK over the top of the previous
one, the QR code no longer pairs. Two symptoms: the pairing screen loads
continuously, or the app reaches the tabs and says "disconnected".

**Cause: the companion was simply not running.** On the morning after the
reinstall there was no TapDesk process, nothing listening on port 8765, and the
Run-key autostart entry was absent (autostart is off by default). A phone with
nothing to connect to produce exactly both reported symptoms: a fresh QR scan
spins forever against a closed port, and a stored pairing optimistically shows
the tabs while never connecting.

Eliminated on the way to that conclusion:

1. **Certificate regeneration - ruled out.** The reinstall landed at
   `D:\TapDesk` (not `%LOCALAPPDATA%\Programs\TapDesk` as before), but the
   config directory is `Path.home()/.tapdesk` and is independent of install
   location. The certificate there predated the reinstall; the fingerprint did
   not change.
2. **Stale certificate held by the phone - the real residual risk.** After the
   uninstall/reinstall the PC device list (`devices.json`) was empty while the
   phone still held a pairing. Any reconnect gets `E_REVOKED` and the phone
   returns to pairing, which works - but only once a running companion exists.
3. **The PyInstaller bundle differing from source - ruled out by probe.** A new
   diagnostic, `companion/tools/probe_shipped_binary.py`, drives the *installed*
   exe (never done before: all 200 Python tests run from source): it starts the
   shipped exe headless, verifies TLS + `hello_ok`, confirms an unknown device
   key is refused with `E_REVOKED` (not a hang), and confirms headless refuses a
   pairing token. The shipped binary was healthy.
4. **The packaging-bundle hypothesis therefore closed**, with a permanent probe
   so any future report can be checked against the actual product binary in
   minutes rather than guessed at.

Two genuine defects were found while confirming none of the above were to
blame, both fixed:

- **A test suite that drove the developer's real desktop.** `InputSimulator`
  fell back to `pynput` when constructed without an executor, so every
  companion started with `--headless` (the `--print-link` path, and the Dart
  cross-implementation tests) moved the real mouse and pressed real keys - the
  moving pointer and Ctrl+P print dialog the user kept hitting. Real input is
  now opt-in (`desktop_input=True`), accepted only by the windowed companion;
  headless can never inject. Locked in by `test_no_desktop_injection.py`,
  which overrides the import machinery so a headless code path reaching pynput
  fails loudly. Mutation-checked.
- **The phone blamed the network instead of naming the cause.** A connect
  failure said "check they are on the same Wi-Fi" while the actual cause was a
  companion that was not running. The message now leads with the most likely
  cause: check TapDesk is running on the computer first, Wi-Fi second.
- Also: a cross-implementation test race (a shared config directory handing
  back the previous test's pairing token) that failed only on a busy machine.

Current state of this machine after the diagnosis: old install uninstalled,
fixed companion rebuilt with the opt-in input gate and installed at
`%LOCALAPPDATA%\Programs\TapDesk`, launch verified (listening on 8765, no
startup errors) while the user tests. The firewall rule removed at uninstall
was re-added with elevation and verified with netsh: inbound TCP 8765, all
profiles, Allow - note that `Get-NetFirewallRule` answers Access denied in a
non-elevated session, which had made an earlier check report the rule as
missing; `netsh advfirewall firewall show rule name="..."` is the reliable
check on this machine.

Published v1.0.0-beta.4 (2026-10-19, release id 417284147): arm64 APK
sha `4dc3cc18…02ce2` (25.0 MB), armv7 sha `1fa1b5ee…7541c` (21.1 MB), and the
rebuilt setup.exe sha `1a10eb50…80ea5c` (58.7 MB) - all three verified
byte-identical to the local files after upload. Signer unchanged
(`02bf814f…226e20`), so the APK installs over beta.3 without an uninstall.

Note that the settings screen still has **not yet been verified on hardware at
all**, and neither has cursor speed, which was the main reason for building it.
Treat beta.4 as the build to verify them.

### The beta.4 "connecting forever" report - cause and fixes (2026-10-23)

**Reported after the settings build:** the QR would seemingly not pair; the app
said "connecting" and the loop never ended. Two things were true at once, and
only one of them was the phone's fault.

**The PC side was the actual breaker.** At the start of the session there was
no TapDesk process and nothing listening on 8765 - the sequel to the
beta.3-reinstall state recorded above. The phone did everything right and the
machine said nothing. Remedied and, this time, made to stay remedied:

- The installed companion is running again and listening on 8765.
- **Start with Windows is now enabled** (the Run key
  `HKCU\…\CurrentVersion\Run → TapDesk` points at the installed exe, set
  through `TapDesk.exe --autostart on`). It stays opt-in in the product; it is
  on here because the school of "start it by hand every class" had already
  failed twice on this machine.
- `companion/tools/probe_lan_reach.py` (untracked until now, committed) walks
  the path a phone walks - TCP to the real Wi-Fi interface, TLS with the
  fingerprint the QR advertises, hello answered with `hello_ok`. All green.

**Two genuine app defects fixed while confirming the above.** Both were found
reading the loop the user experienced rather than guessing at it:

1. **The failure reason never reached the screen.** `describeConnectFailure`
   ("Check TapDesk is running on the computer…") was delivered through
   `SessionDelegate.onError` into a `ValueNotifier` that no widget ever read.
   The banner reads only `ConnectionInfo`, so the user watched the connect /
   reconnect loop go by with never a word about what to do - which is exactly
   what "it says connecting forever" looked and felt like. Reasons now ride on
   the status snapshot itself (`session._publish`, the sink's connect-failure
   path), the controller preserves a recorded reason across the
   reconnect-wait transitions, and a fresh attempt clears it.

2. **Resuming the app could kill a healthy pairing in progress.** `retryNow()`
   fired on every `AppLifecycleState.resumed` and interrupted *any* state. On
   an attempt already dialling, handshaking, or waiting for the PC's Allow
   prompt, it tore the session down underneath the dial and re-ran it - and a
   pairing token is single-use, so the second attempt can never finish. It now
   fires only while the backoff owns the wait (`reconnecting`).

184 Flutter tests pass (six previously failing cross-implementation tests were
a port clash with the newly running companion, not a regression - they bind
8765 themselves and cannot run while the real product is listening).

Published v1.0.0-beta.5 with both fixes; the PC side is unchanged, so the
beta.4 installer remains current.


### Remaining work, in order

1. **Failure cases on hardware.** Everything above was a happy path. The bugs
   that remain are in what happens when things go wrong, and none of it is
   reachable from a unit test:
   - **No stuck keys or buttons after a disconnect** (task 6.6, and requirement
     D8). Hold Ctrl, walk out of Wi-Fi range, walk back. Ctrl must not still
     be down. This is the single most user-visible reliability promise in the
     product and it is the one most likely to be quietly broken.
   - PC sleep, then wake.
   - Revoke the phone from the PC, then reconnect from the phone.
   - Two phones, both paired.
   - Latency on a phone hotspot, not just home Wi-Fi.
2. **Task 3.5, the Settings screen.** Eight settings, most of which already
   exist in the code and need only a control. Left-handed layout and cursor
   speed are the two a user is most likely to want during a lecture.
3. **Task 7.2, off-machine keystore backup.** The local copy is made and
   verified, but it sits on the same drive as the original and so protects
   against nothing that matters. It needs to go somewhere else — a cloud
   drive, an email to yourself, a USB stick in another room.
4. **Code signing for the Windows installer.** Unsigned installers draw a
   SmartScreen warning on every user's machine. There is no cheap fix; a
   certificate has to be bought and the build has to be reproducible enough to
   keep renewing it.
5. **Task 7.7.** Play Store preparation, once the above is solid.
6. **Phase 8** remains deliberately untouched until Phase 7 has shipped.

### Phase 8 - iOS and macOS (deferred)

Not started, and deliberately not started until the Android app and the Windows
companion have passed Phase 6 on real hardware and Phase 7 has shipped.
Recorded here so the decision is not lost, not because it is imminent.

| Piece | Note |
|---|---|
| iOS app | Same Flutter codebase; needs a Mac or CI to build and sign |
| macOS companion | Port the Python companion; requires Accessibility and Screen Recording permissions, guided in-app |
| Protocol | Unchanged - `protocol.md` v1 already covers both platforms |
| Design | Unchanged - the tokens in `design-system.md` are platform-neutral |

The Phase 1 decision is what makes this cheap: because the wire protocol and
the design tokens are platform-neutral, adding these platforms is a packaging
exercise rather than a redesign. The cost of changing the contract later is
paid twice - once in Flutter and once in Python - which is why freezing it
first was worth the day.

## Reference

- Requirements: [`PRD.md`](PRD.md)
- Wire protocol v1: [`protocol.md`](protocol.md)
- Design system: [`design-system.md`](design-system.md)
- Website: [`../website/README.md`](../website/README.md)