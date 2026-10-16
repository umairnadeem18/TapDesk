# TapDesk protocol v1

**Status:** frozen for Phase 2+. Both the Flutter app and the Python companion
are written from this document. If the code and this document disagree, the
document is wrong and must be corrected before either side proceeds.

This document defines the QR payload, the handshake, every message either side
may send or receive, error codes, rate limits and the security rules. It is
deliberately precise — "roughly these fields" is not good enough when two
independent implementations have to agree.

---

## 1. Transport

| Property | Value |
|---|---|
| Protocol | WebSocket over TLS |
| URL | `wss://<ip>:<port>/` |
| TLS | server presents a self-signed certificate |
| Trust | **pinned** — SHA-256 of the certificate's DER bytes, taken from the QR |
| Frame contents | one UTF-8 JSON **object** per frame, no trailing newline |
| Max frame size | 8192 bytes — larger is rejected, not truncated |
| Min TLS version | 1.2 |

Both apps accept the pinned certificate **only** for the fingerprint named in
the QR payload. TLS validation is never disabled globally, and there is no
"trust all certificates" path anywhere in the code. A certificate whose
fingerprint does not match the pinned value is a hard failure
(`E_WRONG_FP`), not a prompt.

The certificate is generated once per installation and stored next to the
companion's config. Its fingerprint is stable across restarts, so the phone
keeps trusting it without re-scanning.

### 1.1 Fingerprint format

Lowercase hexadecimal, **no separators**, exactly 64 characters — the SHA-256
digest of the DER-encoded certificate.

```
fp = "3f9a1c7e5b2d84016c9eab34df7021ee889a0c5b41d2e6f7a3b8c9d0e1f2a3b4c"
```

Rejected: uppercase, `:` separators, base64, any length other than 64.

### 1.2 Network assumptions

Phone and PC share a LAN or Wi-Fi network. Client-isolated guest networks will
not carry device-to-device traffic; a phone hotspot is the documented
workaround. No NAT traversal, no relay, no internet mode in v1.

---

## 2. QR payload and deep link

The companion renders this JSON, base64url-encodes it **without padding**, and
embeds it in a deep link:

```
tapdesk://pair?d=<base64url(json)>
```

### 2.1 Schema

| Field | Type | Required | Rules |
|---|---|---|---|
| `v` | integer | yes | protocol version, currently `1` |
| `name` | string | yes | PC display name, 1–32 chars, may contain spaces |
| `ips` | array of string | yes | 1–4 candidate IPv4 addresses, most likely first |
| `port` | integer | yes | 1024–65535, normally `8765` |
| `token` | string | yes | 32 random bytes, base64url, 43 chars |
| `fp` | string | yes | certificate fingerprint, see §1.1 |

```json
{
  "v": 1,
  "name": "Teacher-Laptop",
  "ips": ["192.168.1.15", "192.168.1.22"],
  "port": 8765,
  "token": "kQ8vZ2rT5xW9bN3mL7pA1sD4fG6hJ0kY2uC8eV1iO5nM",
  "fp": "3f9a1c7e5b2d84016c9eab34df7021ee889a0c5b41d2e6f7a3b8c9d0e1f2a3b4c"
}
```

### 2.2 Token lifetime

- 32 bytes from a cryptographically secure random source.
- Expires **120 seconds** after the QR is rendered.
- Consumed on **first use**, whether the attempt succeeded or failed.
- A rejected or expired token forces a fresh scan — the phone never retries a
  token on its own.

The companion therefore re-renders the QR every 120 seconds, and immediately
after any successful or failed pairing attempt. The app treats a scan as valid
only if the decoded payload passes §2.3; otherwise it shows the manual-entry
fallback.

### 2.3 Validation on the phone

Reject and offer manual entry when: the scheme is not `tapdesk://`; `d` is
missing or not valid base64url; the JSON is not an object; `v` is not `1`;
`ips` is empty; `port` is out of range; `token` or `fp` fails its format rule.

