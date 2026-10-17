"""The companion application.

Wires the server, the input simulator, the window and the tray together. This
is the piece you actually run.

Deliberately importable without a display: `--headless` prints the pairing link
and serves, which is how the server is tested on a machine with no desktop, and
how it can be checked over SSH.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import sys
from pathlib import Path
from typing import Any

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


class Companion:
    """The application, independent of how it is displayed."""

    def __init__(
        self,
        config_dir: Path | None = None,
        port: int = DEFAULT_PORT,
        headless: bool = False,
    ) -> None:
        self.config_dir = config_dir or DEFAULT_CONFIG_DIR
        self.config_dir.mkdir(parents=True, exist_ok=True)

        self.headless = headless
        self._ssl, self._certificate = load_ssl_context(self.config_dir)
        self._devices = DeviceStore(self.config_dir / "devices.json")
        self._pairing = PairingManager(
            port=port,
            fingerprint=self._certificate.fingerprint,
        )
        self._simulator = InputSimulator()

        self._server = PairingServer(
            cert=self._ssl,
            devices=self._devices,
            pairing=self._pairing,
            on_event=self._on_event,
            on_approval_request=self._ask_approval,
        )

        self._tick_task: asyncio.Task | None = None
        self._app: Any = None
        self._window: Any = None
        self._tray: Any = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._exit = asyncio.Event()

    # -- input -------------------------------------------------------------

    def _on_event(self, state: Any, message: dict[str, Any]) -> None:
        """Apply a validated event. Called from the server's event loop."""
        self._simulator.handle(message)
        if message["t"] == "stick":
            self._refresh_window()

    def _ask_approval(self, device_name: str, peer: str) -> bool:
        """Ask the user. Blocking, because the handshake is waiting on it."""
        log.info("pairing request from %s (%s)", device_name, peer)
        if self.headless:
            # No window means no way to ask, and refusing is the safe answer.
            log.warning("headless: refusing, there is nobody to ask")
            return False

        from PySide6.QtWidgets import QApplication, QMessageBox

        self._refresh_window()
        box = QMessageBox(self._window)
        box.setWindowTitle("Allow this phone?")
        box.setText(f"Allow <b>{device_name}</b> to control this computer?")
        box.setInformativeText(f"From {peer}")
        box.setIcon(QMessageBox.Icon.Question)
        box.setStandardButtons(
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        box.setDefaultButton(QMessageBox.StandardButton.No)
        # No by default: an accidental Enter should not grant control of
        # someone's computer.
        return box.exec() == QMessageBox.StandardButton.Yes

    # -- the 60 Hz loop ----------------------------------------------------

    async def _run_ticks(self) -> None:
        """Apply the held stick value on a fixed timer.

        See input/simulator.py: the phone sends at 60 Hz and the OS applies at
        its own rate, so sampling here rather than per message is what makes
        the cursor smooth.
        """
        from .input.simulator import TICK_SECONDS

        while not self._exit.is_set():
            await asyncio.sleep(TICK_SECONDS)
            self._simulator.tick()

    def _refresh_window(self) -> None:
        if self._window is None:
            return
        self._window.set_session(self._pairing.current())
        self._window.set_connected(
            self._server.connected_count > 0, self._server.connected_count
        )
        self._window.set_devices(self._devices.devices)
        self._window.show_pin(False)

    # -- commands ----------------------------------------------------------

    def disconnect_all(self) -> None:
        """Instantly stop controlling this computer.

        Requirement D8, and the thing a user reaches for when something is
        going wrong. It releases everything held rather than just dropping the
        connection, so nothing stays down on the desktop.
        """
        self._simulator.release_all()
        log.info("control released")
        self._refresh_window()

    def revoke(self, device_id: str) -> None:
        if self._devices.revoke(device_id):
            log.info("revoked %s", device_id)
        self._refresh_window()

    # -- run ---------------------------------------------------------------

    async def _serve(self) -> None:
        await self._server.start(port=self._pairing.port)
        self._tick_task = asyncio.create_task(self._run_ticks())
        session = self._pairing.current()
        print(f"TapDesk companion listening on port {session.port}")
        print(f"  computer : {session.name}")
        print(f"  address  : {', '.join(session.ips)}")
        print(f"  link     : {session.deep_link()}")
        print(f"  cert     : {session.fingerprint}")
        print(f"  paired   : {len(self._devices)} device(s)")
        print("Press Ctrl+C to stop.")

        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            with_signal = getattr(loop, "add_signal_handler", None)
            if with_signal:
                try:
                    loop.add_signal_handler(sig, self._exit.set)
                except NotImplementedError:  # pragma: no cover - Windows
                    pass

        await self._exit.wait()

    def run(self) -> int:
        try:
            if self.headless:
                asyncio.run(self._serve())
                return 0
            return self._run_gui()
        except KeyboardInterrupt:
            return 0

    def _run_gui(self) -> int:  # pragma: no cover - needs a desktop
        from PySide6.QtWidgets import QApplication

        from .ui.window import MainWindow, Tray, UiCallbacks

        self._app = QApplication(sys.argv)
        self._app.setQuitOnLastWindowClosed(False)

        callbacks = UiCallbacks(
            on_disconnect=self.disconnect_all,
            on_revoke=self.revoke,
            on_quit=self._quit,
        )

        self._window = MainWindow(callbacks)
        self._window.countdown.connect(
            lambda: self._window.set_session(self._pairing.current())
        )
        self._window.set_session(self._pairing.current())
        self._window.set_devices(self._devices.devices)
        self._window.show()

        self._tray = Tray(callbacks)
        self._tray._show_requested = self._window.show  # type: ignore[attr-defined]
        self._tray.activated.connect(self._on_tray_activated)
        self._tray.show()

        loop = asyncio.new_event_loop()
        self._loop = loop

        def on_ready() -> None:
            asyncio.set_event_loop(loop)
            loop.create_task(self._server.start(port=self._pairing.port))
            loop.create_task(self._run_ticks())
            self._refresh_window()

        from PySide6.QtCore import QTimer

        QTimer.singleShot(0, on_ready)
        QTimer.singleShot(2000, self._refresh_window)

        try:
            return self._app.exec()
        finally:
            self._shutdown()

    def _on_tray_activated(self, reason: Any) -> None:  # pragma: no cover
        from PySide6.QtWidgets import QSystemTrayIcon

        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._window.show()

    def _quit(self) -> None:
        self._exit.set()
        if self._app is not None:
            self._app.quit()

    def _shutdown(self) -> None:
        # Leave nothing held down on exit, whatever happened.
        self._simulator.release_all()


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

    if args.print_link:
        session = companion._pairing.current()
        print(session.deep_link())
        print(f"fingerprint {session.fingerprint}")
        return 0

    return companion.run()


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
