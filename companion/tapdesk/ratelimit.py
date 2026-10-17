"""Rate limiting.

Section 5 of `docs/protocol.md`.

The limit exists to stop a rogue or compromised phone from flooding the PC
with input. Two kinds of message need different treatment:

  * Discrete events (a key press, a click) that would each be a real action.
    Over the limit, they are **dropped** and the phone is told E_RATE_LIMITED.

  * Continuous streams (`stick`, `move`) where dropping frames would make the
    cursor stutter. Over the limit, they are **coalesced**: `move` deltas are
    summed so the cursor keeps up, and `stick` keeps only the newest value,
    because an older stick position is worthless the moment a newer one exists.

Dropping movement entirely would be the easy choice and would produce a cursor
that lags behind the thumb, which is the single most complained-about symptom
in remote-control software.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field


@dataclass
class TokenBucket:
    """A classic token bucket: `rate` per second, up to `burst`."""

    rate: float
    burst: float
    tokens: float = field(init=False)
    updated: float = field(default_factory=time.monotonic)

    def __post_init__(self) -> None:
        self.tokens = self.burst

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self.updated
        if elapsed <= 0:
            return
        self.tokens = min(self.burst, self.tokens + elapsed * self.rate)
        self.updated = now

    def allow(self, amount: float = 1.0) -> bool:
        """Take `amount` tokens if they are available."""
        self._refill()
        if self.tokens >= amount:
            self.tokens -= amount
            return True
        return False

    @property
    def available(self) -> float:
        self._refill()
        return self.tokens


@dataclass
class TextBudget:
    """Characters per second, on top of the per-message count limit.

    A flood of legal 500-character messages would otherwise pass the
    messages-per-second limit while still flooding the PC with keystrokes.
    """

    chars_per_second: float
    burst: float
    tokens: float = field(init=False)
    updated: float = field(default_factory=time.monotonic)

    def __post_init__(self) -> None:
        self.tokens = self.burst

    def allow(self, length: int) -> bool:
        now = time.monotonic()
        elapsed = now - self.updated
        if elapsed > 0:
            self.tokens = min(self.burst, self.tokens + elapsed * self.chars_per_second)
            self.updated = now
        if self.tokens >= length:
            self.tokens -= length
            return True
        return False


class RateLimiter:
    """Per-connection limiter covering every class in the protocol."""

    def __init__(
        self,
        rates: dict[str, tuple[int, int]],
        overall: tuple[int, int],
        text_chars_per_second: int = 2000,
    ) -> None:
        self._rates = rates
        self._buckets = {
            kind: TokenBucket(rate, burst) for kind, (rate, burst) in rates.items()
        }
        self._overall = TokenBucket(*overall)
        self._text = TextBudget(
            chars_per_second=text_chars_per_second,
            burst=text_chars_per_second,
        )

    def allow(self, kind: str) -> bool:
        """Whether a message of this type may be acted on now.

        Coalescing messages (stick, move) should not call this - they are
        handled by their own path so they degrade rather than disappear.
        """
        if not self._overall.allow():
            return False
        bucket = self._buckets.get(kind)
        return bucket.allow() if bucket is not None else True

    def allow_text(self, length: int) -> bool:
        return self.allow("text") and self._text.allow(length)

    def allow_move(self, dx: int, dy: int) -> tuple[int, int]:
        """Coalesce a relative move, returning the total to apply.

        Saturates rather than growing without bound: a single absurd delta
        would otherwise fling the cursor across the screen.
        """
        bucket = self._buckets.get("move")
        if bucket is None:
            return dx, dy
        if bucket.allow():
            return dx, dy
        self._pending_move = (
            self._pending_move[0] + dx,
            self._pending_move[1] + dy,
        )
        total = self._pending_move
        if abs(total[0]) > 500 or abs(total[1]) > 500:
            # Cap, and do not carry the excess into the next batch.
            self._pending_move = (0, 0)
            return (500 if total[0] > 0 else -500, 500 if total[1] > 0 else -500)
        return total

    _pending_move: tuple[int, int] = (0, 0)

    def flush_move(self) -> tuple[int, int]:
        """Take the coalesced delta, leaving zero behind."""
        total = self._pending_move
        self._pending_move = (0, 0)
        return total