The app tries `ips` in order and moves to the next address on connect failure,
with a short timeout (~3 s) per address.

### 2.4 Manual pairing fallback

Identical outcome to a scan, entered by hand:

```json
{ "v": 1, "ip": "192.168.1.15", "port": 8765, "pin": "483920", "fp": "3f9a…" }
```

`pin` is a 6-digit numeric rendering of the same one-time token. The manual
flow therefore needs the PC name and fingerprint visible in the companion
window — the window shows the PIN, the fingerprint, and the IP beside the QR.

---

## 3. Handshake

### 3.1 First-time pairing

```
Phone                                    Companion
  |                                           |
  | 1  TCP + TLS connect (pinned to fp)        |
  |------------------------------------------>|
  |                                           |
  | 2  {"t":"hello","v":1,                     |
  |      "device":"Pixel 7",                   |
  |      "platform":"android",                 |
  |      "appVersion":"1.0.0"}                 |
  |------------------------------------------>|
  |                                           |
  | 3  {"t":"hello_ok","v":1,                  |
  |      "pc":{"name":"Teacher-Laptop"}}        |
  |------------------------------------------>|
  |                                           |
  | 4  {"t":"auth","token":"kQ8v…"}             |
  |------------------------------------------>|
  |                                           |
  | 5  {"t":"auth_pending","device":"Pixel 7", |
  |      "ip":"192.168.1.44"}        (Allow/Deny prompt shown)
  |<------------------------------------------|
  |                                           |
  | 6a {"t":"auth_ok","deviceId":"d_7f3a…",    |
  |       "deviceKey":"bG9s…", "ttl":0}        |
  |<------------------------------------------|   (user pressed Allow)
  |                                           |
  | 6b {"t":"auth_err","code":"E_DENIED"}      |
  |<------------------------------------------|   (user pressed Deny)
  |                                           |
  | 7  {"t":"welcome", ...}                    |
  |<------------------------------------------|
```

Steps 1–4 must complete within **5 seconds**; the phone closes the socket if the
companion has not answered `hello` by then.

The phone shows *"Waiting for approval on Teacher-Laptop…"* on step 5. There is
no timeout on the user's decision — a teacher may take a while to notice the
prompt.

**The device key is issued only on step 6a.** On 6b the phone stores nothing
and returns to the scanner.

### 3.2 Reconnecting a paired device

No QR, no prompt, no token:

```
  | 1  TLS connect (pinned to the stored fp)
  | 2  {"t":"hello","v":1,"device":"Pixel 7","platform":"android","appVersion":"1.0.0"}
  | 3  {"t":"hello_ok","v":1,"pc":{"name":"Teacher-Laptop"}}
  | 4  {"t":"auth","key":"bG9s…"}
  | 5  {"t":"auth_ok","deviceId":"d_7f3a…"}      (no deviceKey - already known)
```

`ttl` is omitted on reconnect, meaning "no expiry in v1".

### 3.3 Device key

| Property | Value |
|---|---|
| Length | 32 random bytes, base64url (43 chars) |
| Stored on phone | Android Keystore via `flutter_secure_storage` |
| Stored on PC | **SHA-256 hash only** — the key itself is never written to disk |
| Scope | one PC, one phone; bound to the PC's `deviceId` |

The PC compares the presented key by hashing it and comparing in constant time.
A stolen PC config therefore does not let an attacker impersonate a phone.

### 3.4 Companion state machine

```
   idle ──start──▶ listening ──socket──▶ handshaking ──hello──▶
                                                    │
                            token ──────────────────┤
                                                    ▼
                                            awaiting_approval ──Allow──▶ authenticated
                                                    │                        │
                                                 Deny                     event
                                                    ▼                        │ loop
                                                 rejected <─────────────────┘
                                                                        disconnect
                                                                            │
                                                                            ▼
                                                                         listening
```

A socket that fails at any step is closed with the appropriate close code (§6.2)
and the companion returns to `listening`.

### 3.5 Phone state machine

