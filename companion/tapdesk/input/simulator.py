"""Performing input on this computer.

The stick is the reason this is not just a loop over the plan.

The phone streams the stick at 60 Hz, but Windows will not move the cursor
faster than its own refresh, and calling `mouse.move` sixty times a second
produces a visible stutter - the exact symptom remote-control apps are
complained about. So the stick is held as the latest value and applied on a
fixed 60 Hz timer instead, with the speed, dead zone and curve from section 4.2
applied here. A drag therefore costs one timer tick per frame regardless of how
fast the phone is sending.

Everything held is tracked so it can be released. A phone that dies mid-drag
would otherwise leave a mouse button or a modifier down on the desktop, and the
user has no way to see why their computer is behaving oddly.
"""

from __future__ import annotations

import logging
import math
import time
from dataclasses import dataclass, field
from typing import Any, Callable

from . import planner

log = logging.getLogger("tapdesk.input")

#: Section 4.2. Full deflection moves this many pixels per tick.
MAX_SPEED = 25.0

#: Below this the stick is treated as centred, so a resting thumb does not
#: drift the cursor across the screen.
DEAD_ZONE = 0.08

#: Above 1 this gives fine control near the centre at the cost of top speed.
CURVE = 1.6

TICK_HZ = 60
TICK_SECONDS = 1.0 / TICK_HZ


@dataclass
class HeldState:
    """What is currently down, so it can all be let go again."""

    keys: set[str] = field(default_factory=set)
    buttons: set[str] = field(default_factory=set)

    def clear(self) -> None:
        self.keys.clear()
        self.buttons.clear()


class InputSimulator:
    """Applies plans to the desktop.

    `executor` is injected so the run loop can be driven without moving a real
    mouse. In production it wraps `pynput`; in tests it records.
    """

    def __init__(
        self,
        executor: Callable[[tuple], None] | None = None,
        max_speed: float = MAX_SPEED,
        dead_zone: float = DEAD_ZONE,
        curve: float = CURVE,
    ) -> None:
        self._execute = executor or self._default_executor
        self.max_speed = max_speed
        self.dead_zone = dead_zone
        self.curve = curve

        self.held = HeldState()
        self.stick = (0.0, 0.0)
        self.stick_updated = 0.0

        self.pending_move = (0, 0)
        self.cursor_speed = 1.0

    # -- stick -------------------------------------------------------------

    def set_stick(self, x: float, y: float) -> None:
        self.stick = (x, y)
        self.stick_updated = time.monotonic()

    def stick_delta(self) -> tuple[int, int]:
        """Pixels to move this tick, given the current stick value.

        Called on a fixed timer. Applies the dead zone, the curve and the
        user's speed setting, and returns whole pixels because that is all the
        OS will accept.
        """
        x, y = self.stick

        if time.monotonic() - self.stick_updated > 0.5:
            # The phone stopped sending without releasing. Treating a stale
            # stick as still deflected would slide the cursor forever.
            return 0, 0

        magnitude = math.hypot(x, y)
        if magnitude < self.dead_zone:
            return 0, 0

        # Normalise to 1.0 on the dead zone, then apply the curve. Raising the
        # magnitude above 1 means the centre is precise and the edge is fast.
        strength = ((magnitude - self.dead_zone) / (1.0 - self.dead_zone)) ** self.curve
        scale = strength / magnitude if magnitude else 0.0

        speed = self.max_speed * self.cursor_speed
        return (
            int(round(x * scale * speed)),
            # +y is up on the wire, screen coordinates count downward, so this
            # is negated. Forgetting that sends the cursor the wrong way, which
            # feels like the stick being broken rather than inverted.
            -int(round(y * scale * speed)),
        )

    def tick(self) -> None:
        """One 60 Hz step: apply the stick, then any coalesced movement."""
        dx, dy = self.stick_delta()
        if dx or dy:
            self.execute(("move", dx, dy))
        if self.pending_move != (0, 0):
            move_x, move_y = self.pending_move
            self.pending_move = (0, 0)
            self.execute(("move", move_x, move_y))

    # -- events ------------------------------------------------------------

    def handle(self, message: dict[str, Any]) -> None:
        """Apply one validated protocol event."""
        kind = message["t"]

        if kind == "stick":
            self.set_stick(float(message["x"]), float(message["y"]))
            return

        if kind == "move":
            self.pending_move = (
                self.pending_move[0] + int(message["dx"]),
                self.pending_move[1] + int(message["dy"]),
            )
            return

        if kind == "ping":
            return

        plan = planner.plan(message)
        for action in plan.actions:
            self.execute(action)
        # `plan.release` is deliberately NOT run here. It exists to describe
        # what must be let go of if this session dies, and running it
        # immediately would cancel a deliberate hold - pressing Ctrl and
        # releasing it in the same breath makes a held modifier useless.
        # Held keys are tracked in `self.held` and released by release_all().

    def execute(self, action: tuple) -> None:
        """Run one action, tracking what it leaves held."""
        kind = action[0]

        if kind == "key":
            _, key, state = action
            if state == "down":
                self.held.keys.add(key)
            else:
                self.held.keys.discard(key)
        elif kind == "button":
            _, button, state = action
            if state == "down":
                self.held.buttons.add(button)
            else:
                self.held.buttons.discard(button)

        self._execute(action)

    def release_all(self) -> None:
        """Let go of everything.

        Section 7.10, and the single most user-visible reliability guarantee in
        the product: a disconnected app must never leave the desktop in a state
        the user cannot diagnose.
        """
        for key in sorted(self.held.keys):
            self._execute(("key", key, "up"))
        for button in sorted(self.held.buttons):
            self._execute(("button", button, "up"))
        self.stick = (0.0, 0.0)
        self.pending_move = (0, 0)
        self.held.clear()

    # -- the real desktop --------------------------------------------------

    def _default_executor(self, action: tuple) -> None:
        """Perform an action with pynput.

        Imported lazily so the module can be imported - and tested - on a
        machine with no desktop session, such as CI.
        """
        try:
            from pynput import keyboard, mouse
        except ImportError:  # pragma: no cover - desktop only
            log.warning("pynput unavailable; input will not be performed")
            return

        kind = action[0]

        if kind == "move":
            mouse.Controller().move(action[1], action[2])
        elif kind == "scroll":
            mouse.Controller().scroll(0, action[1])
        elif kind == "button":
            name, state = action[1], action[2]
            button = {
                "left": mouse.Button.left,
                "right": mouse.Button.right,
                "middle": mouse.Button.middle,
            }[name]
            getattr(mouse.Controller(), button)(state == "down")
        elif kind == "key":
            self._press_key(action[1], action[2])
        elif kind == "text":
            self._type_text(action[1])

    def _press_key(self, key_id: str, state: str) -> None:
        from pynput.keyboard import Controller

        controller = Controller()
        action = controller.press if state == "down" else controller.release

        literal = _PYNPUT_LITERAL.get(key_id)
        if literal is not None:
            # pynput's Key enum has no punctuation members at all - comma,
            # slash and the rest are typed as literal characters.
            action(literal)
            return

        special = _PYNPUT_SPECIAL.get(key_id)
        if special is not None:
            # Named keys are Key *members*, not controller methods with
            # matching names - `controller.ctrl` does not exist. An earlier
            # version assumed it did and raised AttributeError the first time
            # a real key was pressed.
            action(special)
            return

        if len(key_id) == 1:
            # Letters and digits are single characters already.
            action(key_id)
            return

        log.debug("no desktop mapping for key %r", key_id)

    def _type_text(self, text: str) -> None:
        from pynput.keyboard import Controller

        controller = Controller()
        for character in text:
            try:
                controller.type(character)
            except (TypeError, ValueError):
                # Characters pynput cannot synthesise - some emoji, for
                # instance. Skipped rather than aborting the whole string, so a
                # single unsupported glyph does not lose the message.
                log.debug("cannot type %r", character)


