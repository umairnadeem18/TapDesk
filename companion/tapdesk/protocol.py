"""The wire protocol, mirrored from `docs/protocol.md` section 4.

Every constant here exists so that this side and the Flutter side cannot drift:
the key ids, the enums and the field names are written out explicitly rather
than being invented at the call site. A typo becomes an ImportError or a failed
test, not a message the companion silently drops.
"""

from __future__ import annotations

import json
from typing import Any, Final

PROTOCOL_VERSION: Final = 1

# Maximum frame size, section 1. Anything larger is rejected, not truncated.
MAX_FRAME_BYTES: Final = 8192

# Rate limits, section 5. Expressed as (per_second, burst).
RATE_LIMITS: Final = {
    "stick": (120, 30),
    "key": (60, 20),
    "click": (60, 20),
    "combo": (60, 20),
    "slide": (60, 20),
    "move": (60, 20),
    "scroll": (60, 20),
    "text": (10, 10),
    "ping": (1, 1),
}
OVERALL_RATE_LIMIT: Final = (240, 60)
MAX_TEXT_CHARS: Final = 500
TEXT_CHARS_PER_SECOND: Final = 2000

# Error codes, section 6.1.
E_UNSUPPORTED_VERSION: Final = "E_UNSUPPORTED_VERSION"
E_MALFORMED: Final = "E_MALFORMED"
E_UNAUTHENTICATED: Final = "E_UNAUTHENTICATED"
E_BAD_TOKEN: Final = "E_BAD_TOKEN"
E_TOKEN_EXPIRED: Final = "E_TOKEN_EXPIRED"
E_TOKEN_USED: Final = "E_TOKEN_USED"
E_DENIED: Final = "E_DENIED"
E_REVOKED: Final = "E_REVOKED"
E_BAD_FIELD: Final = "E_BAD_FIELD"
E_TOO_LARGE: Final = "E_TOO_LARGE"
E_RATE_LIMITED: Final = "E_RATE_LIMITED"
E_WRONG_FP: Final = "E_WRONG_FP"
E_AUTH_FAILED_KEY: Final = "E_BAD_TOKEN"
E_UNSAFE: Final = "E_UNSAFE"

# Close codes, section 6.2.
CLOSE_NORMAL: Final = 1000
CLOSE_SHUTDOWN: Final = 1001
CLOSE_AUTH_FAILED: Final = 4001
CLOSE_UNSUPPORTED_VERSION: Final = 4002
CLOSE_REVOKED: Final = 4003
CLOSE_RATE_LIMITED: Final = 4004
CLOSE_WRONG_FP: Final = 4005
CLOSE_PAIRING_BUSY: Final = 4006
CLOSE_INTERNAL: Final = 1011

# --- keyboards -----------------------------------------------------------

ARROWS: Final = frozenset({"up", "down", "left", "right"})
EDITING: Final = frozenset(
    {"enter", "tab", "backspace", "delete", "insert", "esc", "space"}
)
MODIFIERS: Final = frozenset({"shift", "ctrl", "alt", "win"})
LOCKS: Final = frozenset({"capslock", "numlock", "scrolllock"})
NAVIGATION: Final = frozenset({"home", "end", "pgup", "pgdn"})
PUNCTUATION: Final = frozenset(
    {
        "minus",
        "equal",
        "lbracket",
        "rbracket",
        "backslash",
        "semicolon",
        "apostrophe",
        "grave",
        "comma",
        "period",
        "slash",
    }
)
OTHER: Final = frozenset({"printscreen", "pause", "menu"})

FUNCTION_KEYS: Final = frozenset(f"f{i}" for i in range(1, 13))

#: Every key id the companion will accept. Section 4.3.
KEY_IDS: Final = (
    frozenset("abcdefghijklmnopqrstuvwxyz")
    | frozenset("0123456789")
    | FUNCTION_KEYS
    | ARROWS
    | EDITING
    | MODIFIERS
    | LOCKS
    | NAVIGATION
    | PUNCTUATION
    | OTHER
)

MOUSE_BUTTONS: Final = frozenset({"left", "right", "middle"})

