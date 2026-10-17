"""The WebSocket server and the pairing handshake.

Section 3 of `docs/protocol.md`.

The handshake is the security-relevant part of the whole product, so it is
written as an explicit state machine rather than a series of `if`s scattered
through the message loop:

    connected -> hello -> auth_pending -> auth_ok -> connected(ready)

Nothing is accepted before `auth_ok`. An unauthenticated socket that starts
sending `key` events gets them dropped and counted, not obeyed - otherwise the
Allow/Deny prompt would be decorative.

TLS is mandatory. The certificate is self-signed and the phone pins its
fingerprint from the QR; this server never offers a plaintext option, because a
"just for testing" fallback would be the thing that shipped.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import ssl
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Awaitable, Callable

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from . import protocol as p
from .devices import DeviceStore
from .pairing import PairingToken
from .ratelimit import RateLimiter
from .session import DEFAULT_PORT, PairingManager

log = logging.getLogger("tapdesk.server")

#: Section 3.1: hello must be answered within five seconds or the phone hangs up.
HELLO_TIMEOUT_SECONDS = 5.0

#: Section 3.1: the user's decision is not timed out. A teacher may take a
#: while to notice the prompt, and being disconnected for being slow would be
#: maddening.
APPROVAL_TIMEOUT_SECONDS = 120.0

#: How long the stick stream may go without a value before the PC stops moving
#: the cursor, as a backstop if a phone dies mid-drag.
STICK_IDLE_TIMEOUT_SECONDS = 0.5


@dataclass
class ConnectionState:
    """Everything the server tracks for one socket."""

    peer: str
    device_name: str = ""
    device_id: str | None = None
    authenticated: bool = False
    frames_seen: int = 0
    frames_dropped: int = 0
    stick: tuple[float, float] = (0.0, 0.0)
    stick_updated: float = 0.0
    pending_move: tuple[int, int] = (0, 0)
    limiter: RateLimiter = field(
        default_factory=lambda: RateLimiter(p.RATE_LIMITS, p.OVERALL_RATE_LIMIT)
    )


class PairingServer:
    """The companion's server.

    `on_event` receives every validated input event and is where input
    simulation is plugged in. Keeping it a callback means this class has no
    dependency on pynput or on a window, so the whole handshake can be tested
    on a machine with no display.
    """

    def __init__(
        self,
        cert: ssl.SSLContext,
        devices: DeviceStore,
        pairing: PairingManager,
        on_event: Callable[[ConnectionState, dict[str, Any]], None] | None = None,
        on_approval_request: Callable[[str, str], Awaitable[bool]] | None = None,
        on_release: Callable[[], None] | None = None,
    ) -> None:
        self._ssl = cert
        self._devices = devices
        self._pairing = pairing
        self._on_event = on_event or (lambda state, message: None)
        self._on_approval = on_approval_request
        self._on_release = on_release
        self._states: dict[ServerConnection, ConnectionState] = {}
        self._server: Any = None

    # -- lifecycle --------------------------------------------------------

    async def start(self, port: int = DEFAULT_PORT, host: str = "0.0.0.0") -> None:
        self._server = await serve(
            self._handle,
            host,
            port,
            ssl=self._ssl,
            ping_interval=20,
            ping_timeout=20,
            max_size=p.MAX_FRAME_BYTES,
        )
        log.info("listening on %s:%s", host, port)

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            with contextlib.suppress(Exception):
                await self._server.wait_closed()

    @property
    def connected_count(self) -> int:
        return sum(
            1 for s in self._states.values() if s.authenticated
        )

    # -- the connection loop ----------------------------------------------

    async def _handle(self, connection: ServerConnection) -> None:
        state = ConnectionState(peer=str(connection.remote_address))
        self._states[connection] = state
        try:
            await self._handshake(connection, state)
            if state.authenticated:
                await self._serve_events(connection, state)
        except ConnectionClosed:
            pass
        except p.ProtocolError as exc:
            log.info("protocol error from %s: %s", state.peer, exc.code)
            await self._close(connection, exc.code)
        except Exception:  # pragma: no cover - defensive
            log.exception("unhandled error for %s", state.peer)
            await self._close(connection, "internal")
        finally:
            self._release_input(state)
            self._states.pop(connection, None)

    async def _handshake(
        self, connection: ServerConnection, state: ConnectionState
    ) -> None:
        try:
            raw = await asyncio.wait_for(
                connection.recv(), timeout=HELLO_TIMEOUT_SECONDS
            )
        except asyncio.TimeoutError:
            await self._close(connection, p.E_MALFORMED)
            return

        message = p.decode(raw)
        if message.get("t") != "hello":
            raise p.ProtocolError(p.E_MALFORMED, "expected hello first")

        if message.get("v") != p.PROTOCOL_VERSION:
            await self._send_error(connection, p.E_UNSUPPORTED_VERSION)
            await self._close(connection, p.CLOSE_UNSUPPORTED_VERSION)
            return

        state.device_name = str(message.get("device", "Unknown phone"))[:64]

        await self._send(
            connection,
            {"t": "hello_ok", "v": p.PROTOCOL_VERSION, "pc": {"name": self._pairing.name}},
        )

        auth = p.decode(await connection.recv())
        if auth.get("t") != "auth":
            raise p.ProtocolError(p.E_MALFORMED, "expected auth")

        token = auth.get("token")
        key = auth.get("key")

        if isinstance(key, str) and key:
            await self._authenticate_device(connection, state, key)
            return

        if isinstance(token, str) and token:
            await self._authenticate_token(connection, state, token)
            return

        raise p.ProtocolError(p.E_MALFORMED, "auth carried neither token nor key")

    async def _authenticate_token(
        self, connection: ServerConnection, state: ConnectionState, token: str
    ) -> None:
        """First-time pairing: check the token, then ask the human."""
        session = self._pairing.current()

        if not session.token.matches(token):
            await self._send_error(connection, p.E_BAD_TOKEN)
            await self._close(connection, p.CLOSE_AUTH_FAILED)
            return

        # Spend the token before asking. If the user denies, or the pairing
        # fails, the code on screen is dead and a new one is drawn.
        ok, code = session.token.valid()
        if not ok:
            await self._send_error(connection, code)
            await self._close(connection, p.CLOSE_AUTH_FAILED)
            return
        session.token.consume()

        await self._send(
            connection,
            {"t": "auth_pending", "device": state.device_name, "ip": state.peer},
        )

        allowed = await self._ask_user(state.device_name, state.peer)
        if not allowed:
            await self._send_error(connection, p.E_DENIED)
            await self._close(connection, p.CLOSE_AUTH_FAILED)
            return

        device, raw_key = self._devices.pair(
            name=state.device_name,
            fingerprint=self._pairing.fingerprint,
        )
        state.device_id = device.device_id
        state.authenticated = True

        await self._send(
            connection,
            {
                "t": "auth_ok",
                "deviceId": device.device_id,
                # Handed over exactly once; the PC keeps only the hash.
                "deviceKey": raw_key,
                "ttl": 0,
            },
        )
        await self._send_welcome()

    async def _authenticate_device(
        self, connection: ServerConnection, state: ConnectionState, key: str
    ) -> None:
        """Reconnecting phone: the key is the proof, and no prompt is shown."""
        device = self._devices.find_by_key(key)
        if device is None:
            # Could be revoked, or never paired. Either way the phone must
            # forget its key and scan again.
            await self._send_error(connection, p.E_REVOKED)
            await self._close(connection, p.CLOSE_REVOKED)
            return

        state.device_id = device.device_id
        state.device_name = device.name
        state.authenticated = True
        self._devices.touch(device.device_id)

        await self._send(
            connection, {"t": "auth_ok", "deviceId": device.device_id}
        )
        await self._send_welcome()

    async def _ask_user(self, device_name: str, peer: str) -> bool:
        if self._on_approval is None:
            # No UI attached: refuse rather than silently allow. Allowing by
            # default would make the prompt meaningless in exactly the
            # situation where it matters.
            log.warning("no approval handler; refusing %s from %s", device_name, peer)
            return False
        try:
            return await asyncio.wait_for(
                self._on_approval(device_name, peer),
                timeout=APPROVAL_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            log.info("approval timed out for %s", device_name)
            return False

    # -- events ------------------------------------------------------------

    async def _serve_events(
        self, connection: ServerConnection, state: ConnectionState
    ) -> None:
        async for raw in connection:
            state.frames_seen += 1
            try:
                message = p.decode(raw)
                await self._handle_event(state, message)
            except p.ProtocolError as exc:
                state.frames_dropped += 1
                # Malformed input is dropped, not fatal: one bad frame must not
                # kill a live session mid-lecture.
                if exc.code not in (p.E_RATE_LIMITED, p.E_UNSAFE, p.E_BAD_FIELD):
                    log.info("dropping frame: %s", exc.code)

    async def _handle_event(
        self, state: ConnectionState, message: dict[str, Any]
    ) -> None:
        kind = message["t"]

        if kind == "ping":
            state.limiter.allow("ping")
            await self._send_nowait(
                {"t": "pong", "ts": message["ts"], "st": int(time.time() * 1000)}
            )
            return

        p.validate(message)

        if not state.authenticated:
            raise p.ProtocolError(p.E_UNAUTHENTICATED, kind)

        if kind == "stick":
            # No rate limit here, and deliberately so: the newest value always
            # wins and older ones are discarded. That IS the coalescing the
            # protocol asks for - a frame limiter would drop the newest value
            # instead of the oldest and make the cursor stutter.
            state.stick = (float(message["x"]), float(message["y"]))
            state.stick_updated = time.monotonic()
            return

        if kind == "move":
            state.pending_move = (
                state.pending_move[0] + int(message["dx"]),
                state.pending_move[1] + int(message["dy"]),
            )
            return

        if kind == "text":
            if not state.limiter.allow_text(len(message["s"])):
                raise p.ProtocolError(p.E_RATE_LIMITED, "text")
            self._on_event(state, message)
            return

        if not state.limiter.allow(kind):
            raise p.ProtocolError(p.E_RATE_LIMITED, kind)

        self._on_event(state, message)

    def _release_input(self, state: ConnectionState) -> None:
        """Undo anything still held, so nothing stays down after a disconnect.

        Section 7.10. A phone that dies mid-drag would otherwise leave a mouse
        button or a key held down on the user's desktop until they noticed.

        Both halves are needed and neither is enough alone: clearing the
        per-connection stick stops the cursor gliding, and `on_release` tells
        the input layer to physically let go of what it pressed. The second
        half used to be missing, which left Ctrl and the mouse button latched
        down with nothing on screen to explain it.
        """
        if state.pending_move != (0, 0):
            state.pending_move = (0, 0)
        if state.stick != (0.0, 0.0):
            state.stick = (0.0, 0.0)
            state.stick_updated = time.monotonic()

        if self._on_release is not None:
            self._on_release()

    # -- helpers -----------------------------------------------------------

    async def _send(self, connection: ServerConnection, message: dict[str, Any]) -> None:
        await connection.send(p.encode(message))

    async def _send_error(
        self, connection: ServerConnection, code: str
    ) -> None:
        await self._send(connection, {"t": "auth_err", "code": code})

    async def _send_welcome(self) -> None:
        # Sent on every successful handshake so a reconnecting phone does not
        # have to remember the limits from last time.
        await self._send_nowait(
            {
                "t": "welcome",
                "maxText": p.MAX_TEXT_CHARS,
                "stickHz": 60,
                "serverTime": int(time.time() * 1000),
            }
        )

    async def _send_nowait(self, message: dict[str, Any]) -> None:
        """Send to every authenticated socket."""
        for connection, state in list(self._states.items()):
            if not state.authenticated:
                continue
            with contextlib.suppress(Exception):
                await connection.send(p.encode(message))

    async def _close(
        self, connection: ServerConnection, code_or_error: int | str, detail: str = ""
    ) -> None:
        """Close the socket with the right code.

        Accepts either a WebSocket close code or one of the protocol's error
        strings, because the call sites naturally have one or the other.

        The reason string must be a str. Passing the numeric code as the
        reason - which looked harmless - made websockets raise, so the close
        never happened and the phone saw "no close frame received or sent".
        """
        if isinstance(code_or_error, str):
            code = _CLOSE_FOR_ERROR.get(code_or_error, p.CLOSE_AUTH_FAILED)
            reason = detail or code_or_error
        else:
            code = code_or_error
            reason = detail

        with contextlib.suppress(Exception):
            await connection.close(code, reason)


#: Error code to close code, section 6.2.
_CLOSE_FOR_ERROR: dict[str, int] = {
    p.E_UNSUPPORTED_VERSION: p.CLOSE_UNSUPPORTED_VERSION,
    p.E_REVOKED: p.CLOSE_REVOKED,
    p.E_RATE_LIMITED: p.CLOSE_RATE_LIMITED,
    p.E_WRONG_FP: p.CLOSE_WRONG_FP,
    p.E_BAD_TOKEN: p.CLOSE_AUTH_FAILED,
    p.E_TOKEN_EXPIRED: p.CLOSE_AUTH_FAILED,
    p.E_TOKEN_USED: p.CLOSE_AUTH_FAILED,
    p.E_DENIED: p.CLOSE_AUTH_FAILED,
    p.E_AUTH_FAILED_KEY: p.CLOSE_AUTH_FAILED,
}


def load_ssl_context(config_dir: Path) -> tuple[ssl.SSLContext, Any]:
    """Build the TLS context from the stored certificate.

    The certificate is created on first run and reused forever after, so the
    fingerprint in the QR stays valid across restarts.
    """
    from . import tls

    certificate = tls.ensure(config_dir)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(
        certfile=str(config_dir / "companion.crt"),
        keyfile=str(config_dir / "companion.key"),
    )
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return context, certificate
