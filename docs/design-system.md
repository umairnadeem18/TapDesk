# TapDesk design system

**Status:** frozen for Phase 2+. Covers the Flutter app and the Python companion
window. The marketing site keeps its own light theme — this document is about
the two apps a user touches mid-lecture.

The design goal is narrow: **a teacher must find and hit the right control in
under a second, in a dim room, without looking closely.** Dark background, one
green accent, very large targets, almost no decoration.

---

## 1. Principles

1. **Dark only.** No light theme. A projector-lit room is the environment, and
   a white screen is blinding at the back of a lecture hall.
2. **One accent colour.** Green means "this is TapDesk" and "this is active".
   It is never used decoratively.
3. **Green means connected.** The connection dot is green when connected and
   red when not. Nothing else is green unless it is active or enabled.
4. **Targets are huge.** A thumb in motion, not a cursor at rest.
5. **No hidden gestures** for anything essential. Every action is a visible
   button.
6. **Never look broken.** When disconnected or reconnecting, controls disable
   with a clear banner. They never appear live and silently do nothing.

---

## 2. Colour tokens

Dark theme only. Every colour in both apps comes from this table.

| Token | Hex | Used for |
|---|---|---|
| `background` | `#0A0A0A` | screen background |
| `surface` | `#171717` | cards, tab bar, sheets |
| `surfaceElevated` | `#1F1F1F` | keys, pressed states, inputs |
| `primary` | `#16A34A` | buttons, button borders, active tab pill, focus rings |
| `primaryPressed` | `#15803D` | pressed buttons |
| `highlight` | `#86EFAC` | active accents, connection-dot glow, slider fill |
| `text` | `#FAFAFA` | labels, headings, key labels |
| `textMuted` | `#9CA3AF` | secondary labels, hints, disabled labels |
| `error` | `#DC2626` | disconnected state, validation errors |
| `warning` | `#F59E0B` | Safe Mode notices, battery/low-signal warnings |
| `divider` | `#262626` | 1 px separators |

### 2.1 Rules

- Green is reserved. A green element is either **active**, **enabled**, or
  **connected** — never merely decorative.
- Disabled controls: `surfaceElevated` background, `textMuted` label, **no
  green border**. A disabled button must not look pressable.
- Pressed = `primaryPressed` background, or `surfaceElevated` plus a `primary`
  border for outline buttons.
- Error red is only for connection failure and validation. It is never used for
  a destructive-but-unrelated action.
- Minimum contrast for any text: 4.5:1. `#9CA3AF` on `#0A0A0A` is 7.4:1,
  `#16A34A` on `#0A0A0A` is 3.4:1 — **so green is never used for small body
  text**, only for borders, fills and large labels.

---

## 3. Typography

| Role | Family | Size | Weight | Notes |
|---|---|---|---|---|
| Display | Poppins | 28 | 600 | screen titles only |
| Key label | Inter | 22 | 600 | on-screen keyboard keys |
| Button | Inter | 18 | 600 | Slides and Mouse tab buttons |
| Body | Inter | 16 | 400 | settings, descriptions |
| Label | Inter | 14 | 500 | tab labels, captions |
| Mono | JetBrains Mono | 14 | 400 | IP, fingerprint, PIN |

Poppins for headings, Inter for body, as specified in the product brief.
Both ship as bundled assets — the apps must render identically offline, since
pairing happens on a local network that may have no internet.

Labels are **never** below 14 px, and key labels never below 22 px: the phone
will be an arm's length away.

---

## 4. Spacing, shape and elevation

| Token | Value |
|---|---|
| `space1` | 4 |
| `space2` | 8 |
| `space3` | 12 |
| `space4` | 16 |
| `space5` | 24 |
| `space6` | 32 |
| `radiusCard` | 16 |
| `radiusButton` | 28 (fully rounded pill) |
| `radiusKey` | 10 |
| `borderWidth` | 2 |
| `minTouchTarget` | 56 dp |

Screen padding is `space4` (16); gaps between cards are `space3` (12).

Elevation is subtle — this is a flat dark UI:

