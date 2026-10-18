"""The companion application.

Wires the server, the input simulator, the window and the tray together. This
is the piece you actually run.

Threading is the thing worth understanding here, because getting it wrong is
silent.

The server is asyncio. The window is Qt. Qt is not thread-safe and *must* be
driven from the thread that created it, so the server cannot simply run on the
same loop as the GUI. So the server runs on its own event loop in a background
thread, and every call that touches a widget is bounced back to the GUI thread
through a queued signal.

Two bugs this structure exists to prevent, both of which were written and then
fixed:

* The GUI mode created an event loop, scheduled the server on it, and never
  ran it. Nothing ever listened on the port. A QR code was on screen the whole
  time, so it looked completely plausible.
* The approval handler was a plain function, but the server awaits it. Awaiting
  a bool raises TypeError - at the exact moment the user is being asked whether
  to let a phone control their computer.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
import threading
import traceback
from pathlib import Path
from typing import Any, Callable

from . import protocol as p
from . import tls
from .devices import DeviceStore
from .input import InputSimulator
from .server import PairingServer, load_ssl_context
from .session import DEFAULT_PORT, PairingManager

log = logging.getLogger("tapdesk")

#: Where the certificate, device list and settings live. Overridable so a
#: portable install can keep its state beside the executable.
DEFAULT_CONFIG_DIR = Path.home() / ".tapdesk"

#: The always-available escape hatch. Shown in the window tooltip so the user
#: can find it, and held in one place so it is not spelled three ways.
STOP_HOTKEY = "ctrl+alt+q"


def _is_release(message: dict[str, Any]) -> bool:
    """True for an event that only lets go of something.

    Safe Mode passes these through, so a key held when Safe Mode was switched
    on can still be released rather than staying latched down forever.
    """
    kind = message.get("t")
    if kind == "ping":
        return True
    if kind == "key":
        return message.get("a") in ("release", "up")
    if kind == "click":
        return message.get("a") == "up"
    return False


#: Winsock error numbers, named so the meaning travels with the number.
_WSAEADDRINUSE = 10048
_WSAEACCES = 10013

#: The same two conditions on other platforms. Not theoretical: the protocol
#: is platform-neutral and this file is the one place that has to explain
#: itself to a user, so it should not stop making sense off Windows.
_EADDRINUSE = 98
_EACCES = 13


def describe_startup_error(error: BaseException, port: int) -> str:
    """Turn a failure to bind into a sentence the user can act on.

    Every branch says what to do next, not just what went wrong. "Port 8765 is
    already in use" is only useful if the user is also told that the usual
    cause is a second copy of the app they have not noticed.
    """
    code = getattr(error, "winerror", None) or getattr(error, "errno", None)

    if code in (_WSAEADDRINUSE, _EADDRINUSE):
        return (
            f"Port {port} is already in use, so TapDesk cannot accept "
            "connections from your phone.\n\n"
            "Another copy of TapDesk is almost certainly already running. "
            "Look for it in the system tray, right-click it and choose Quit, "
            "then start TapDesk again."
        )

    if code in (_WSAEACCES, _EACCES):
        return (
            f"Windows refused to let TapDesk open port {port}.\n\n"
            "Another program may be using that port, or a firewall is blocking "
            "it. Close anything else that might be using it, or restart Windows "
            "and try again."
        )

    return (
        f"TapDesk could not start listening on port {port}.\n\n"
        f"The system said: {error}"
    )


class StartupError(Exception):
    """The companion could not start, with a reason the user can act on.

    Its message is written for someone who has never seen this program, not
    for whoever is debugging it. The original "the companion server did not
    start listening" told the user nothing, and neither did the traceback
    behind it, because that was thrown on a background thread and never once
    mentioned the port.
    """


class _Bridge:
    """Hands work to the GUI thread.

    Wraps a QObject signal rather than reaching into Qt directly, so the
    backend stays importable - and testable - with no Qt at all. A plain
    callable is also accepted and run inline, which is what the headless and
    test paths use.
    """

    def __init__(self) -> None:
        self._post: Callable[[Callable[[], None]], None] | None = None
        self._gui_thread: int | None = None

    def attach(self, post: Callable[[Callable[[], None]], None], thread_id: int) -> None:
        self._post = post
        self._gui_thread = thread_id

    def call(self, work: Callable[[], None]) -> None:
        """Run `work` on the GUI thread, or here if there isn't one."""
        if self._post is None or threading.get_ident() == self._gui_thread:
            work()
            return
        self._post(work)