def _build_specials() -> dict[str, Any]:
    """Canonical key id to the pynput `Key` member that represents it.

    Only named keys appear here. Letters, digits and punctuation are typed
    literally and need no entry, so leaving them out keeps one thing to keep in
    step rather than two.
    """
    from pynput.keyboard import Key

    names = {
        "up": "up",
        "down": "down",
        "left": "left",
        "right": "right",
        "enter": "enter",
        "tab": "tab",
        "backspace": "backspace",
        "delete": "delete",
        "insert": "insert",
        "esc": "esc",
        "space": "space",
        "shift": "shift",
        "ctrl": "ctrl",
        "alt": "alt",
        "capslock": "caps_lock",
        "numlock": "num_lock",
        "scrolllock": "scroll_lock",
        "home": "home",
        "end": "end",
        "pgup": "page_up",
        "pgdn": "page_down",
        "printscreen": "print_screen",
        "pause": "pause",
        "menu": "menu",
    }
    names.update({f"f{i}": f"f{i}" for i in range(1, 13)})

    mapping: dict[str, Any] = {}
    for key_id, name in names.items():
        member = getattr(Key, name, None)
        if member is not None:
            mapping[key_id] = member

    # The Windows key is spelled differently per platform: cmd on macOS,
    # cmd_l / cmd_r on Windows. Resolved defensively so this module imports
    # everywhere and the Windows key still works here.
    for candidate in ("cmd_l", "cmd", "cmd_r"):
        member = getattr(Key, candidate, None)
        if member is not None:
            mapping["win"] = member
            break

    return mapping


_PYNPUT_SPECIAL: dict[str, Any] = _build_specials()
#: Punctuation key ids to the literal character to type.
#:
#: pynput's Key enum genuinely has no punctuation members - it is arrows,
#: modifiers and function keys only - so comma, slash and the rest are typed as
#: characters. Verified against the enum rather than assumed, after an earlier
#: version looked for members that do not exist.
_PYNPUT_LITERAL: dict[str, str] = {
    "minus": "-",
    "equal": "=",
    "lbracket": "[",
    "rbracket": "]",
    "backslash": "\\",
    "semicolon": ";",
    "apostrophe": "'",
    "grave": "`",
    "comma": ",",
    "period": ".",
    "slash": "/",
}