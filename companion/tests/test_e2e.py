"""End-to-end tests: a real client against a really-listening companion.

These are the tests that would have caught the two silent bugs in the backend
wiring - the event loop that was created but never run, and the sync approval
handler that the server awaits. Both produced a companion that looked correct
and refused to connect anyone.

Nothing here mocks the socket, the TLS layer or the handshake. That is the
point: a mock cannot tell you the port is bound.
"""

from __future__ import annotations

import asyncio
import ssl
from pathlib import Path

import pytest

from tapdesk import protocol as p
from tapdesk import session as session_mod
from tapdesk.app import Companion, _is_release


pytestmark = pytest.mark.timeout(30)


def free_port() -> int:
    """Ask the OS for a port nobody is using, then let go of it.

    Tests cannot share the fixed default port: they run concurrently in
    practice and would collide on a machine where one of them fails.
    """
    import socket

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def make_companion(tmp_path: Path, port: int | None = None, **kwargs) -> Companion:
    return Companion(
        config_dir=tmp_path,
        port=port if port is not None else free_port(),
        headless=True,
        **kwargs,
    )


def client_context(directory: Path) -> ssl.SSLContext:
    """A TLS context that trusts exactly this companion's certificate.

    The test's stand-in for the phone's fingerprint pinning. It does not turn
    verification off - it verifies against the one certificate the companion
    was configured with, so a server presenting anything else fails here.
    """
    context = ssl.create_default_context()
    context.load_verify_locations(cafile=str(directory / "companion.crt"))
    # Connected by IP, and the certificate is issued for the pairing token's
    # name rather than a hostname. The phone's real check is the SHA-256
    # fingerprint it was given in the QR code, which this stands in for.
    context.check_hostname = False
    return context


class TestBackendActuallyListens:
    def test_start_backend_binds_a_port(self, tmp_path: Path) -> None:
        companion = make_companion(tmp_path)
        try:
            # start_backend waits for the server to actually be listening.
            # Before this fix it created a loop, scheduled the server and
            # returned immediately without ever running it.
            companion.start_backend()
            assert companion._loop is not None
            assert companion._started.is_set()
        finally:
            companion.stop_backend()

    def test_the_socket_really_accepts_a_tcp_connection(
        self, tmp_path: Path
    ) -> None:
        import socket

        port = free_port()
        companion = make_companion(tmp_path, port=port)
        try:
            companion.start_backend()
            with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
                assert s is not None
        finally:
            companion.stop_backend()

    def test_stop_backend_is_idempotent(self, tmp_path: Path) -> None:
        # Quit is reachable from the tray, the window and a signal handler, so
        # shutdown can legitimately be reached more than once.
        companion = make_companion(tmp_path)
        companion.start_backend()
        companion.stop_backend()
        companion.stop_backend()

    def test_stop_backend_releases_held_input(self, tmp_path: Path) -> None:
        # Closing the companion must not leave a modifier down on the desktop.
        companion = make_companion(tmp_path)
        companion.start_backend()
        companion._simulator.handle({"t": "key", "k": "ctrl", "a": "press"})
        companion.stop_backend()
        assert companion._simulator.held.keys == set()

    def test_starting_twice_does_not_start_two_servers(
        self, tmp_path: Path
    ) -> None:
        companion = make_companion(tmp_path)
        try:
            companion.start_backend()
            companion.start_backend()
            assert companion._thread is not None
        finally:
            companion.stop_backend()


class TestApproval:
    async def test_approval_is_awaitable_and_can_allow(self, tmp_path: Path) -> None:
        # The server awaits this. A plain function returning bool raised
        # TypeError here, which is the worst possible time: the user is being
        # asked whether to trust a phone.
        allowed: list[str] = []

        def approve(name: str, peer: str) -> bool:
            allowed.append(name)
            return True

        companion = make_companion(tmp_path, approve=approve)
        try:
            assert await companion._ask_approval("Pixel 7", "1.2.3.4") is True
            assert allowed == ["Pixel 7"]
        finally:
            companion.stop_backend()

    async def test_approval_can_deny(self, tmp_path: Path) -> None:
        companion = make_companion(tmp_path, approve=lambda n, p: False)
        try:
            assert await companion._ask_approval("Pixel 7", "1.2.3.4") is False
        finally:
            companion.stop_backend()

    async def test_with_nobody_to_ask_it_refuses(self, tmp_path: Path) -> None:
        # No window and no override means no way to ask. Refusing is the only
        # safe answer.
        companion = Companion(
            config_dir=tmp_path, port=free_port(), headless=True
        )
        try:
            assert await companion._ask_approval("Pixel 7", "1.2.3.4") is False
        finally:
            companion.stop_backend()