| Level | Treatment |
|---|---|
| 0 | `background`, no shadow |
| 1 | `surface`, no shadow, 1 px `divider` border |
| 2 | `surfaceElevated`, shadow `0 4 16 rgba(0,0,0,0.5)` |

---

## 5. The app shell

```
┌──────────────────────────────────────┐
│  Teacher-Laptop        ● Connected  ⚙ │  app bar, 56 dp
├──────────────────────────────────────┤
│      ( Slides )    Mouse    Keyboard  │  tab bar, 64 dp
├──────────────────────────────────────┤
│                                      │
│              tab body                 │
│                                      │
└──────────────────────────────────────┘
```

- **Tab bar** — three equal tabs. The active tab is a `primary` pill with
  `text` label; inactive tabs are `textMuted` on transparent. Never an
  underline-only indicator: the pill is visible from across a room.
- **Connection dot** — 10 dp. Green with a `highlight` glow when connected;
  `error` red, no glow, when not; `warning` amber while connecting or
  reconnecting. It pulses at 1 Hz while reconnecting.
- **App bar** — PC name in `textMuted` (truncated to 20 chars), settings icon
  at the right, 24 dp outlined.
- **Banner** — appears below the tab bar only when not connected: *"Reconnecting
  to Teacher-Laptop…"* on `surfaceElevated` with a `warning` left border,
  `primary` spinner. All controls in the body are disabled while it shows.

---

## 6. Component specs

### 6.1 Primary button

| Property | Value |
|---|---|
| Height | 72 dp (Slides tab), 56 dp minimum elsewhere |
| Background | `primary` |
| Label | Inter 18/600, `text` on green — 4.9:1, passes AA |
| Corner | fully rounded pill |
| Pressed | `primaryPressed` |
| Disabled | `surfaceElevated` bg, `textMuted` label, no green |

### 6.2 Slide button

`<` Previous and `>` Next sit side by side, equal width, 72 dp tall, with an
outlined chevron at 40 dp above an 18 dp label. They are the two things a user
presses most, so they get the most space.

The secondary row below holds three smaller buttons — Start, End, Black — each
56 dp, `surface` background with a `primary` border and `primary` label.

Every press fires a 10 ms haptic.

### 6.3 Analog stick

- Base circle 180 dp, `surface`, 2 px `primary` border.
- Knob 76 dp, `primary` fill, `highlight` ring, sits exactly on centre at rest.
- Deflection maps to the full radius; the knob is clamped, never scaled.
- Dead zone 0.08 — inside it the knob shows as idle and no `stick` is sent.
- Two faint guide lines (horizontal and vertical) at 12% opacity for
  orientation.
- Left-handed mode mirrors the layout; the knob's behaviour is identical.

### 6.4 Click buttons

Left at bottom-left, right at bottom-right, each 96 dp circle — a circle, not a
rectangle, because it is a physical button in the user's mind. `surface`
background, `primary` border, outlined icon at 32 dp. Pressed fills `primary`
with a `text` icon.

Double-tap within 250 ms performs a double-click. Hold-and-drag is `down` on
press, `up` on release — the protocol handles it, no extra state.

### 6.5 Scroll strip

A 56 dp wide vertical strip to the right of the stick, `surface` with a rounded
`highlight` thumb 48 dp tall. Dragging moves the cursor proportionally —
scrolling is continuous, not stepped.

### 6.6 Keyboard

- Keys 48 dp tall, `radiusKey` 10, `surfaceElevated` fill, `text` label at
  Inter 22/600, `divider` border.
- Modifier keys (Shift, Ctrl, Alt, Win) are `surface` with a `primary` border;
  when latched they fill `primary` and their label turns `text` — the only way
  to see a sticky modifier is to see it lit.
- Space spans the full width; Enter, Backspace and Tab are 1.5× the standard
  key.
- F1–F12 hide behind a single `F` toggle to keep the grid to six rows.
- The text-injection field uses the phone's native keyboard, so Urdu and voice
  typing work without any layout work on our side.

### 6.7 Slider

