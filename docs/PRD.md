# Product requirements

## Vision

TapDesk turns a phone into a wireless mouse, slide clicker and keyboard for a
PC or laptop. A small desktop companion shows a QR code, the phone scans it, and
the two are paired in under ten seconds — no cables, no typing IP addresses, and
no walking back to the desk mid-lecture.

## Three deliverables

| # | Deliverable | Purpose |
|---|---|---|
| 1 | **Mobile app** (Android, Flutter) | Controller UI: Slides, Mouse, Keyboard |
| 2 | **Desktop companion** (Windows first) | Receives commands, shows the pairing QR, drives the real mouse and keyboard |
| 3 | **Website** (`/website`) | Landing page with downloads: APK for the phone, installer for the computer |

An APK installs only on Android phones. A laptop needs the desktop companion
(`.exe` on Windows). The site therefore offers two download buttons.

## Goals

- Pair phone and PC in under 10 seconds via QR code.
- Control mouse, slides and keyboard with latency under 50 ms on the same Wi-Fi.
- Be simple enough for a teacher to use mid-lecture: three tabs, big buttons.
- Be secure by design — only the paired phone can control the computer.
- Publish to Google Play after a working website/APK beta.

## Non-goals (v1)

- Control over the internet, from outside the local network.
- iOS app (planned later; Flutter makes this straightforward).
- Screen mirroring or remote-desktop viewing.
- Multi-user classroom management dashboards.

## Target users

| Persona | Needs |
|---|---|
| **Teacher / lecturer** (primary) | Move slides, point and click, type a short text while walking around the class |
| **Presenter / speaker** | A clicker replacement for conferences |
| **Casual user** | Control a media PC or laptop from the couch |

## Mobile app

Top tab bar with three tabs — **Slides · Mouse · Keyboard** — the active tab
highlighted in green, plus a connection indicator and settings in the app bar.

### Pairing (first launch)

- Full-screen camera with a QR scanning frame in green corners.
- Fallback: enter the address manually (IP + 6-digit PIN).
- On success, show "Connected to *&lt;PC name&gt;*".
- Remember paired computers and reconnect automatically on next launch.

### Slides tab

- Two large buttons side by side: **&lt; Previous** and **&gt; Next**.
- Secondary row: start slideshow (F5), end (Esc), black screen (B).
- Optional: use phone volume keys as next/previous.
- Optional: haptic feedback per press, plus a slide timer.

### Mouse tab

- Analog stick in the centre — direction sets direction, distance sets speed,
  snaps back to centre on release.
- **Left button** bottom-left: tap to click, hold to drag, double-tap to
  double-click.
- **Right button** bottom-right: tap to right-click.
- Vertical scroll strip alongside the stick.
- Settings: cursor speed, acceleration curve, left-handed layout, haptics.
- Later: a touchpad mode toggle.

### Keyboard tab

- Full on-screen QWERTY including letters, numbers, Shift, Ctrl, Alt, Win, Tab,
  Esc, Backspace, Enter, Space, arrow keys and an F1–F12 row.
- Sticky modifiers, so tapping Ctrl then C sends Ctrl+C.
- Alternative: a text field using the phone's native keyboard for Unicode text
  injection and voice typing.
- Shortcut row: Copy, Paste, Undo, Alt+Tab, Win+D, Ctrl+S.

### Connection

- Always-visible state: Connecting / Connected / Disconnected.
- Auto-reconnect with backoff: 1s, 2s, 4s, up to 10s.
- "Reconnecting…" banner with controls disabled while reconnecting.
- Optional: keep the screen awake while connected.

## Desktop companion

| ID | Requirement |
|---|---|
| D1 | Runs in the system tray; optional start on login |
| D2 | Starts a WebSocket server on a free port (default 8765) on the local network |
| D3 | Main window shows a QR code (white background, black modules, green accent) with PC name and local IP |
| D4 | QR carries: protocol version, PC name, local IPs, port, one-time pairing token, public key fingerprint |
| D5 | On a successful scan, asks "Allow *&lt;Phone name&gt;* to control this computer?" → Allow / Deny |
| D6 | Lists paired devices with **Revoke** |
| D7 | Receives events and performs OS-level input: move, click, scroll, key press, text |
| D8 | Pause/Disconnect button plus a global hotkey to instantly disable control |
| D9 | Shows connection status and number of connected phones |
| D10 | Auto-detects IP changes and refreshes the QR |
| D11 | Installer creates the inbound Windows Firewall rule |

