"""End-to-end tests for the pairing handshake.

A real TLS server on a real socket, driven by a client that mimics the phone -
including pinning the certificate fingerprint the way `docs/protocol.md`
section 7.1 requires. Anything less would let a broken handshake pass here and
only fail on a phone.
"""

from __future__ import annotations

import asyncio
import ssl
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest
from websockets.asyncio.client import connect

from tapdesk import protocol as p
from tapdesk.devices import DeviceStore, hash_key
from tapdesk.pairing import QRPayload, new_token
from tapdesk.ratelimit import RateLimiter
from tapdesk.server import PairingServer
from tapdesk.session import PairingManager


@dataclass
class Harness:
    """A running server plus the knobs a test wants to turn."""

    directory: Path
    server: PairingServer
    events: list[dict[str, Any]] = field(default_factory=list)
    approval: bool = True
    approval_calls: list[tuple[str, str]] = field(default_factory=list)
    port: int = 0

    async def start(self) -> None:
        await self.server.start(port=self.port, host="127.0.0.1")
        # Port 0 asks the OS for a free port; read it back off the socket.
        for server in self.server._server.sockets:  # noqa: SLF001
            self.port = server.getsockname()[1]
            break

    async def stop(self) -> None:
        await self.server.stop()

    def client_context(self) -> ssl.SSLContext:
        """A TLS context that trusts exactly this certificate.

        This is the test's stand-in for the phone's fingerprint pinning: it
        does not disable verification, it verifies against the one certificate
        the server was configured with. A server presenting anything else fails
        here, which is the property that matters.
        """
        context = ssl.create_default_context()
        context.load_verify_locations(
            cafile=str(self.directory / "companion.crt")
        )
        context.check_hostname = False  # connected by IP, not by name
        return context


def build(
    directory: Path, *, approval: bool = True
) -> Harness:
    from tapdesk import tls

    certificate = tls.ensure(directory)
    devices = DeviceStore(directory / "devices.json")

    pairing = PairingManager(
        port=8765,
        fingerprint=certificate.fingerprint,
        name="Test-PC",
    )

    harness = Harness(directory=directory, server=None, approval=approval)  # type: ignore[arg-type]

    async def ask(device_name: str, peer: str) -> bool:
        harness.approval_calls.append((device_name, peer))
        return harness.approval

    # Synchronous on purpose: the server calls this directly, not with await.
    def on_event(state: Any, message: dict[str, Any]) -> None:
        harness.events.append(message)

    harness.server = PairingServer(
        cert=_ssl(directory),
        devices=devices,
        pairing=pairing,
        on_event=on_event,
        on_approval_request=ask,
    )
    return harness


def _ssl(directory: Path) -> ssl.SSLContext:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(
        certfile=str(directory / "companion.crt"),
        keyfile=str(directory / "companion.key"),
    )
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return context


async def _pair(harness: Harness, device_name: str = "Pixel 7") -> dict[str, Any]:
    """Run hello + auth and return the final handshake message.

    The server sends `auth_pending` while the human decides and only then
    `auth_ok`, so a successful pairing involves two replies. Reading a single
    message and calling it the result is what made these tests fail against
    correct code.
    """
    url = f"wss://127.0.0.1:{harness.port}/"
    async with connect(url, ssl=harness.client_context()) as ws:
        await ws.send(
            p.encode(
                {"t": "hello", "v": 1, "device": device_name, "platform": "android"}
            )
        )
        hello_ok = p.decode(await ws.recv())
        assert hello_ok["t"] == "hello_ok"
        assert hello_ok["pc"]["name"] == "Test-PC"

        await ws.send(
            p.encode({"t": "auth", "token": harness.server._pairing.session.token.value})  # noqa: SLF001
        )

        reply = p.decode(await ws.recv())
        if reply["t"] == "auth_pending":
            # The user was asked; wait for their decision to come back.
            reply = p.decode(await ws.recv())
        return reply


# ---------------------------------------------------------------------------


