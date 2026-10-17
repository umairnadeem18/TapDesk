"""The pairing session: token, QR payload and its lifecycle.

Section 2.2: the token lives 120 seconds and the QR is refreshed when it
expires, when it is consumed, or when this machine's address changes. All three
matter - a QR left on screen for ten minutes is a QR that has already expired,
and a user who scans it gets a failure they cannot explain.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Callable

from . import pairing, tls

DEFAULT_PORT = 8765


@dataclass
class Session:
    """The current pairing offer and everything needed to render it."""

    port: int = DEFAULT_PORT
    name: str = ""
    ips: tuple[str, ...] = ()
    fingerprint: str = ""
    token: pairing.PairingToken = field(default_factory=pairing.PairingToken)
    created_at: float = field(default_factory=time.time)

    def payload(self) -> pairing.QRPayload:
        return pairing.QRPayload(
            name=self.name,
            ips=self.ips,
            port=self.port,
            token=self.token.value,
            fingerprint=self.fingerprint,
        )

    def deep_link(self) -> str:
        return self.payload().to_deep_link()

    @property
    def seconds_remaining(self) -> int:
        return self.token.remaining_seconds

    def expired(self) -> bool:
        return self.token.expired


class PairingManager:
    """Owns the session and decides when to mint a new one.

    Refresh is pull-based rather than timer-based: the window asks
    `current()` and gets a fresh token if the old one has expired. That avoids a
    background thread that would have to be shut down cleanly on exit.
    """

    def __init__(
        self,
        port: int = DEFAULT_PORT,
        fingerprint: str = "",
        name: str | None = None,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._port = port
        self._fingerprint = fingerprint
        self._name = name if name is not None else tls.hostname()
        self._clock = clock
        self._last_ips: tuple[str, ...] = ()
        self._session = self._mint()

    def _mint(self) -> Session:
        ips = tuple(tls.local_ips())
        self._last_ips = ips
        return Session(
            port=self._port,
            name=self._name,
            ips=ips,
            fingerprint=self._fingerprint,
        )

    @property
    def name(self) -> str:
        """The PC name shown in the window and sent in `hello_ok`."""
        return self._name

    @property
    def fingerprint(self) -> str:
        """The pinned certificate fingerprint, copied into every QR payload."""
        return self._fingerprint

    @property
    def port(self) -> int:
        return self._port

    @property
    def session(self) -> Session:
        return self._session

    def current(self) -> Session:
        """The session to display, refreshed if it has gone stale.

        Three things force a refresh: the token expiring, the token having been
        spent, and this machine's IP changing - which happens constantly on
        Wi-Fi and would leave the phone trying an address that no longer
        exists.
        """
        if self._session.expired() or self._session.token.consumed:
            self._session = self._mint()
            return self._session

        now_ips = tuple(tls.local_ips())
        if now_ips != self._last_ips:
            self._session = self._mint()
            return self._session

        return self._session

    def consume(self, token: pairing.PairingToken) -> bool:
        """Spend a token if it is the current one and still valid.

        Single-use: a token is spent whether the pairing that used it
        succeeded or failed, so a wrong PIN cannot be retried against the same
        code.
        """
        current = self._session
        if current.token is not token:
            return False
        ok, _ = token.valid()
        token.consume()
        return ok

    def refresh(self) -> Session:
        """Force a new session, e.g. after a pairing attempt."""
        self._session = self._mint()
        return self._session