`highlight` fill to the left of the thumb, `divider` to the right, 4 dp track,
20 dp thumb with a `primary` ring. Minimum 56 dp tall hit area even though the
visual is thinner.

### 6.8 Pairing screen

Full-bleed camera preview, dimmed 40% with black. A scanning frame of four
`primary` corner brackets, 240 dp square, 4 dp thick, `highlight` glow. Below
it, a `surface` sheet with the manual-entry option as a text button.

Permission rationale is shown *before* the system dialog — a short screen
explaining that the camera is only used to read the pairing code.

---

## 7. Companion window

The companion follows the same tokens. It is a native window, not a web page.

| Element | Spec |
|---|---|
| Window | 380 × 480 dp, `background`, rounded 12 |
| QR | white background, black modules, quiet zone ≥ 4 modules, ~260 dp — white is required, a dark QR scans badly |
| PC name | Poppins 20/600, `text`, centred, truncated at 24 chars |
| IP and port | JetBrains Mono 14, `textMuted`, centred |
| PIN | JetBrains Mono 28/700, `highlight` — only shown when the manual fallback is needed |
| Fingerprint | JetBrains Mono 10, `textMuted`, wrapped, with a copy button |
| Status row | connection dot in the same colours as the app |
| Primary action | 56 dp button, `primary` fill — pair / disconnect |
| Device rows | `surface`, 56 dp, name in `text`, IP in `textMuted`, Revoke as a `error` text button |

The QR regenerates every 120 s and on any pairing attempt, and the window
refreshes immediately when the machine's IP changes.

---

## 8. Motion

| Interaction | Duration | Curve |
|---|---|---|
| Tab change | 150 ms | ease-out |
| Button press | 80 ms | ease-out |
| Stick knob | follows the finger at 60 Hz, no easing | — |
| Banner appear | 200 ms | ease-out |
| Connection dot pulse | 1000 ms loop while reconnecting | ease-in-out |

The analog stick is the exception: it must track the thumb with no smoothing,
or the cursor will feel like it is lagging.

All non-essential animation is disabled under `prefers-reduced-motion`
(Flutter: `MediaQuery.disableAnimations`), leaving state changes instant.

---

## 9. Accessibility

Binding, not optional:

- Every interactive element has a minimum 56 dp hit area, even where the visual
  is smaller.
- Labels use Inter at 14 px or larger, meeting 4.5:1.
- Meaning is never carried by colour alone — a disabled button also loses its
  green border, a latched modifier also changes fill, a disconnected state also
  shows text.
- Every control has a semantic label for TalkBack, e.g. *"Next slide"*,
  *"Left mouse button"*, *"Sticky control"*.
- Haptics fire on Slides and Mouse presses; they are configurable but default
  to on.
- The connection state is announced by a live region, so TalkBack says
  *"Connected to Teacher-Laptop"* without the user hunting for the dot.

---

## 10. Branding marks

- **App icon** — white mouse silhouette on `#0A0A0A`, with a single `#16A34A`
  cursor arrow. Must read at 48 dp.
- **Tray icon** — 16 dp monochrome mouse outline. Windows wants a small
  monochrome glyph; green is only for the tray tooltip highlight.
- **Companion window title bar** — dark `#0A0A0A`, so the window does not flash
  white on a dark desktop.
- **QR colours are fixed** at black-on-white regardless of theme — scanners
  need the contrast.

---

## 11. Checklist for implementers

- [ ] No colour outside §2 appears anywhere in either app.
- [ ] Green is used only for active, enabled or connected.
- [ ] Every target ≥ 56 dp, verified on the smallest supported screen.
- [ ] Disabled controls lose their green border, not just their opacity.
- [ ] Controls disable with a visible banner when not connected.
- [ ] Connection dot is green / amber / red and pulses while reconnecting.
- [ ] Sticky modifiers are visibly latched, not merely remembered.
- [ ] Fonts are bundled; nothing loads from the network.
- [ ] TalkBack labels on every control; live region on connection state.
- [ ] Reduced-motion disables all animation except the analog stick.