```
 idle ──scan/entry──▶ connecting ──TLS ok──▶ handshaking ──auth──▶
                          │                                      │
                          │                              awaiting_approval
                          │                                      │
                     connect fails                        ┌─────┴─────┐
                          │                            allowed       denied
                          ▼                               ▼          ▼
                     reconnecting ──backoff──▶ idle    connected   idle
                                                   │
                                              socket closes
                                                   ▼
                                             reconnecting
```

Backoff for `reconnecting`: 1 s, 2 s, 4 s, 8 s, then 10 s forever. Any
successful `auth_ok` resets the backoff to 1 s.

`connected` is the only state in which controls are enabled. In every other
state the UI shows a clear banner and disables input — inputs are never queued
silently.

---

## 4. Message catalogue

Every message is a JSON object with a string `t` field. Unknown `t` values are
dropped and counted, never fatal.

### 4.1 Handshake and session

| Direction | Message | Fields |
|---|---|---|
| → | `hello` | `v` int, `device` string ≤64, `platform` `"android"`, `appVersion` string ≤16 |
| ← | `hello_ok` | `v` int, `pc.name` string |
| → | `auth` | exactly one of `token` (43 chars) or `key` (43 chars) |
| ← | `auth_pending` | `device` string, `ip` string |
| ← | `auth_ok` | `deviceId` string, `deviceKey` string (first pairing only), `ttl` int (optional) |
| ← | `auth_err` | `code` from §6.1 |
| ← | `welcome` | `maxText` int, `stickHz` int, `serverTime` int (unix ms) |
| ↔ | `ping` | `ts` int, unix milliseconds |
| ↔ | `pong` | `ts` int (echoed unchanged), `st` int (server unix ms) |
| → | `bye` | `reason` string ≤32 |

### 4.2 Pointer

| Message | Fields | Notes |
|---|---|---|
| `stick` | `x` float −1..1, `y` float −1..1 | ~60 Hz, continuous. **+y is up.** Sent only while the stick is off-centre |
| `move` | `dx` int, `dy` int | touchpad mode, relative pixels, **−y is up** |
| `click` | `b` `left\|right\|middle`, `a` `down\|up\|click\|double` | `down`+`up` gives a drag |
| `scroll` | `dy` int | ticks; **positive scrolls up**, away from the user |

Stick tuning, all companion-side and configurable from the phone:

| Parameter | Default | Meaning |
|---|---|---|
| dead zone | 0.08 | \|x\| and \|y\| below this are ignored |
| max speed | 25 px/tick at full deflection | scaled by the user's cursor-speed setting |
| curve | 1.6 | exponent; >1 gives fine control near centre |

The companion holds the **last** stick value and keeps applying it each tick
until a new value arrives. A stick stream that stops mid-deflection therefore
keeps the cursor moving; the phone sends `x:0,y:0` on release.

### 4.3 Keyboard

| Message | Fields | Notes |
|---|---|---|
| `key` | `k` key id, `a` `press\|release\|tap` | `tap` is press+release |
| `combo` | `keys` array of 1–4 key ids | chords, e.g. `["ctrl","c"]` |
| `text` | `s` string | Unicode injection, ≤ `maxText` chars (default 500) |

**Key ids** are lowercase ASCII. These are the only accepted strings:

| Group | Ids |
|---|---|
| Letters | `a`–`z` |
| Digits | `0`–`9` |
| Function | `f1`–`f12` |
| Arrows | `up` `down` `left` `right` |
| Editing | `enter` `tab` `backspace` `delete` `insert` `esc` `space` |
| Modifiers | `shift` `ctrl` `alt` `win` |
| Locks | `capslock` `numlock` `scrolllock` |
| Navigation | `home` `end` `pgup` `pgdn` |
| Punctuation | `minus` `equal` `lbracket` `rbracket` `backslash` `semicolon` `apostrophe` `grave` `comma` `period` `slash` |
| Other | `printscreen` `pause` `menu` |