### QR payload

```json
{
  "v": 1,
  "name": "Teacher-Laptop",
  "ips": ["192.168.1.15"],
  "port": 8765,
  "token": "one-time-random-32-bytes",
  "fp": "sha256-fingerprint-of-pc-key"
}
```

Encoded as a deep link: `tapdesk://pair?data=<base64url(json)>`. The token
expires after two minutes or on first use, whichever comes first, and the QR
refreshes automatically.

## Communication protocol

JSON over WebSocket. All messages are small, validated and rate-limited on the
PC side; unknown or malformed messages are dropped.

| Event | Example |
|---|---|
| Hello / auth | `{"t":"auth","token":"…","device":"Pixel 7"}` |
| Stick (continuous) | `{"t":"stick","x":0.42,"y":-0.15}` — sent at ~60 Hz, values in −1..1 |
| Relative move | `{"t":"move","dx":5,"dy":-3}` — touchpad mode |
| Click | `{"t":"click","b":"left","a":"down\|up\|click\|double"}` |
| Scroll | `{"t":"scroll","dy":-3}` |
| Key | `{"t":"key","k":"right","a":"press"}` |
| Key combo | `{"t":"combo","keys":["ctrl","c"]}` |
| Text | `{"t":"text","s":"Hello"}` |
| Slides | `{"t":"slide","a":"next\|prev\|start\|end\|blank"}` |
| Ping / pong | `{"t":"ping","ts":…}` |

## Pairing and security

1. Desktop generates a one-time token and session keypair, and renders the QR.
2. Phone opens a TLS WebSocket (self-signed cert) and **pins** the fingerprint
   from the QR, preventing a man-in-the-middle.
3. Phone sends the token. The PC verifies it, shows the Allow / Deny prompt, and
   on Allow issues a long-lived device key — stored in the Android Keystore on
   the phone, hashed on the PC.
4. Next time the phone reconnects automatically with the device key; no re-scan.
5. The PC can revoke any device; revoked keys are rejected.

Requirements: no control without pairing; tokens single-use, time-limited and
≥128-bit random; encrypted transport; rate limiting and an input sanity filter
(max events/sec, max text length); a visible indicator on the PC with a quick
Disconnect; an optional Safe Mode that blocks risky shortcuts such as Win+R;
and no logging of keystrokes to any server.

## Performance targets

| Metric | Target |
|---|---|
| Pairing time | < 10 s |
| Input latency (same Wi-Fi) | < 50 ms (typical 10–30 ms) |
| Stick update rate | 60 Hz |
| Desktop CPU idle | < 2% |
| Mobile battery | < 5%/hour with the screen on |
| Reconnect after a Wi-Fi blip | < 5 s |

## Network notes

Phone and PC must be on the same Wi-Fi or LAN. Some school guest networks use
client isolation, which blocks device-to-device traffic — documented, with a
phone-hotspot workaround. mDNS/Bonjour discovery and a Bluetooth fallback are
later additions.

Android manifest permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `CAMERA`,
`CHANGE_WIFI_MULTICAST_STATE` (if mDNS), `VIBRATE`. Cleartext and self-signed
certificates are handled only through explicit cert-pinning code — TLS
validation is never disabled globally.

## Non-functional requirements

- **Platforms:** Android 8.0+ (API 26+); Windows 10/11 (v1), macOS 12+ and
  Ubuntu (v2).
- **Reliability:** no stuck keys or clicks; release all pressed keys and buttons
  on disconnect.
- **Accessibility:** large targets, high contrast (black/white/green passes WCAG
  AA), haptics, screen-reader labels.
- **Localisation:** English first, Urdu later; the text-injection path must
  support Unicode.
- **Privacy:** no analytics inside the apps, no personal data collected.
- **Permissions:** camera (QR) and network only.
- **macOS:** the companion requires Accessibility and Screen Recording
  permissions; guide users in-app.