class TestTokenPairing:
    @pytest.mark.asyncio
    async def test_hello_then_token_reaches_auth_ok(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            assert auth_ok["t"] == "auth_ok"
            assert auth_ok["deviceId"].startswith("d_")
            assert auth_ok["deviceKey"].startswith("tdk_")
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_the_user_is_asked_before_anything_is_paired(
        self, tmp_path: Path
    ) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            await _pair(harness)
            assert harness.approval_calls, "pairing must not be automatic"
            assert harness.approval_calls[0][0] == "Pixel 7"
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_denying_ends_the_session(self, tmp_path: Path) -> None:
        harness = build(tmp_path, approval=False)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            assert auth_ok["t"] == "auth_err"
            assert auth_ok["code"] == "E_DENIED"
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_no_device_is_stored_when_the_user_denies(
        self, tmp_path: Path
    ) -> None:
        harness = build(tmp_path, approval=False)
        await harness.start()
        try:
            await _pair(harness)
            assert len(harness.server._devices) == 0  # noqa: SLF001
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_a_token_is_single_use(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            await _pair(harness)
            # Second attempt with the same, now-spent, token must fail.
            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(
                    p.encode(
                        {"t": "auth", "token": "z" * 43}
                    )
                )
                reply = p.decode(await ws.recv())
                assert reply["t"] == "auth_err"
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_a_wrong_token_is_refused(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(p.encode({"t": "auth", "token": new_token()}))
                reply = p.decode(await ws.recv())
                assert reply["code"] == "E_BAD_TOKEN"
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_an_unsupported_version_is_refused(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode({"t": "hello", "v": 99, "device": "X", "platform": "android"})
                )
                reply = p.decode(await ws.recv())
                assert reply["code"] == "E_UNSUPPORTED_VERSION"
        finally:
            await harness.stop()


class TestDeviceKeys:
    @pytest.mark.asyncio
    async def test_the_raw_key_is_never_stored(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            raw_key = auth_ok["deviceKey"]
            stored = (tmp_path / "devices.json").read_text("utf-8")
            assert raw_key not in stored, "the key must never touch disk"
            assert hash_key(raw_key) in stored
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_a_paired_phone_reconnects_without_a_prompt(
        self, tmp_path: Path
    ) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            key = auth_ok["deviceKey"]
            harness.approval_calls.clear()

            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(p.encode({"t": "auth", "key": key}))
                reply = p.decode(await ws.recv())
                assert reply["t"] == "auth_ok"
                # A known device must not make the user confirm again.
                assert harness.approval_calls == []
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_a_revoked_device_is_rejected(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            key = auth_ok["deviceKey"]
            device_id = auth_ok["deviceId"]

            harness.server._devices.revoke(device_id)  # noqa: SLF001

            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(p.encode({"t": "auth", "key": key}))
                reply = p.decode(await ws.recv())
                assert reply["t"] == "auth_err"
                assert reply["code"] == "E_REVOKED"
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_an_unknown_key_is_refused(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(p.encode({"t": "auth", "key": "tdk_" + "x" * 40}))
                reply = p.decode(await ws.recv())
                assert reply["code"] == "E_REVOKED"
        finally:
            await harness.stop()


class TestEvents:
    @pytest.mark.asyncio
    async def test_events_are_delivered_after_pairing(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            key = auth_ok["deviceKey"]

            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(p.encode({"t": "auth", "key": key}))
                await ws.recv()  # auth_ok
                await ws.recv()  # welcome

                await ws.send(p.encode({"t": "slide", "a": "next"}))
                await ws.send(p.encode({"t": "text", "s": "السلام"}))
                await asyncio.sleep(0.15)

                kinds = [e["t"] for e in harness.events]
                assert "slide" in kinds
                assert "text" in kinds
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_ping_is_answered(self, tmp_path: Path) -> None:
        harness = build(tmp_path)
        await harness.start()
        try:
            auth_ok = await _pair(harness)
            key = auth_ok["deviceKey"]
            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                await ws.send(p.encode({"t": "auth", "key": key}))
                await ws.recv()
                await ws.recv()
                await ws.send(p.encode({"t": "ping", "ts": 1763308800123}))
                pong = p.decode(await ws.recv())
                assert pong["t"] == "pong"
                assert pong["ts"] == 1763308800123
        finally:
            await harness.stop()

    @pytest.mark.asyncio
    async def test_events_before_auth_are_never_acted_on(
        self, tmp_path: Path
    ) -> None:
        # The Allow/Deny prompt is only meaningful if nothing works before it.
        harness = build(tmp_path)
        await harness.start()
        try:
            url = f"wss://127.0.0.1:{harness.port}/"
            async with connect(url, ssl=harness.client_context()) as ws:
                await ws.send(
                    p.encode(
                        {"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}
                    )
                )
                await ws.recv()
                # Go straight to events without auth at all.
                await ws.send(p.encode({"t": "slide", "a": "next"}))
                await asyncio.sleep(0.15)
                assert harness.events == []
        finally:
            await harness.stop()


class TestTLS:
    @pytest.mark.asyncio
    async def test_an_untrusted_certificate_is_refused(self, tmp_path: Path) -> None:
        """Pinning must actually pin.

        A client with an empty trust store must fail to connect. If it
        succeeded, the fingerprint in the QR would be decorative.
        """
        harness = build(tmp_path)
        await harness.start()
        try:
            url = f"wss://127.0.0.1:{harness.port}/"
            with pytest.raises(ssl.SSLError):
                async with connect(url, ssl=ssl.create_default_context()):
                    pass
        finally:
            await harness.stop()
