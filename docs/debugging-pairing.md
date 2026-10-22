# Pairing debugging log — the phone never connects

State as of 2026-10-23 ~03:15, end of the beta.6 session. Written so the next
session starts at the diagnosis rather than rediscovering it. Textbook lesson so
far: every layer *below* the phone's own code is healthy; the failure is a
silent break inside the phone's scan→dial chain, and beta.6's on-screen trace
was built precisely to make that break nameable.

## What is proven healthy (do not re-test these)

| Layer | Evidence |
| --- | --- |
| Companion server on 0.0.0.0:8765 | `netstat` LISTENING, Dart probe (see `mobile/tool/probe_phone.dart`) completes hello→hello_ok→auth against the real companion |
| Cert / fingerprint pinning | Same cert since 01:40, fp `eab4983affaabfccd8e7fab3ad58c852eb761ad386256c06a7640257b46660a6`; the Dart probe pins and connects with it |
| QR content | `pairing.link` payload decodes to valid JSON: name DESKTOP-6A0NO24, ips [192.168.2.110], port 8765, 43-char token, 64-hex fp; the phone's strict parser accepts it (trace said "QR accepted") |
| Network path PC↔phone | Both on Wi-Fi UMAIR; PC probe dials itself via the Wi-Fi IP fine; phone reached the PC at 01:26 and 01:54 (pre-beta.6) and at 02:11–02:12 |
| Phone app version | beta.6 confirmed installed (the trace strip exists and speaks) |
| PC-side log observability | `~\.tapdesk\companion.log` names every accept/hello/auth refusal |

## The hard timeline (all timestamps local, 2026-10-23)

- **01:26, 01:54 (beta.5)**: phone (192.168.2.102) connects — TCP + TLS + **WebSocket
  upgrade complete** ("connection open" ×3, then ×7) — and sends **zero bytes**;
  all sockets close ~2 s later. No hello, no auth, nothing in the log between.
- **02:11–02:12 (beta.5, with peer instrumentation)**: same pattern, peer named:
  `connection accepted from ('192.168.2.102', …)` ×5, server's 5 s hello-timeout
  closes each (`no hello … closing`). Retry spacing ~15-20 s = app-side backoff loop.
- **02:17 Dart probe from the PC** using the phone's own `PinnedSocket` code:
  hello_ok + auth_err (E_BAD_TOKEN with a placeholder token) — the *whole wire
  and server* are fine for a Dart client that actually sends.
- **02:52–02:58 (beta.6, user test)**: trace strip on the phone:
  1. `02:52:11 no remembered computer` ← fresh install, correct
  2. `02:53:19 QR accepted: TapDesk code for DESKTOP-6A0NO24` ← scan parses fine
  3. **…nothing.** No `scanned:` line, no `connect:` line. The older lines were
     still on the strip at 02:57, proving `connectTo` never ran on the scan path
     (it calls `trace.reset()` first — the 02:52/02:53 lines would be gone).
  4. Remembered-card click (02:57:41) — the *new* refusal path works exactly as
     designed: `saved device key: none` → `no pairing token and no saved key:
     scan the QR again` → `status: connection failed (forgotten pairing)`.
  5. Third scan: `_busy` spinner ("pairing loading") never ends.
- **companion.log during 02:52–02:58: NOTHING.** The phone never opened a single
  connection. The PC never saw the token, so no dialog — exactly as reported.

## Root cause (as localized by beta.6)

**The phone's scan→dial chain dies silently between `remember(payload)` and
`sink.connectTo(payload, token: payload.token)`.** Everything after the scan
parses works; nothing after it runs. In
`mobile/lib/screens/pairing_screen.dart` `_onDetect`:

```dart
_busy = true;
await _scanner?.stop();
trace.add('QR accepted: …');        // ← last line the user ever saw
if (!mounted) return;               // ← silent gate #1
await context.read<PairingStore>().remember(payload);
// remember() → notifyListeners → _Root rebuilds (hasPaired=true)
//               → PairingScreen is swapped out for AppShell
if (!mounted) return;               // ← silent gate #2 — prime suspect
await Haptics.confirm();            // ← await on a platform channel
widget.onPaired?.call(payload);     // ← never reached, or reached and silenced
```