Any other value is `E_BAD_FIELD` and dropped. Text characters are **not** sent
as `key` — printable characters go through `text`, so Unicode works everywhere
and no character table is needed on the PC.

`text` rejects control characters other than `\n` and `\t`; everything else
printable in Unicode is allowed, including Urdu and emoji.

### 4.4 Slides

| Message | Fields |
|---|---|
| `slide` | `a` = `next\|prev\|start\|end\|blank` |

Companion-side mapping (the phone sends only the action, never a key):

| Action | Keys sent |
|---|---|
| `next` | `pagedown`, falling back to `right` |
| `prev` | `pageup`, falling back to `left` |
| `start` | `f5` |
| `end` | `esc` |
| `blank` | `b` |

### 4.5 Companion → phone

| Message | Fields | Notes |
|---|---|---|
| `auth_err` | `code` | see §6.1 |
| `welcome` | `maxText`, `stickHz`, `serverTime` | once, after `auth_ok` |
| `pong` | `ts`, `st` | latency probe |
| `shutdown` | `reason` | companion is exiting |
| `revoked` | — | this device was revoked; phone must forget the key |
| `settings` | `cursorSpeed` int, `accel` float, `safeMode` bool | pushed when the PC-side settings change |

---

## 5. Rate limits and limits

Enforced per connection. Exceeding a limit yields `E_RATE_LIMITED` for discrete
events, and silent coalescing for continuous ones — a flood must never queue
work faster than it can be performed.

| Class | Messages | Limit |
|---|---|---|
| Continuous | `stick` | 120/s, burst 30 — excess values are dropped, keeping the newest |
| Discrete input | `key` `click` `combo` `slide` `move` `scroll` | 60/s, burst 20 |
| Text | `text` | 10/s, 500 characters each |
| Session | `ping` | 1/s |
| Overall | everything | 240 messages/s |
| Frame size | any | 8192 bytes |

`move` events beyond the limit are **coalesced** by summing, not dropped, so a
fast touchpad swipe stays smooth.

Text is also capped per second in aggregate (2000 characters) to stop a
long-paste flood from locking the PC.

---

## 6. Errors

### 6.1 Error codes

Sent as `{"t":"auth_err","code":"…"}` during the handshake, or as a close code
afterwards. Errors never carry free-form detail — a malformed message from an
unknown device learns the attacker nothing.

| Code | Meaning | Client response |
|---|---|---|
| `E_UNSUPPORTED_VERSION` | protocol `v` is not 1 | show "update the app"; stop retrying |
| `E_MALFORMED` | not valid JSON, or not an object | drop, count |
| `E_UNAUTHENTICATED` | input before `auth_ok` | drop, count |
| `E_BAD_TOKEN` | token malformed or unknown | re-scan required |
| `E_TOKEN_EXPIRED` | older than 120 s | re-scan required |
| `E_TOKEN_USED` | already consumed | re-scan required |
| `E_DENIED` | user pressed Deny | return to scanner |
| `E_REVOKED` | device revoked on the PC | delete stored key; return to scanner |
| `E_BAD_FIELD` | unknown key id, bad enum, out-of-range number | drop, count |
| `E_TOO_LARGE` | frame over 8192 bytes | close |
| `E_RATE_LIMITED` | over a §5 limit | drop; back off |
| `E_WRONG_FP` | certificate fingerprint mismatch | **fatal** — refuse to connect |
| `E_UNSAFE` | blocked by Safe Mode | show a brief notice; do not retry |

### 6.2 WebSocket close codes

| Code | Meaning |
|---|---|
| 1000 | normal close (`bye` sent) |
| 1001 | companion shutting down (`shutdown` sent first) |
| 4001 | authentication failed |
| 4002 | unsupported protocol version |
| 4003 | device revoked |
| 4004 | rate limit exceeded repeatedly — back off 30 s |
| 4005 | certificate fingerprint mismatch |
| 4006 | pairing already pending for another device |
| 1011 | companion internal error |

A phone that receives any code it does not recognise closes cleanly, drops to
`reconnecting`, and applies the §3.5 backoff.