class TestHotkeyIsNotLoadBearing:
    """A missing emergency stop must never cost the user the app.

    This pynput version has no HotKey.from_keyboard_string, and an unguarded
    call to it took the whole companion down on launch. The invariant is that
    registering the hotkey can fail any which way and the companion carries on
    serving.
    """

    def test_a_broken_hotkey_does_not_stop_the_companion(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        pynput = pytest.importorskip("pynput.keyboard")

        def explode(*args: object, **kwargs: object) -> None:
            raise AttributeError("from_keyboard_string was removed")

        monkeypatch.setattr(
            pynput.HotKey, "from_keyboard_string", explode, raising=False
        )

        companion = make_companion(tmp_path)
        try:
            companion.start_backend()
            companion._install_hotkey()
            # Still listening, which is the part that matters.
            assert companion._started.is_set()
        finally:
            companion.stop_backend()


class TestSafeMode:
    def test_release_events_are_recognised(self) -> None:
        assert _is_release({"t": "key", "k": "ctrl", "a": "release"}) is True
        assert _is_release({"t": "click", "b": "left", "a": "up"}) is True
        assert _is_release({"t": "ping"}) is True

    def test_pressing_events_are_not(self) -> None:
        assert _is_release({"t": "key", "k": "ctrl", "a": "press"}) is False
        assert _is_release({"t": "click", "b": "left", "a": "down"}) is False
        assert _is_release({"t": "slide", "a": "next"}) is False
        assert _is_release({"t": "text", "s": "hello"}) is False

    def test_safe_mode_blocks_input_but_still_allows_release(
        self, tmp_path: Path
    ) -> None:
        # The asymmetry is the whole design: you must be able to stop a
        # runaway input, and you must not be able to leave a key stuck down.
        performed: list[tuple] = []
        companion = make_companion(tmp_path)
        companion._simulator._execute = performed.append

        try:
            companion._on_event(None, {"t": "text", "s": "rm -rf"})
            companion._on_event(None, {"t": "slide", "a": "next"})
            companion._on_event(None, {"t": "click", "b": "left", "a": "down"})
            # Safe mode is off, so all of this must reach the desktop. If it
            # did not, "safe mode blocks input" below would pass for the wrong
            # reason - a permanently dead input path also blocks input.
            assert ("text", "rm -rf") in performed
            assert ("key", "pgdn", "down") in performed
            assert ("button", "left", "down") in performed

            performed.clear()
            companion.set_safe_mode(True)
            # Enabling Safe Mode lets go of what was held, which is a
            # deliberate action and not a leak, so the baseline is reset here.
            performed.clear()

            companion._on_event(None, {"t": "text", "s": "rm -rf"})
            companion._on_event(None, {"t": "slide", "a": "next"})
            companion._on_event(None, {"t": "click", "b": "left", "a": "down"})
            assert performed == [], "safe mode leaked input through"

            companion._on_event(None, {"t": "key", "k": "ctrl", "a": "release"})
            assert performed == [("key", "ctrl", "up")], (
                "safe mode must still let a held key go"
            )
        finally:
            companion.stop_backend()

    def test_turning_safe_mode_on_lets_go_of_everything_held(
        self, tmp_path: Path
    ) -> None:
        companion = make_companion(tmp_path)
        try:
            companion._simulator.handle({"t": "key", "k": "ctrl", "a": "press"})
            assert companion._simulator.held.keys

            companion.set_safe_mode(True)
            assert companion._simulator.held.keys == set()
        finally:
            companion.stop_backend()




async def _handshake(
    companion: Companion,
    port: int,
    device: str = "Pixel 7",
    key: str | None = None,
):
    """Connect, hello, and authenticate. Returns (ws, final handshake reply).

    Authenticates with a saved device key when one is supplied, and with the
    pairing token otherwise - which is the whole point of the distinction. The
    token is spent on first pairing, so a reconnect that still sends it can
    only ever be a first-time device.

    Reads through `auth_pending` rather than assuming one reply: the server
    tells the phone it is asking the human, and only then answers. Treating the
    first reply as the result is what makes these tests fail against correct
    code.
    """
    from websockets.asyncio.client import connect

    url = f"wss://127.0.0.1:{port}/"
    ws = await connect(url, ssl=client_context(companion.config_dir))

    await ws.send(
        p.encode({"t": "hello", "v": 1, "device": device, "platform": "android"})
    )
    hello_ok = p.decode(await asyncio.wait_for(ws.recv(), 5))
    assert hello_ok["t"] == "hello_ok", hello_ok

    if key is not None:
        await ws.send(p.encode({"t": "auth", "key": key}))
    else:
        await ws.send(
            p.encode(
                {"t": "auth", "token": companion._pairing.session.token.value}
            )
        )

    reply = p.decode(await asyncio.wait_for(ws.recv(), 5))
    if reply["t"] == "auth_pending":
        reply = p.decode(await asyncio.wait_for(ws.recv(), 5))
    return ws, reply


class TestFullHandshake:
    async def test_a_paired_phone_can_pair_and_send_input(
        self, tmp_path: Path
    ) -> None:
        """The whole product, over a real socket.

        A real WebSocket client connects to a really-bound port, is approved,
        gets paired, and its events reach the simulator. If this passes, the
        companion does what the QR code promises.
        """
        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: True
        )

        performed: list[tuple] = []
        companion._simulator._execute = performed.append

        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port)

            assert reply["t"] == "auth_ok", reply
            # The device is remembered across restarts.
            assert len(companion._devices) == 1
            assert companion._server.connected_count == 1

            await ws.send(p.encode({"t": "text", "s": "hello"}))
            await asyncio.sleep(0.4)
            assert ("text", "hello") in performed, performed

            await ws.close()
            await asyncio.sleep(0.4)
            assert companion._server.connected_count == 0

        finally:
            companion.stop_backend()

    async def test_a_denied_phone_cannot_send_anything(
        self, tmp_path: Path
    ) -> None:
        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: False
        )
        performed: list[tuple] = []
        companion._simulator._execute = performed.append

        ws = None
        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port, device="Attacker")

            # Denied means denied, and nothing it sends afterwards is applied.
            assert reply["t"] == "auth_err", reply
            assert reply["code"] == "E_DENIED", reply

            # The companion closes the socket after a denial, so the phone
            # finds out by the connection dropping. Either way, nothing this
            # phone sends may be performed - a client that ignores the close
            # and keeps talking must get nowhere.
            try:
                await ws.send(p.encode({"t": "text", "s": "rm -rf"}))
                await asyncio.sleep(0.4)
            except Exception:
                pass  # the socket was closed under us, which is the point

            assert performed == []
            assert len(companion._devices) == 0

        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_the_second_phone_is_asked_separately(
        self, tmp_path: Path
    ) -> None:
        # Pairing one phone must not silently trust the next one. If the
        # prompt were skipped, anyone who could reach the port could take
        # control of the machine.
        port = free_port()
        seen: list[str] = []
        companion = make_companion(
            tmp_path,
            port=port,
            approve=lambda name, peer: seen.append(name) or True,
        )

        try:
            companion.start_backend()
            first, _ = await _handshake(companion, port, device="Pixel 7")

            # The pairing token is single-use - a scanned QR code works once,
            # so a second phone needs the refreshed code the window now shows.
            # Reusing a spent token would let a photograph of an old QR code
            # grant access.
            companion._pairing.refresh()
            second, reply = await _handshake(companion, port, device="Tabby")

            assert reply["t"] == "auth_ok", reply
            assert seen == ["Pixel 7", "Tabby"]
            assert len(companion._devices) == 2

            await first.close()
            await second.close()
        finally:
            companion.stop_backend()

    async def test_a_paired_phone_may_reconnect_without_being_asked(
        self, tmp_path: Path
    ) -> None:
        # Once trusted, a device reconnecting should not re-prompt the user.
        # Re-asking every reconnect trains people to click Yes without
        # reading, which defeats the prompt entirely.
        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: True
        )

        try:
            companion.start_backend()
            first, reply = await _handshake(companion, port)
            assert reply["t"] == "auth_ok"

            # The key is handed over exactly once, in auth_ok. This is what the
            # phone keeps and sends from now on.
            saved_key = reply["deviceKey"]
            await first.close()
            await asyncio.sleep(0.3)

            # A reconnect with the saved key must not re-prompt the user.
            second, again = await _handshake(companion, port, key=saved_key)
            assert again["t"] == "auth_ok", again
            assert again["deviceId"] == reply["deviceId"]
            await second.close()

            # And the companion still trusts it.
            assert len(companion._devices) == 1
        finally:
            companion.stop_backend()

    async def test_the_stick_actually_reaches_the_input_layer(
        self, tmp_path: Path
    ) -> None:
        """The cursor must move, not merely the frame be accepted.

        This is the one test that would have caught the analog stick being
        dead. The server used to store stick values on the connection state and
        return without forwarding them, so every other event type worked, the
        phone was convinced it was sending, the frames passed validation -
        and the cursor never moved.

        Asserting "the companion did not complain" was not enough. A frame can
        be perfectly valid, correctly framed and correctly authenticated and
        still never be acted on.
        """
        port = free_port()
        companion = make_companion(
            tmp_path,
            port=port,
            approve=lambda name, peer: True,
        )

        performed: list[tuple] = []
        companion._simulator._execute = performed.append

        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port)
            assert reply["t"] == "auth_ok", reply

            await ws.send(p.encode({"t": "stick", "x": 1.0, "y": 0.0}))
            # The stick is sampled on a 60 Hz timer, not per frame, so give the
            # backend loop a few ticks to turn the value into a mouse movement.
            await asyncio.sleep(0.4)

            moves = [a for a in performed if a[0] == "move"]
            assert moves, (
                "the stick was accepted but never moved the cursor; "
                f"actions were {performed}"
            )
            assert moves[0][1] > 0, "dragging right must move the cursor right"

            await ws.close()
        finally:
            companion.stop_backend()

    async def test_moving_up_moves_the_cursor_up(self, tmp_path: Path) -> None:
        # +y is up on the wire and screen coordinates count downward. Missing
        # that negation sends the cursor the wrong way, which feels like a
        # broken stick rather than an inverted one.
        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: True
        )

        performed: list[tuple] = []
        companion._simulator._execute = performed.append

        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port)
            assert reply["t"] == "auth_ok", reply

            await ws.send(p.encode({"t": "stick", "x": 0.0, "y": 1.0}))
            await asyncio.sleep(0.4)

            moves = [a for a in performed if a[0] == "move"]
            assert moves
            assert moves[0][2] < 0, "up on the wire must be up on the screen"

            await ws.close()
        finally:
            companion.stop_backend()

    async def test_releasing_the_stick_stops_the_cursor(self, tmp_path: Path) -> None:
        """A stick left deflected must not slide the cursor forever.

        The phone sends a zero on release; without it, or without the stick
        going stale, a phone set down mid-drag would keep driving the pointer
        across the presenter's desktop with nobody touching it.
        """
        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: True
        )

        performed: list[tuple] = []
        companion._simulator._execute = performed.append

        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port)
            assert reply["t"] == "auth_ok", reply

            await ws.send(p.encode({"t": "stick", "x": 1.0, "y": 0.0}))
            await asyncio.sleep(0.3)

            await ws.send(p.encode({"t": "stick", "x": 0.0, "y": 0.0}))
            # Let the release actually be processed before starting to watch.
            # The tick loop samples whatever value it last received, so a tick
            # fired in the instant between "release sent" and "release applied"
            # would otherwise be counted as the cursor still moving.
            await asyncio.sleep(0.2)
            performed.clear()

            await asyncio.sleep(0.3)

            moves = [a for a in performed if a[0] == "move"]
            assert not moves, f"the cursor kept moving after release: {moves}"

            await ws.close()
        finally:
            companion.stop_backend()

    async def test_disconnect_releases_held_input(self, tmp_path: Path) -> None:
        # Section 7.10: a phone that vanishes mid-drag must not leave the
        # desktop with the mouse button down.
        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: True
        )

        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)

            await ws.send(p.encode({"t": "click", "b": "left", "a": "down"}))
            await ws.send(p.encode({"t": "key", "k": "ctrl", "a": "press"}))
            await asyncio.sleep(0.4)
            assert companion._simulator.held.buttons == {"left"}
            assert companion._simulator.held.keys == {"ctrl"}

            # The phone goes away without disconnecting cleanly.
            ws.transport.abort()
            await asyncio.sleep(0.6)

            assert companion._simulator.held.buttons == set()
            assert companion._simulator.held.keys == set()
        finally:
            companion.stop_backend()

    async def test_hello_reports_the_pc_identity(self, tmp_path: Path) -> None:
        # The phone shows this to the user, so it has to be right.
        from websockets.asyncio.client import connect

        port = free_port()
        companion = make_companion(
            tmp_path, port=port, approve=lambda name, peer: True
        )
        ws = None
        try:
            companion.start_backend()
            ws = await connect(
                f"wss://127.0.0.1:{port}/",
                ssl=client_context(companion.config_dir),
            )
            await ws.send(
                p.encode(
                    {
                        "t": "hello",
                        "v": 1,
                        "device": "Pixel 7",
                        "platform": "android",
                    }
                )
            )
            hello_ok = p.decode(await asyncio.wait_for(ws.recv(), 5))

            assert hello_ok["t"] == "hello_ok"
            # The protocol (docs/protocol.md line 253) puts the fingerprint
            # in the QR deep link, not in hello_ok - the phone already pinned
            # the certificate from the code it scanned.
            assert hello_ok["pc"]["name"] == companion._pairing.name
            assert "fp" not in hello_ok
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

