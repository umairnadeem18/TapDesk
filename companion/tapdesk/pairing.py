"""One-time pairing tokens, the QR payload and its deep link.

Section 2 of `docs/protocol.md`. The QR is the whole pairing story: it carries
everything the phone needs to open a pinned TLS connection and ask permission,
which is why its validation is strict and its token is short-lived.
"""

from __future__ import annotations

import base64
import json
import secrets
import time
from dataclasses import dataclass, field
from typing import Any, Final

from .protocol import PROTOCOL_VERSION

#: Section 2.2. Two minutes, and consumed on first use either way.
TOKEN_TTL_SECONDS: Final = 120

#: 32 bytes, base64url, unpadded - so 43 characters.
TOKEN_BYTES: Final = 32
TOKEN_LENGTH: Final = 43

DEEP_LINK_SCHEME: Final = "tapdesk://pair"
DEEP_LINK_KEY: Final = "d"


def new_token() -> str:
    """A fresh 32-byte token, base64url encoded without padding."""
    raw = secrets.token_bytes(TOKEN_BYTES)
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def is_valid_token(value: object) -> bool:
    """Whether a string has the shape of a token, without checking its age."""
    return (
        isinstance(value, str)
        and len(value) == TOKEN_LENGTH
        and all(c.isalnum() or c in "-_" for c in value)
    )


@dataclass
class PairingToken:
    """A one-time token with an expiry.

    `consume` exists because a token must be spent whether or not the pairing
    it authorised succeeded. Letting a failed attempt leave the token alive
    would mean an attacker who guessed a PIN could keep retrying.
    """

    value: str = field(default_factory=new_token)
    created_at: float = field(default_factory=time.monotonic)
    consumed: bool = False

    @property
    def expired(self) -> bool:
        return (time.monotonic() - self.created_at) > TOKEN_TTL_SECONDS

    @property
    def remaining_seconds(self) -> int:
        return max(0, int(TOKEN_TTL_SECONDS - (time.monotonic() - self.created_at)))

    def matches(self, candidate: object) -> bool:
        """Compare in constant time; the PIN path is guessable by design."""
        if not is_valid_token(candidate) or not is_valid_token(self.value):
            return False
        return secrets.compare_digest(str(candidate), self.value)

    def consume(self) -> None:
        self.consumed = True

    def valid(self) -> tuple[bool, str]:
        """Whether this token may still be used, and why not."""
        if self.consumed:
            return False, "E_TOKEN_USED"
        if self.expired:
            return False, "E_TOKEN_EXPIRED"
        return True, ""


@dataclass(frozen=True)
class QRPayload:
    """What the QR code encodes, section 2.1."""

    name: str
    ips: tuple[str, ...]
    port: int
    token: str
    fingerprint: str

    @property
    def version(self) -> int:
        return PROTOCOL_VERSION

    def to_dict(self) -> dict[str, Any]:
        return {
            "v": PROTOCOL_VERSION,
            "name": self.name,
            "ips": list(self.ips),
            "port": self.port,
            "token": self.token,
            "fp": self.fingerprint,
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), separators=(",", ":"))

    def to_deep_link(self) -> str:
        """`tapdesk://pair?d=<base64url(json)>`, padding stripped."""
        encoded = (
            base64.urlsafe_b64encode(self.to_json().encode("utf-8"))
            .decode("ascii")
            .rstrip("=")
        )
        return f"{DEEP_LINK_SCHEME}?{DEEP_LINK_KEY}={encoded}"


def is_valid_ipv4(value: object) -> bool:
    if not isinstance(value, str):
        return False
    parts = value.split(".")
    if len(parts) != 4:
        return False
    for part in parts:
        if not part.isdigit() or len(part) > 3:
            return False
        if len(part) > 1 and part[0] == "0":
            return False
        if not 0 <= int(part) <= 255:
            return False
    return True


def is_valid_fingerprint(value: object) -> bool:
    """64 lowercase hex characters, no separators.

    Strictly lowercase and unseparated on purpose: the phone pins this string
    against a certificate digest, and a value that needs normalising is a value
    we should not be quietly cleaning up before comparing it.
    """
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(c in "0123456789abcdef" for c in value)
    )


def validate_payload(payload: dict[str, Any]) -> tuple[bool, str]:
    """Check a decoded payload against section 2.3."""
    if payload.get("v") != PROTOCOL_VERSION:
        return False, "unsupported version"

    name = payload.get("name")
    if not isinstance(name, str) or not 1 <= len(name) <= 32:
        return False, "bad name"

    ips = payload.get("ips")
    if not isinstance(ips, list) or not 1 <= len(ips) <= 4:
        return False, "bad ips"
    if not all(is_valid_ipv4(ip) for ip in ips):
        return False, "bad ip"

    port = payload.get("port")
    if isinstance(port, bool) or not isinstance(port, int):
        return False, "bad port"
    if not 1024 <= port <= 65535:
        return False, "port out of range"

    if not is_valid_token(payload.get("token")):
        return False, "bad token"

    if not is_valid_fingerprint(payload.get("fp")):
        return False, "bad fingerprint"

    return True, ""