Note remember() *did* complete: the "paired computers" card (192.168.2.110:8765)
it creates was there at 02:57 — it cannot have survived from launch, because the
02:52 line said `no remembered computer`. So the break is strictly in the
continuation after remember: an unmount/`mounted` swallow, a platform-channel
`Haptics.confirm()` hang, or `_onPaired` throwing before its first trace line —
in a release build, any of those is *invisible* (no error surface at all).

Two defects ride along:

1. `_busy = true` is set and **never reset** in the success path — the design
   assumed the screen would be replaced. Scan #3 kept the screen (_onHome was
   true), so the spinner showed forever even though a rebuild-driven navigation
   was all that ever happens. Any await that never returns leaves a dead spinner.
2. The AppShell shows on `hasPaired` alone, ungated from connection state — so
   the user lands in controls "not connected" with no dial having ever happened,
   which has looked like five different bugs when it is this one.

## Also established

- The remembered path *would* have worked correctly if a key existed: since the
  PC's `devices.json` was wiped and the phone-side key was revoked+forgotten in
  an earlier session, EVERY remembered dial is (correctly) refused with
  "scan the QR again". Fixing scan→dial is therefore *sufficient* for pairing.
- beta.6's companion had zero users to greet: no `connection accepted from
  192.168.2.102` lines at all during the test — the phone never dialed.

## Next session's fix plan (in order)

1. **Make the scan path unmount-proof.** `_onDetect` must not strand the pairing
   callback behind its own screen's lifecycle. Capture the payload first; call
   `widget.onPaired(payload)` through a path that runs regardless of whether the
   pairing screen is still mounted (e.g. have `_Root` own the scan→remember→pair
   sequence, or invoke onPaired *before* the awaited navigation-driving state
   change, or drop the `if (!mounted) return;` gates in that continuation).
2. **Never block pairing on haptics.** `await Haptics.confirm();` →
   `unawaited(Haptics.confirm());` (also move it before remember so its position
   in an async chain cannot matter).
3. **Reset `_busy` in a `finally`**, and on dispose, so a spinner can never hang
   forever.
4. **Surface async errors in release**: install `FlutterError.onError` and
   `PlatformDispatcher.instance.onError` handlers that `trace.add(...)` — one
   line each. Tonight's silent throw, whatever it was, would have named itself.
   Also wrap the `widget.onPaired(payload)` call in try/catch → trace.
5. Add trace lines at `_onPaired` entry and immediately after `remember()`
   returns inside `_onDetect`, so the exact surviving instruction is visible.
6. Rebuild → beta.7 → user scans. Expected correct outcome on the strip:
   `QR accepted` → `scanned: 192.168.2.110:8765 token=yes` → `connect …
   token=yes` → `dialing` → `socket open` → `sent 2 frames` → `PC: hello_ok` →
   `PC: auth_pending` (PC shows the approval dialog) → `status: Connected`.
7. **Wipe the analyzer debt**: `flutter analyze` currently reports 18 issues
   (mostly pre-existing unused imports / relative-import lint in tests, plus
   `tool/probe_phone.dart`). Clean them all so analyze exits clean; decide
   whether `tool/probe_phone.dart` stays (then fix its import to `package:`)
   or gets deleted once pairing is proven fixed.

## Tool-chain notes for whoever runs the next build

- `flutter test` needs TapDesk.exe killed first (cross-implementation tests bind
  8765/8876); relaunch the companion detached afterwards.
- Release APKs: `powershell -ExecutionPolicy Bypass -File build-release.ps1`.
  Publishing: use `powershell -Command "& { .\publish-release.ps1 -Tag …
  -Body (Get-Content … -Raw) }"` — **`-File` does not evaluate inline
  expressions**; beta.6's first publish set the body to the literal string
  `(Get-Content` and skipped the APKs (fixed by re-running via `-Command` and
  PATCHing the body through the API).
- Website deploy recipe (temp copy outside the repo + Vercel API
  rootDirectory→null + link + deploy --prod), and **always restore
  `rootDirectory: "website"` afterwards** — done at 03:07 this time.
- Release: v1.0.0-beta.6 (id 421232254); arm64 sha256
  `c022aa784ce019b3e9f97fb02b69664ea755d1c89dfd798d85f7ff14754b11ae`, v7a
  `2c17c32d5a3b188db9143630cf0458b1ea849ccca78a248aac0b8b25bbd870f9`; all asset
  URLs verified 200; website serves beta.6.
