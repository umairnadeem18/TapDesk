"""Turning protocol events into concrete input actions.

Split from the thing that performs them so the translation can be tested.
`pynput` moves a real cursor on a real desktop, which no test can assert
against; the plan - "Ctrl down, C down, C up, Ctrl up" - is pure data and
every interesting decision lives here.

An action is a tuple:

    ("move", dx, dy)              relative pointer movement in pixels
    ("button", name, down|up)     left / right / middle
    ("scroll", ticks)             positive is up
    ("key", key_id, down|up)      a canonical key id
    ("text", string)              Unicode to type literally

Keeping the vocabulary this small means the executor is a lookup table rather
than a second implementation of the rules.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable

from .. import protocol as p

Action = tuple


@dataclass
class KeyPlan:
    """What to do, plus what must be released afterwards.

    `release` is the important field: an interrupted session that leaves Ctrl
    held down leaves the user's desktop in a state they cannot see the cause of.
    Everything that presses something also records how to let it go.
    """

    actions: list[Action] = field(default_factory=list)
    release: list[Action] = field(default_factory=list)

    def __bool__(self) -> bool:
        return bool(self.actions)


def plan_slide(action: str) -> KeyPlan:
    """Expand a slide action into the key that performs it.

    Exactly one key is pressed. The protocol lists a fallback for each action,
    but pressing both would advance the deck twice per click, so the fallback
    is only used when the user has told us the primary does not work.
    """
    key = p.SLIDE_KEYS.get(action)
    if not key:
        return KeyPlan()
    return KeyPlan(actions=[("key", key, "down"), ("key", key, "up")])


def plan_combo(keys: Iterable[str]) -> KeyPlan:
    """Press modifiers, tap the final key, then release the modifiers.

    The releases are part of `actions`, not a separate list, because a chord
    that pressed its modifiers and never released them would leave Ctrl latched
    on the user's desktop for the rest of the session.
    """
    key_list = list(keys)
    if not key_list:
        return KeyPlan()

    modifiers = list(key_list[:-1])
    final = key_list[-1]

    actions: list[Action] = [("key", key, "down") for key in modifiers]
    actions.append(("key", final, "down"))
    actions.append(("key", final, "up"))
    actions.extend(("key", key, "up") for key in reversed(modifiers))

    return KeyPlan(
        actions=actions,
        release=[("key", key, "up") for key in modifiers],
    )


def plan_key(key: str, action: str) -> KeyPlan:
    """A single named key.

    `press` is a HOLD. It deliberately does not release: the phone is holding
    it down, and the matching release arrives as its own message or happens at
    teardown. Releasing immediately would make a held modifier useless.
    """
    if key not in p.KEY_IDS:
        return KeyPlan()
    if action == "tap":
        return KeyPlan(actions=[("key", key, "down"), ("key", key, "up")])
    if action in ("press", "down"):
        return KeyPlan(actions=[("key", key, "down")], release=[("key", key, "up")])
    if action in ("release", "up"):
        return KeyPlan(actions=[("key", key, "up")])
    return KeyPlan()


def plan_click(button: str, action: str) -> KeyPlan:
    """A mouse click.

    `down` alone is a drag and has nothing to release on its own; the simulator
    holds the button and releases it when the socket closes.
    """
    if button not in p.MOUSE_BUTTONS:
        return KeyPlan()
    if action == "click":
        return KeyPlan(
            actions=[("button", button, "down"), ("button", button, "up")]
        )
    if action == "double":
        return KeyPlan(
            actions=[
                ("button", button, "down"),
                ("button", button, "up"),
                ("button", button, "down"),
                ("button", button, "up"),
            ]
        )
    if action == "down":
        return KeyPlan(actions=[("button", button, "down")])
    if action == "up":
        return KeyPlan(actions=[("button", button, "up")])
    return KeyPlan()


def plan_scroll(ticks: int) -> KeyPlan:
    return KeyPlan(actions=[("scroll", ticks)]) if ticks else KeyPlan()


def plan_text(text: str) -> KeyPlan:
    """Unicode injection.

    Typed literally rather than mapped through a key table, which is the only
    reason Urdu and emoji work at all. Control characters were rejected at
    validation, so anything reaching here is printable or a newline.
    """
    return KeyPlan(actions=[("text", text)]) if text else KeyPlan()


def plan_move(dx: int, dy: int) -> KeyPlan:
    return KeyPlan(actions=[("move", dx, dy)]) if (dx or dy) else KeyPlan()


def plan(message: dict[str, Any]) -> KeyPlan:
    """Translate one validated protocol event."""
    kind = message["t"]

    if kind == "slide":
        return plan_slide(message["a"])
    if kind == "combo":
        return plan_combo(message["keys"])
    if kind == "key":
        return plan_key(message["k"], message["a"])
    if kind == "click":
        return plan_click(message["b"], message["a"])
    if kind == "scroll":
        return plan_scroll(int(message["dy"]))
    if kind == "text":
        return plan_text(message["s"])
    if kind == "move":
        return plan_move(int(message["dx"]), int(message["dy"]))

    # stick is applied by the run loop at 60 Hz from the latest value, not
    # per message: applying 60 discrete small moves per second looks nothing
    # like a smooth cursor.
    return KeyPlan()
