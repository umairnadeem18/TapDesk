# TapDesk mobile

The Flutter controller app for Android: **Slides · Mouse · Keyboard**.

Built from [`../docs/protocol.md`](../docs/protocol.md) and
[`../docs/design-system.md`](../docs/design-system.md). Those two documents are
the contract — if the code disagrees with them, one of them is wrong.

## Requirements

Everything lives on `D:` — see [`D:\DevTools\verify.ps1`](../../../../DevTools/verify.ps1)
for a one-command health check.

| Tool | Version | Path |
|---|---|---|
| Flutter | 3.47.7 (Dart 3.13.5) | `D:\DevTools\flutter` |
| JDK | Temurin 17 | `D:\DevTools\jdk-17` |
| Android SDK | platform 36, build-tools 36 | `D:\DevTools\android-sdk` |
| Android NDK | 28.2.13676358 | `D:\DevTools\android-sdk\ndk\28.2.13676358` |

Open a **new** terminal after installing so PATH changes take effect.

## Running

```bash
cd mobile
flutter pub get
flutter analyze          # must be clean
flutter test             # 12 tests
flutter run              # with a physical Android 8+ phone attached
```

Build a debug APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build-apk.ps1
```

Output: `build\app\outputs\flutter-apk\app-debug.apk`.

Both build scripts are detached and log to a file, because the first Gradle
build downloads a great deal on a slow connection and an interrupted build is
wasted time.

## Layout

```
lib/
  main.dart                     app entry, theme wiring, portrait lock
  theme/tokens.dart             every colour, size and duration from the design system
  state/connection_controller.dart  the nine connection states + 1/2/4/8/10s backoff
  ui/app_shell.dart             app bar, tab bar, settings route
  ui/connection_indicators.dart connection dot and the reconnect banner
  screens/                      Phase 3 — Slides, Mouse, Keyboard, Settings, pairing
  transport/                    Phase 4 — WebSocket, certificate pinning, event builders
```

## Rules this codebase follows

These are not style preferences; breaking them breaks a documented requirement.

1. **No hard-coded colours or magic numbers.** Use `tokens.dart`. If a value
   is genuinely missing, add it to `docs/design-system.md` first.
2. **`connected` is the only state that enables controls.** Every other state
   disables input and shows a banner. Inputs are never queued silently.
3. **Green means active, enabled or connected.** Nothing else. Disabled
   controls lose their green border rather than just fading.
4. **Never disable TLS validation globally.** The companion's self-signed
   certificate is trusted only because its fingerprint was pinned from the QR.
   There is no trust-all path anywhere in this app.
5. **The device key goes in the Android Keystore** via `flutter_secure_storage`,
   never in `shared_preferences`.
6. **Minimum 56 dp touch target**, and every control gets a semantic label.
7. **Portrait only.** Rotating mid-lecture must not reflow controls under the
   user's thumb.

## Current state

Phase 2 of [`../docs/PLAN.md`](../docs/PLAN.md) is done: the app scaffolds,
compiles, has the dark theme, and the shell is real — tabs, connection dot,
reconnect banner and the disable-when-disconnected rule all work.

The tab bodies are placeholders that say which phase fills them in. The
transport does not exist yet, so nothing is sent to a PC.

## Gotchas on this machine

Recorded because each one cost real time and none is obvious from the code.

- **`sdkmanager` uses slash notation now** — `platforms/android-36`, not
  `platforms;android-36`. The old form fails with a misleading
  "Package not found".
- **`sdkmanager` hangs on the NDK package.** No output, no network activity,
  never finishes. `install-ndk.ps1` fetches the archive from Google directly
  and lays it out the way the SDK manager would.
- **Flutter's Gradle plugin auto-installs the NDK with the semicolon syntax**,
  which cannot succeed on a current machine, so the build dies with
  "Android sdkmanager did not install NDK". Having the NDK already installed
  makes Flutter skip that broken path entirely. This is a Flutter bug, not a
  misconfiguration here.
- **`path_provider_android` is pinned to 2.2.23** in `pubspec.yaml`. Version
  2.3.x pulls in `jni`, which compiles C++ and drags the NDK into every
  build. Revisit when a newer release ships prebuilt binaries.
- **Fonts are bundled, not fetched.** `assets/fonts/fetch-fonts.ps1` downloads
  the 11 weights once. They are assets because pairing happens on a local
  network that may have no internet.