class Companion:
    """The application, independent of how it is displayed."""

    def __init__(
        self,
        config_dir: Path | None = None,
        port: int = DEFAULT_PORT,
        headless: bool = False,
        approve: Callable[[str, str], bool] | None = None,
    ) -> None:
        self.config_dir = config_dir or DEFAULT_CONFIG_DIR
        self.config_dir.mkdir(parents=True, exist_ok=True)

        self.headless = headless

        #: Safe Mode: while on, the phone may release things but never press
        #: them. Off by default, because a companion that ignores input is
        #: useless; the switch exists for when it is not.
        self._safe_mode = False

        #: Test seam. When supplied, pairing decisions come from here and no
        #: dialog is ever shown. Production uses the window instead.
        self._approve_override = approve

        self._ssl, self._certificate = load_ssl_context(self.config_dir)
        self._devices = DeviceStore(self.config_dir / "devices.json")
        self._pairing = PairingManager(
            port=port,
            fingerprint=self._certificate.fingerprint,
        )
        self._simulator = InputSimulator()

        self._bridge = _Bridge()
        self._server = PairingServer(
            cert=self._ssl,
            devices=self._devices,
            pairing=self._pairing,
            on_event=self._on_event,
            on_approval_request=self._ask_approval,
            # A phone that vanishes mid-drag must not leave the desktop with
            # Ctrl down. This is the only thing that lets go of it.
            on_release=self._simulator.release_all,
        )

        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._started = threading.Event()
        self._startup_error: BaseException | None = None
        self._exit: asyncio.Event | None = None
        self._tick_task: Any = None
        self._stopping = False

        self._app: Any = None
        self._window: Any = None
        self._tray: Any = None
        #: Set only in GUI mode; the hotkey needs somewhere to emit to.
        self._emitter: Any = None
        self._poll_timer: Any = None
        self._hotkey_listener: Any = None

    # -- input -------------------------------------------------------------

    def _on_event(self, state: Any, message: dict[str, Any]) -> None:
        """Apply a validated event. Runs on the backend loop.

        Safe Mode is enforced here rather than in the window so that no UI
        path can forget to check it. While it is on, only releases get
        through: the phone can let go of things but cannot press anything.
        That asymmetry is deliberate - you need to be able to stop a runaway
        input, not have it stopped for you.
        """
        if self._safe_mode and not _is_release(message):
            log.debug("safe mode dropped %s", message.get("t"))
            return
        self._simulator.handle(message)

    async def _ask_approval(self, device_name: str, peer: str) -> bool:
        """Ask the user whether to allow this phone.

        Awaited by the server, so this must be a coroutine. It is genuinely
        asynchronous rather than blocking, because the window lives on another
        thread: the dialog is shown there and the answer is resolved back onto
        this loop.
        """
        log.info("pairing request from %s (%s)", device_name, peer)

        if self._approve_override is not None:
            allowed = self._approve_override(device_name, peer)
            log.info("pairing %s by override", "allowed" if allowed else "denied")
            return allowed

        if self.headless or self._window is None:
            # Nobody to ask. Refusing is the only safe answer: allowing would
            # turn a missing UI into a silent auto-approve, which is precisely
            # what the prompt exists to prevent.
            log.warning("refusing, there is nobody to ask")
            return False

        self._bridge.call(self._refresh_window)

        loop = asyncio.get_running_loop()
        answer: asyncio.Future[bool] = loop.create_future()

        def show() -> None:
            from PySide6.QtWidgets import QMessageBox

            box = QMessageBox(self._window)
            box.setWindowTitle("Allow this phone?")
            box.setText(f"Allow <b>{device_name}</b> to control this computer?")
            box.setInformativeText(f"From {peer}")
            box.setIcon(QMessageBox.Icon.Question)
            box.setStandardButtons(
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            # No by default: an accidental Enter must not hand over control of
            # someone's computer.
            box.setDefaultButton(QMessageBox.StandardButton.No)
            result = box.exec() == QMessageBox.StandardButton.Yes
            loop.call_soon_threadsafe(
                lambda: answer.done() or answer.set_result(result)
            )

        self._bridge.call(show)
        return await answer

    # -- the 60 Hz loop ----------------------------------------------------

    async def _run_ticks(self) -> None:
        """Apply the held stick value on a fixed timer.

        See input/simulator.py: the phone sends at 60 Hz and the OS applies at
        its own rate, so sampling here rather than per message is what makes
        the cursor smooth.
        """
        from .input.simulator import TICK_SECONDS

        while not self._stopping:
            await asyncio.sleep(TICK_SECONDS)
            self._simulator.tick()

    def _refresh_window(self) -> None:
        if self._window is None:
            return
        self._window.set_session(self._pairing.current())
        count = self._server.connected_count
        self._window.set_connected(count > 0, count)
        self._window.set_devices(self._devices.devices)

    # -- commands ----------------------------------------------------------

    def disconnect_all(self) -> None:
        """Instantly stop controlling this computer.

        Requirement D8, and the thing a user reaches for when something is
        going wrong. Releases everything held rather than just dropping the
        connection, so nothing stays down on the desktop.
        """
        self._simulator.release_all()
        log.info("control released")
        self._bridge.call(self._refresh_window)

    def revoke(self, device_id: str) -> None:
        if self._devices.revoke(device_id):
            log.info("revoked %s", device_id)
        self._bridge.call(self._refresh_window)

    def set_safe_mode(self, enabled: bool) -> None:
        """Freeze the desktop.

        While on, nothing the phone sends is performed - only releases. The
        user can still type on their own machine, which is the point: if the
        phone has gone wrong, you need to be able to close things without
        fighting it.
        """
        self._safe_mode = enabled
        if enabled:
            self._simulator.release_all()
            log.info("safe mode on")
        else:
            log.info("safe mode off")
        self._bridge.call(self._refresh_window)

    # -- backend -----------------------------------------------------------

    async def _serve(self) -> None:
        """The backend coroutine, running on its own loop in a thread."""
        self._exit = asyncio.Event()
        try:
            await self._server.start(port=self._pairing.port)
        except OSError as exc:
            # Recorded rather than raised. This runs on a background thread, so
            # an exception here dies quietly in the thread and leaves
            # start_backend waiting for a socket that will never bind - which
            # is how a port already in use became "the companion server did
            # not start listening" with no hint of why.
            self._startup_error = exc
            self._started.set()
            return

        self._tick_task = asyncio.create_task(self._run_ticks())
        self._started.set()
        self._publish_link()
        log.info("listening on port %s", self._pairing.port)
        await self._exit.wait()

    def _publish_link(self) -> None:
        """Write the live pairing link to the config directory.

        Without this, anything asking a *running* companion for its code had to
        mint a new session to do it, and got back a token the server had never
        heard of. That made the code useless to a script, and to anything
        automating setup - the token simply never matched.
        """
        session = self._pairing.current()
        path = self.config_dir / "pairing.link"
        try:
            path.write_text(
                f"{session.deep_link()}\n"
                f"fingerprint {session.fingerprint}\n"
                f"port {session.port}\n",
                encoding="utf-8",
            )
        except OSError as exc:  # pragma: no cover - best effort
            log.warning("could not publish the pairing link: %s", exc)

    @staticmethod
    def _read_published_link(config_dir: Path) -> str | None:
        """The link a running companion published, if there is a fresh one."""
        path = config_dir / "pairing.link"
        try:
            return path.read_text(encoding="utf-8")
        except OSError:
            return None

    def start_backend(self, timeout: float = 10.0) -> None:
        """Start the server on a background loop and wait until it listens.

        Waiting for `_started` is what turns "we scheduled the server and
        hoped" into something verifiable: `connected_count` and a real
        connection only work if the socket is genuinely bound.

        Raises [StartupError] with something the user can act on. The point of
        the wording is that "port 8765 is already in use, another copy of
        TapDesk is probably running" is a sentence someone can fix, where
        "did not start listening" is not.
        """
        if self._thread is not None:
            return

        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(
            target=self._run_loop, name="tapdesk-backend", daemon=True
        )
        self._thread.start()

        if not self._started.wait(timeout):
            raise StartupError(
                f"TapDesk did not start listening on port {self._pairing.port}."
            )

        if self._startup_error is not None:
            raise StartupError(describe_startup_error(self._startup_error, self._pairing.port))

    def _run_loop(self) -> None:
        asyncio.set_event_loop(self._loop)
        assert self._loop is not None
        self._loop.create_task(self._serve())
        self._loop.run_forever()

    def stop_backend(self) -> None:
        """Shut the server down cleanly and leave nothing held down."""
        self._stopping = True
        self._simulator.release_all()

        loop, thread = self._loop, self._thread
        # Cleared first so a second call is a no-op, but the locals above are
        # what get used: reading self._loop after nulling it raised
        # AttributeError on every shutdown, so the exception escaped
        # stop_backend and the listener was left running.
        self._loop, self._thread = None, None
        if loop is None or thread is None:
            return

        if self._exit is not None:
            loop.call_soon_threadsafe(self._exit.set)

        loop.call_soon_threadsafe(loop.stop)
        thread.join(timeout=5)
        if not loop.is_closed():
            loop.close()

        listener, self._hotkey_listener = self._hotkey_listener, None
        if listener is not None:
            # Left running it would keep a thread - and its pynput hook -
            # alive after the window is gone.
            try:
                listener.stop()
            except Exception:  # pragma: no cover - best effort
                pass

    # -- run ---------------------------------------------------------------

    def _print_banner(self) -> None:
        session = self._pairing.current()
        print(f"TapDesk companion listening on port {session.port}")
        print(f"  computer : {session.name}")
        print(f"  address  : {', '.join(session.ips) or 'no network address'}")
        print(f"  link     : {session.deep_link()}")
        print(f"  cert     : {session.fingerprint}")
        print(f"  paired   : {len(self._devices)} device(s)")

    def run(self) -> int:
        if self.headless:
            return self._run_headless()
        return self._run_gui()

    def _run_headless(self) -> int:
        try:
            self.start_backend()
        except StartupError as exc:
            # Printed and exited non-zero, so a script or the installer notices.
            # The traceback that used to appear here said nothing about the port.
            print(f"\nTapDesk could not start.\n\n{exc}", file=sys.stderr)
            return 1

        self._print_banner()
        print("Press Ctrl+C to stop.")
        try:
            while True:
                # The backend runs in a thread, so there is no loop to block
                # on. Sleeping is what keeps the process alive and is also
                # where Ctrl+C lands.
                threading.Event().wait(0.25)
        except KeyboardInterrupt:
            print("\nstopping")
            return 0
        finally:
            self.stop_backend()

    def _run_gui(self) -> int:  # pragma: no cover - needs a desktop
        from PySide6.QtCore import QObject, Qt, Signal
        from PySide6.QtWidgets import QApplication

        from .ui.window import MainWindow, Tray, UiCallbacks

        class Emitter(QObject):
            post = Signal(object)
            stop = Signal()

        # Only the program name is passed. Handing our own --config-dir and
        # --port to Qt means it parses them as Qt options, and it does not
        # reliably leave alone the ones it does not recognise. The visible
        # symptom was a startup-failure dialog that appeared for a fraction of
        # a second and closed itself, which is worse than no dialog at all.
        self._app = QApplication([sys.argv[0]])
        self._app.setApplicationName("TapDesk")
        self._app.setQuitOnLastWindowClosed(False)

        # Every call that touches a widget is routed through this emitter.
        # Emitting from the backend thread queues it; emitting from the GUI
        # thread runs it inline, so there is no ordering surprise when the
        # caller is already on the right thread.
        emitter = Emitter()
        emitter.post.connect(
            lambda work: work(), Qt.ConnectionType.QueuedConnection
        )
        # The hotkey listener is pynput's own thread, so the release it detects
        # has to cross to the GUI thread like everything else.
        emitter.stop.connect(self.disconnect_all)
        self._emitter = emitter
        self._bridge.attach(emitter.post.emit, threading.get_ident())

        callbacks = UiCallbacks(
            on_disconnect=self.disconnect_all,
            on_revoke=self.revoke,
            on_quit=self._quit,
            on_safe_mode=self.set_safe_mode,
        )

        self._window = MainWindow(callbacks)
        self._window.set_session(self._pairing.current())
        self._window.set_devices(self._devices.devices)
        self._window.set_hotkey_hint(STOP_HOTKEY)

        self._tray = Tray(callbacks)
        self._tray.show_requested = self._window.show
        self._tray.activated.connect(self._on_tray_activated)

        try:
            self.start_backend()
        except StartupError as exc:
            # A frozen build has no terminal to print to, and PyInstaller's
            # traceback dialog shows a teacher a Python stack trace. Worse, it
            # said nothing about the cause: the exception came from a thread,
            # so the user was left with "did not start listening" and no idea
            # that another copy of the app was holding the port.
            self._explain_and_quit(str(exc))
            return 1

        self._tray.show()
        self._window.show()
        self._print_banner()
        self._refresh_window()

        self._install_hotkey()
        self._poll()

        try:
            return self._app.exec()
        finally:
            self.stop_backend()
            self._simulator.release_all()

    def _explain_and_quit(self, message: str) -> None:
        """Tell the user why TapDesk stopped, in words, then close.

        Two channels, deliberately. A dialog is the friendly one, but a dialog
        is a window: it can be suppressed, auto-dismissed, or blocked by
        whatever else has focus, and a startup failure is exactly the moment
        where the user least needs to be left guessing. So the same words are
        written to startup-error.log in the config directory, and the dialog
        says where that is.

        No traceback either way. This is the first thing most users will ever
        see if something is wrong, and a stack trace through files they have
        never heard of is not an explanation.
        """
        log.error("startup failed: %s", message)

        path = self.config_dir / "startup-error.log"
        try:
            path.write_text(
                f"TapDesk could not start.\n\n{message}\n\n"
                f"Full detail, if you need it:\n{traceback.format_exc()}\n",
                encoding="utf-8",
            )
        except OSError as exc:  # pragma: no cover - best effort
            log.warning("could not write startup-error.log: %s", exc)

        try:
            from PySide6.QtWidgets import QMessageBox

            box = QMessageBox(
                QMessageBox.Icon.Critical, "TapDesk could not start", message
            )
            box.setWindowTitle("TapDesk could not start")
            box.setInformativeText(f"The same message is saved at {path}")
            box.exec()
        except Exception:  # pragma: no cover - the log is the guarantee
            log.exception("could not show the error dialog")

    def _install_hotkey(self) -> None:
        """Register a global emergency stop.

        Requirement D8. Deliberately a low-level listener rather than a Qt
        shortcut: a Qt shortcut only fires while the companion has focus, and
        the whole point is to work when the user is in a browser or a game
        with the companion hidden behind it.

        Implemented as an explicit combination check rather than
        `HotKey.from_keyboard_string`, which this version of pynput does not
        have. Building it by hand also means the combination can be named in
        one place and shown to the user.
        """
        try:
            from pynput import keyboard
        except ImportError:  # pragma: no cover - desktop only
            log.warning("pynput unavailable; no global stop hotkey")
            return

        needed = {keyboard.Key.ctrl_l, keyboard.Key.ctrl_r,
                  keyboard.Key.alt_l, keyboard.Key.alt_r}
        trigger = keyboard.KeyCode.from_char("q")
        pressed: set[Any] = set()

        def on_press(key: Any) -> None:
            pressed.add(key)
            if key == trigger and needed <= pressed:
                self._release_from_hotkey()

        def on_release(key: Any) -> None:
            pressed.discard(key)

        try:
            listener = keyboard.Listener(on_press, on_release)
            listener.start()
            self._hotkey_listener = listener
            log.info("stop hotkey: %s", STOP_HOTKEY)
        except Exception as exc:  # pragma: no cover - desktop only
            # The whole setup is guarded because a missing emergency stop must
            # never cost the user the app: this pynput version has no
            # from_keyboard_string, and an unguarded call took the entire
            # companion down on launch.
            log.warning("no global stop hotkey (%s)", exc)

    def _release_from_hotkey(self) -> None:
        """Handle the stop hotkey from pynput's listener thread."""
        emitter = getattr(self, "_emitter", None)
        if emitter is None:
            self.disconnect_all()
            return
        self._bridge.call(emitter.stop.emit)

    def _poll(self) -> None:
        """Keep the status row honest without polling the window itself."""
        from PySide6.QtCore import QTimer

        timer = QTimer()
        timer.setInterval(1000)
        timer.timeout.connect(self._refresh_window)
        timer.start()
        # Held so it is not collected while the window is alive.
        self._poll_timer = timer

    def _on_tray_activated(self, reason: Any) -> None:  # pragma: no cover
        from PySide6.QtWidgets import QSystemTrayIcon

        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._window.show()

    def _quit(self) -> None:
        if self._app is not None:
            self._app.quit()

    def __del__(self) -> None:  # pragma: no cover - best effort
        try:
            self.stop_backend()
        except Exception:
            pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tapdesk", description="The TapDesk desktop companion."
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT, help="port to listen on"
    )
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=DEFAULT_CONFIG_DIR,
        help="where the certificate and device list are kept",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="serve without a window; prints the pairing link",
    )
    parser.add_argument(
        "--print-link",
        action="store_true",
        help="print the pairing link and exit",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="log everything"
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    )

    companion = Companion(
        config_dir=args.config_dir, port=args.port, headless=args.headless
    )

    # Checked before anything is constructed. Minting a fresh session here would
    # print a token the running server has never heard of, which is worse than
    # useless: it looks right and never pairs.
    if args.print_link:
        published = Companion._read_published_link(args.config_dir)
        if published is not None:
            print(published.strip())
            return 0

        companion = Companion(
            config_dir=args.config_dir, port=args.port, headless=True
        )
        session = companion._pairing.current()
        print(session.deep_link())
        print(f"fingerprint {session.fingerprint}")
        return 0

    companion = Companion(
        config_dir=args.config_dir, port=args.port, headless=args.headless
    )
    return companion.run()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())