---

## 7. Security requirements

These are binding on both implementations, not aspirations.

1. **Pinning, never trust-all.** The self-signed certificate is trusted only
   because its fingerprint came from the QR. No global TLS bypass, no
   `badCertificateCallback` that returns true, in either app.
2. **Nothing works before pairing.** Every event from an unauthenticated socket
   is dropped and counted.
3. **Explicit human approval.** The first pairing of a device always shows the
   Allow/Deny prompt with the phone's reported name and IP. There is no
   auto-approve, no "trust this network", and no remembered-network bypass.
4. **Tokens are single-use and short-lived.** 32 bytes, 120 s, consumed on
   first attempt. Replay is `E_TOKEN_USED` or `E_TOKEN_EXPIRED`.
5. **The PC stores only hashes** of device keys, and compares in constant time.
6. **Revocation is immediate.** A revoked `deviceId` is rejected on the next
   connection, and the phone deletes its stored key when it sees `revoked`.
7. **Bounded input.** Rate limits, frame-size cap and text cap from §5 are
   enforced before any work is performed.
8. **Safe Mode** blocks risky chords by default-allow list — at minimum
   `win+r`, `win+x`, `ctrl+alt+del` — answering `E_UNSAFE`. It is on by default
   and the phone shows when it is blocking something.
9. **Always-visible state.** The companion shows a tray indicator and a window
   with connected-device count and an instant Disconnect button, plus a global
   hotkey that drops all control immediately.
10. **No stuck input.** On disconnect, for any reason, every key and button the
    companion believes is down is released.
11. **Nothing leaves the machine.** There is no TapDesk server. Keystrokes are
    never logged to disk or sent anywhere except the paired PC.

---

## 8. Versioning

`v` is an integer. v1 clients must refuse anything above 1 rather than
half-understand it, and the companion must refuse a client whose major version
differs — both answer `E_UNSUPPORTED_VERSION` and close with 4002.

Additive changes that stay inside v1: new optional fields on existing messages,
new `t` values (ignored by old clients, by §4), new error codes. Anything that
changes the meaning of an existing field is a new version.

---

## 9. Worked examples

Latency probe — the phone sends `ts`, the companion echoes it unchanged:

```
→ {"t":"ping","ts":1763308800123}
← {"t":"pong","ts":1763308800123,"st":1763308800131}
```
Round trip is the client's own clock difference; the companion never adjusts
`ts`.

Continuous stick while the thumb is pushed right and up:

```
→ {"t":"stick","x":0.42,"y":0.15}
→ {"t":"stick","x":0.44,"y":0.16}
→ {"t":"stick","x":0.0,"y":0.0}     ← on release
```

Typing Urdu into a slide:

```
→ {"t":"text","s":"السلام"}
```

Chord and slide control:

```
→ {"t":"combo","keys":["ctrl","shift","p"]}
→ {"t":"slide","a":"next"}
```

Malformed input — all three are dropped silently and counted:

```
→ {"t":"key","k":"super","a":"press"}     ← unknown key id
→ {"t":"stick","x":1.4,"y":0}            ← out of range
→ not json at all
```

---

## 10. Checklist for implementers

- [ ] Accepts `tapdesk://pair?d=` **and** the manual `{ip, port, pin, fp}` form.
- [ ] Validates the fingerprint format before trusting it (§1.1).
- [ ] Tries each IP in `ips` in order, ~3 s timeout each.
- [ ] Shows a visible waiting state during `auth_pending`.
- [ ] Stores the device key in the platform keystore, never in plain prefs.
- [ ] Enables controls only in `connected`; disables with a banner otherwise.
- [ ] Backoff 1/2/4/8/10 s, reset on success.
- [ ] Sends `stick` only while off-centre, and `0,0` on release.
- [ ] Enforces §5 before acting, coalescing `move` rather than dropping it.
- [ ] Releases every held key on disconnect (§7.10).
- [ ] Never disables TLS validation globally.