async def _greeting(ws) -> dict[str, Any]:
    """Drain auth_ok, welcome and settings, returning the settings push.

    The companion tells the phone what it is doing the moment it connects. A
    test that reads a fixed number of messages instead is really asserting
    "nothing else was added", which is how adding the settings push - the
    right thing - showed up as a ping test failing.
    """
    seen: dict[str, Any] = {}
    while "settings" not in seen:
        message = p.decode(await asyncio.wait_for(ws.recv(), 5))
        seen[message["t"]] = message
    return seen["settings"]


class TestSettingsReachTheComputer:
    """A slider on the phone has to move the pointer on the PC.

    The settings are applied in the companion's input layer, not on the phone,
    so the only way to know a change took effect is to watch the real thing it
    changes. Asserting that the phone sent a `set` would prove the phone
    worked, not that the setting did.
    """

    async def test_the_phone_is_told_the_settings_the_second_it_connects(
        self, tmp_path: Path
    ) -> None:
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port)
            assert reply["t"] == "auth_ok", reply

            settings = await _greeting(ws)
            assert settings["cursorSpeed"] == 1.0
            assert settings["accel"] == 1.6
            assert settings["safeMode"] is False
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_cursor_speed_reaches_the_input_layer(self, tmp_path: Path) -> None:
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "cursorSpeed": 2.5}))
            settings = await _greeting(ws)

            # Echoed back, so the phone can show the truth rather than its
            # own optimism.
            assert settings["cursorSpeed"] == 2.5
            assert companion._simulator.cursor_speed == 2.5
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_a_slower_pointer_is_actually_reachable(
        self, tmp_path: Path
    ) -> None:
        """Below 1.0 is the case that matters and the easiest one to lose.

        Someone driving a projector from the back of a room needs the pointer
        to crawl. If the range were 1.0-4.0 the slider would look right and
        the bottom half of its travel would do nothing at all.
        """
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "cursorSpeed": 0.25}))
            settings = await _greeting(ws)

            assert settings["cursorSpeed"] == 0.25
            assert companion._simulator.cursor_speed == 0.25
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_the_acceleration_curve_reaches_the_input_layer(
        self, tmp_path: Path
    ) -> None:
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "accel": 2.4}))
            settings = await _greeting(ws)

            assert settings["accel"] == 2.4
            assert companion._simulator.curve == 2.4
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_changing_one_setting_leaves_the_others_alone(
        self, tmp_path: Path
    ) -> None:
        """`set` is a partial update, and it has to behave like one.

        A phone that always sent all three fields would reset a Safe Mode
        change made on the computer every time it connected - two people
        editing one setting, last write wins, nobody told.
        """
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "cursorSpeed": 3.0}))
            await _greeting(ws)
            await ws.send(p.encode({"t": "set", "accel": 2.0}))
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "safeMode": True}))
            settings = await _greeting(ws)

            assert settings["safeMode"] is True
            assert settings["cursorSpeed"] == 3.0
            assert settings["accel"] == 2.0
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_an_impossible_speed_is_refused_and_the_old_one_survives(
        self, tmp_path: Path
    ) -> None:
        """A refused change must snap the phone back, not leave it lying.

        If the frame were merely dropped the slider would sit at 99 while the
        pointer behaved exactly as before, and the user would have no way to
        tell that from a setting that worked.
        """
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "cursorSpeed": 99.0}))
            settings = await _greeting(ws)

            assert settings["cursorSpeed"] == 1.0, settings
            assert companion._simulator.cursor_speed == 1.0
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_turning_on_safe_mode_over_the_wire_lets_go_of_a_held_key(
        self, tmp_path: Path
    ) -> None:
        """Freezing input while Ctrl is still down is the thing to avoid.

        Safe Mode's purpose is to stop a runaway; leaving the desktop with a
        modifier held would make turning it on part of the runaway.
        """
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        performed: list[tuple] = []
        try:
            companion._simulator._execute = performed.append
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "key", "k": "ctrl", "a": "press"}))
            await asyncio.sleep(0.4)
            assert companion._simulator.held.keys, "Ctrl should be down first"

            await ws.send(p.encode({"t": "set", "safeMode": True}))
            await _greeting(ws)

            assert companion._simulator.held.keys == set()
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_safe_mode_still_blocks_input_after_a_phone_sets_it(
        self, tmp_path: Path
    ) -> None:
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        performed: list[tuple] = []
        try:
            companion._simulator._execute = performed.append
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "set", "safeMode": True}))
            await _greeting(ws)

            await ws.send(p.encode({"t": "text", "s": "rm -rf"}))
            await asyncio.sleep(0.4)
            assert ("text", "rm -rf") not in performed, performed
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()