#: Ranges the companion accepts for a `set`, and clamps to rather than
#: rejecting. A phone asking for a cursor speed of 400 gets 4.0 and is told so;
#: refusing outright would leave the user with a slider that does nothing and
#: no explanation. The lower bound is well under 1 so "slower than normal" is
#: actually reachable, which presenters driving a large screen need.
CURSOR_SPEED_RANGE: Final = (0.25, 4.0)
ACCEL_RANGE: Final = (1.0, 3.0)
CLICK_ACTIONS: Final = frozenset({"down", "up", "click", "double"})
KEY_ACTIONS: Final = frozenset({"press", "release", "tap"})
SLIDE_ACTIONS: Final = frozenset({"next", "prev", "start", "end", "blank"})

#: How a slide action becomes a real key, section 4.4. The phone sends only
#: the action; deciding what it means is this side's job, because PowerPoint,
#: Impress and a PDF viewer all disagree about what "next" is.
#:
#: ONE key is sent, not both. The first value is the one performed; the second
#: is only a fallback to try if the first demonstrably does nothing, which
#: cannot be detected from here. Pressing both would advance the deck twice
#: per click, which is worse than pressing the wrong single key.
SLIDE_KEYS: Final = {
    "next": "pgdn",
    "prev": "pgup",
    "start": "f5",
    "end": "esc",
    "blank": "b",
}

#: What to try when the primary key does nothing, chosen by the user in
#: settings. Referenced, never sent automatically.
SLIDE_FALLBACKS: Final = {
    "next": "right",
    "prev": "left",
    "start": "f5",
    "end": "esc",
    "blank": "b",
}

#: Chord sizes allowed, section 4.3.
MIN_COMBO_KEYS: Final = 1
MAX_COMBO_KEYS: Final = 4

#: Safe Mode allow list, section 7.8. Anything matching is refused with
#: E_UNSAFE rather than performed.
BLOCKED_CHORDS: Final = frozenset(
    {
        ("win", "r"),
        ("win", "x"),
        ("ctrl", "alt", "del"),
        ("win", "l"),
    }
)


class ProtocolError(Exception):
    """A message the companion refuses.

    Carries the code from section 6.1 so the caller can report exactly why,
    and so the phone gets a reason rather than silence.
    """

    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code
        self.detail = detail


def encode(message: dict[str, Any]) -> str:
    """Serialise one message. One JSON object per frame, no newline."""
    text = json.dumps(message, separators=(",", ":"), ensure_ascii=False)
    size = len(text.encode("utf-8"))
    if size > MAX_FRAME_BYTES:
        raise ProtocolError(E_TOO_LARGE, f"{size} bytes")
    return text


def decode(text: str) -> dict[str, Any]:
    """Parse one frame.

    Raises [ProtocolError] for anything malformed. Never returns a partially
    parsed message, because acting on half a command is worse than dropping it.
    """
    if len(text.encode("utf-8")) > MAX_FRAME_BYTES:
        raise ProtocolError(E_TOO_LARGE)
    try:
        parsed = json.loads(text)
    except (ValueError, TypeError) as exc:
        raise ProtocolError(E_MALFORMED, str(exc)) from exc
    if not isinstance(parsed, dict):
        raise ProtocolError(E_MALFORMED, "not an object")
    kind = parsed.get("t")
    if not isinstance(kind, str) or not kind:
        raise ProtocolError(E_MALFORMED, "missing t")
    return parsed


def _require_str(message: dict[str, Any], field: str) -> str:
    value = message.get(field)
    if not isinstance(value, str):
        raise ProtocolError(E_BAD_FIELD, f"{field} is not a string")
    return value


def _require_number(message: dict[str, Any], field: str) -> float:
    value = message.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProtocolError(E_BAD_FIELD, f"{field} is not a number")
    return float(value)


def _require_int(message: dict[str, Any], field: str) -> int:
    value = message.get(field)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ProtocolError(E_BAD_FIELD, f"{field} is not an integer")
    return value


def _require_enum(
    message: dict[str, Any], field: str, allowed: frozenset[str]
) -> str:
    value = _require_str(message, field)
    if value not in allowed:
        raise ProtocolError(E_BAD_FIELD, f"{field}={value!r}")
    return value