## Website requirements

Nav bar: Home · About · Services · **Download** (green pill, sticky on scroll).

- **Hero** — slogan on the left, the mouse on the right, reacting to scroll:
  it moves to the centre, bursts into pixels, and the download CTA appears.
- **About** — the story, who it is for, the mission.
- **Services** — cards for slide control, wireless mouse, full keyboard, QR
  pairing and secure design.
- **How it works** — install the desktop app, scan the QR, control the PC.
- **Download** — Android APK and Windows companion cards with version, size and
  SHA-256, plus install instructions; macOS/Linux marked coming soon.
- **FAQ** — same-network requirement, the hotspot tip, safety, installing an APK.
- **Footer** — privacy policy, terms, contact, copyright.

Behaviour: detect the visitor's device and highlight the matching download;
show a short "How to install" modal; publish the SHA-256 checksum; count
downloads with privacy-friendly analytics.

Non-functional: mobile-first responsive, Lighthouse ≥ 90, white background with
black text and green accents, smooth scroll animations that respect
`prefers-reduced-motion`, HTTPS, SEO meta tags, an Open Graph image, and a
public privacy policy URL (required by the Play Store).

## Distribution

**Phase A — direct.** Build a signed release APK and back up the keystore
permanently. Build the desktop installer (PyInstaller → Inno Setup). Consider
code signing to avoid SmartScreen warnings. Upload both to GitHub Releases and
link them from the download page.

**Phase B — Play Store.** Developer account (US$25, identity verification).
Build an `.aab`. Prepare the listing: name, descriptions, 512×512 icon,
1024×500 feature graphic, 2–8 screenshots in green/white/black. Supply the
privacy policy URL, complete the Data safety form (no data collected) and the
content rating questionnaire. New personal developer accounts must run a closed
test with a minimum number of testers for a minimum period before production
access — check the current requirement in Play Console. Note in the description
that the free desktop companion is required.

## Testing plan

- **Unit:** protocol parsing, token expiry, rate limiter, key mapping.
- **Integration:** home Wi-Fi, school Wi-Fi, mobile hotspot.
- **Latency:** round-trip ping and end-to-end cursor delay.
- **Real use:** PowerPoint, Google Slides in a browser, PDF viewers, Impress.
- **Security:** connect without a token, replay an old token, use a wrong
  fingerprint, flood events, use a revoked device.
- **Devices:** at least three Android versions and screen sizes; Windows 10 and 11.
- **Failure cases:** Wi-Fi drops, PC sleep, app backgrounded, IP change, firewall
  block.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| School Wi-Fi blocks device-to-device traffic | Hotspot instructions; later Bluetooth or a relay mode |
| Windows Firewall blocks the port | Installer creates the rule; in-app troubleshooting |
| SmartScreen flags an unsigned `.exe` | Code-sign the installer; publish checksums; open-source the companion |
| A PC-control tool gets misused | Pairing plus Allow prompt, visible indicator, instant disconnect, optional Safe Mode |
| Play Store rejection | Minimal permissions, clear privacy policy, accurate listing |
| The stick feels sluggish | Tunable speed and acceleration; touchpad mode later |
| macOS permission friction | Guided in-app setup |

## Success metrics

Median pairing under 10 s with >95% success; median input latency under 50 ms;
crash-free sessions above 99%; 100 website downloads in the first month; a Play
Store rating of 4.2 or better; and 80% of surveyed teachers reporting that it
replaces their slide clicker.

## Roadmap

1. Touchpad mode and gestures — pinch zoom, three-finger swipe.
2. Teacher-only security — school accounts, PIN or biometric lock, classroom
   device whitelist.
3. mDNS auto-discovery and a Bluetooth fallback.
4. macOS and Linux companions, then an iOS app.
5. Presenter extras — laser pointer, timer, notes, slide thumbnails.
6. Media and volume remote, shortcut macros, custom button layouts.
7. Multi-PC switching, and a remote-over-internet mode with an end-to-end
   encrypted relay.

## Definition of done for v1

A teacher installs the desktop app, scans the QR with the TapDesk app, and can
move slides, use the mouse (stick with left/right click) and type on the PC —
securely and with no noticeable lag.