class TestUnpairingFromThePhone:
    """A phone should be able to cut its own access without walking over."""

    async def test_a_phone_can_ask_to_be_unpaired_and_then_cannot_reconnect(
        self, tmp_path: Path
    ) -> None:
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, reply = await _handshake(companion, port)
            assert reply["t"] == "auth_ok", reply
            await _greeting(ws)
            key = reply["deviceKey"]
            assert len(companion._devices) == 1

            await ws.send(p.encode({"t": "forget"}))
            answer = p.decode(await asyncio.wait_for(ws.recv(), 5))
            assert answer["t"] == "revoked", answer

            await ws.close()
            await asyncio.sleep(0.3)

            # The key is destroyed, not just politely ignored. Reconnecting
            # with the key the phone still has must fail the way a revoked
            # device always has.
            ws2, again = await _handshake(companion, port, key=key)
            try:
                assert again["t"] == "auth_err", again
                assert again["code"] == "E_REVOKED", again
            finally:
                await ws2.close()
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()

    async def test_unpairing_lets_go_of_everything_the_phone_was_holding(
        self, tmp_path: Path
    ) -> None:
        """Access gone means input gone, not input frozen mid-gesture."""
        port = free_port()
        companion = make_companion(tmp_path, port=port, approve=lambda n, p: True)
        ws = None
        try:
            companion.start_backend()
            ws, _ = await _handshake(companion, port)
            await _greeting(ws)

            await ws.send(p.encode({"t": "key", "k": "ctrl", "a": "press"}))
            await asyncio.sleep(0.4)
            assert companion._simulator.held.keys

            await ws.send(p.encode({"t": "forget"}))
            await asyncio.wait_for(ws.recv(), 5)
            await asyncio.sleep(0.3)

            assert companion._simulator.held.keys == set()
        finally:
            if ws is not None:
                await ws.close()
            companion.stop_backend()