def _optional_range(
    message: dict[str, Any], field: str, limits: tuple[float, float]
) -> float | None:
    """Read an optional numeric field, checking it is inside `limits`.

    Returns None when the field is absent, which is not an error and not zero:
    `set` is a partial update, so a phone changing only Safe Mode sends only
    Safe Mode. Defaulting an absent field to 0 would silently reset a setting
    the user never touched.
    """
    if field not in message:
        return None
    value = _require_number(message, field)
    low, high = limits
    if not low <= value <= high:
        raise ProtocolError(E_BAD_FIELD, f"{field}={value} outside {low}-{high}")
    return value


def is_blocked(chord: list[str]) -> bool:
    """Whether Safe Mode refuses this chord, in either order."""
    normalised = tuple(sorted(chord))
    return any(
        normalised == tuple(sorted(blocked)) for blocked in BLOCKED_CHORDS
    )


def validate(message: dict[str, Any]) -> None:
    """Check one input message against the catalogue.

    Raises [ProtocolError] on anything invalid. An unknown ``t`` is *not* an
    error - section 4 says unknown message types are dropped and counted, so
    that an old phone talking to a newer companion degrades quietly.
    """
    kind = message.get("t")

    if kind == "stick":
        x = _require_number(message, "x")
        y = _require_number(message, "y")
        if not -1.0 <= x <= 1.0 or not -1.0 <= y <= 1.0:
            raise ProtocolError(E_BAD_FIELD, "stick out of range")
        return

    if kind == "move":
        _require_int(message, "dx")
        _require_int(message, "dy")
        return

    if kind == "click":
        _require_enum(message, "b", MOUSE_BUTTONS)
        _require_enum(message, "a", CLICK_ACTIONS)
        return

    if kind == "scroll":
        _require_int(message, "dy")
        return

    if kind == "key":
        key = _require_str(message, "k")
        if key not in KEY_IDS:
            raise ProtocolError(E_BAD_FIELD, f"unknown key {key!r}")
        _require_enum(message, "a", KEY_ACTIONS)
        return

    if kind == "combo":
        keys = message.get("keys")
        if not isinstance(keys, list):
            raise ProtocolError(E_BAD_FIELD, "keys is not a list")
        if not MIN_COMBO_KEYS <= len(keys) <= MAX_COMBO_KEYS:
            raise ProtocolError(E_BAD_FIELD, f"{len(keys)} keys in a chord")
        for key in keys:
            if not isinstance(key, str) or key not in KEY_IDS:
                raise ProtocolError(E_BAD_FIELD, f"unknown key {key!r}")
        if is_blocked(keys):
            raise ProtocolError(E_UNSAFE, "+".join(keys))
        return

    if kind == "text":
        text = _require_str(message, "s")
        if len(text) > MAX_TEXT_CHARS:
            raise ProtocolError(E_BAD_FIELD, "text too long")
        # Newline and tab are legitimate; other control characters are not,
        # because injecting them has no meaning and can confuse a shell.
        if any(ord(ch) < 32 and ch not in "\n\t" for ch in text):
            raise ProtocolError(E_BAD_FIELD, "control character in text")
        return

    if kind == "slide":
        _require_enum(message, "a", SLIDE_ACTIONS)
        return

    if kind == "ping":
        _require_int(message, "ts")
        return

    if kind == "set":
        # A partial update: only the fields present are changed. Validating the
        # range here rather than trusting the phone means a phone claiming a
        # cursor speed of 400 cannot make the pointer unusable, and the value
        # that gets applied is echoed back so the screen can show the truth.
        present = False
        if _optional_range(message, "cursorSpeed", CURSOR_SPEED_RANGE) is not None:
            present = True
        if _optional_range(message, "accel", ACCEL_RANGE) is not None:
            present = True
        if "safeMode" in message:
            if not isinstance(message["safeMode"], bool):
                raise ProtocolError(E_BAD_FIELD, "safeMode must be a boolean")
            present = True
        if not present:
            raise ProtocolError(E_BAD_FIELD, "set carried no settings")
        return

    if kind == "forget":
        # No fields. This phone is asking to be unpaired, which the companion
        # treats exactly like the Revoke button in its window.
        return

    # Unknown type: counted and dropped, not an error.
    return
