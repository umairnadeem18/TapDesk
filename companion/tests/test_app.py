"""Tests for the application wiring and the window.

The window is constructed against Qt's offscreen platform so it can be built
and driven on a machine with no display. That catches the class of bug where
the window only fails once a user tries to start the app.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from tapdesk import qr  # noqa: E402
from tapdesk.app import Companion  # noqa: E402
from tapdesk.devices import DeviceStore  # noqa: E402
from tapdesk.session import PairingManager  # noqa: E402
from tapdesk import tls  # noqa: E402


class TestCompanion:
    def test_it_constructs_and_has_a_fingerprint(self, tmp_path: Path) -> None:
        companion = Companion(headless=True, config_dir=tmp_path)
        assert len(companion._pairing.fingerprint) == 64

    def test_it_reuses_its_certificate_across_runs(self, tmp_path: Path) -> None:
        first = Companion(headless=True, config_dir=tmp_path)
        second = Companion(headless=True, config_dir=tmp_path)
        # A new fingerprint each launch would force a re-scan every boot.
        assert first._pairing.fingerprint == second._pairing.fingerprint

    def test_the_pairing_link_parses_back_to_the_same_data(
        self, tmp_path: Path
    ) -> None:
        import base64
        import json

        companion = Companion(headless=True, config_dir=tmp_path)
        link = companion._pairing.current().deep_link()
        encoded = link.split("d=", 1)[1]
        padded = encoded + "=" * (-len(encoded) % 4)
        data = json.loads(base64.urlsafe_b64decode(padded))

        assert data["v"] == 1
        assert data["fp"] == companion._pairing.fingerprint
        assert data["port"] == companion._pairing.port

    def test_disconnect_releases_everything_held(self, tmp_path: Path) -> None:
        companion = Companion(headless=True, config_dir=tmp_path)
        companion._simulator.handle({"t": "key", "k": "ctrl", "a": "press"})
        companion._simulator.handle({"t": "click", "b": "left", "a": "down"})
        assert companion._simulator.held.keys

        companion.disconnect_all()

        assert companion._simulator.held.keys == set()
        assert companion._simulator.held.buttons == set()

    def test_revoking_forgets_the_device(self, tmp_path: Path) -> None:
        companion = Companion(headless=True, config_dir=tmp_path)
        device, key = companion._devices.pair(name="Pixel 7", fingerprint="a" * 64)
        assert companion._devices.find_by_key(key) is not None

        companion.revoke(device.device_id)

        assert companion._devices.find_by_key(key) is None

    def test_devices_survive_a_restart(self, tmp_path: Path) -> None:
        first = Companion(headless=True, config_dir=tmp_path)
        device, key = first._devices.pair(name="Pixel 7", fingerprint="a" * 64)

        second = Companion(headless=True, config_dir=tmp_path)
        assert second._devices.find_by_key(key) is not None


class TestQR:
    def test_it_renders_a_scannable_size(self) -> None:
        rendered = qr.render("tapdesk://pair?d=abc")
        assert rendered.png.startswith(b"\x89PNG")
        assert rendered.side > 20, "a tiny matrix will not scan reliably"

    def test_a_longer_payload_still_fits(self) -> None:
        # The real deep link carries a 43-character token and a 64-character
        # fingerprint. If that did not fit, every QR would be undeliverable.
        companion_payload = "tapdesk://pair?d=" + "e" * 320
        assert qr.render(companion_payload).side > 20


class TestWindow:
    def test_the_window_builds_and_shows_a_session(self, tmp_path: Path) -> None:
        from PySide6.QtWidgets import QApplication

        from tapdesk.ui.window import MainWindow, UiCallbacks

        app = QApplication.instance() or QApplication([])

        companion = Companion(headless=True, config_dir=tmp_path)
        window = MainWindow(
            UiCallbacks(
                on_disconnect=lambda: None,
                on_revoke=lambda device_id: None,
                on_quit=lambda: None,
            )
        )
        window.set_session(companion._pairing.current())
        window.set_devices(companion._devices.devices)

        # The name and address are what the user checks before scanning, so an
        # empty window is a real failure, not a cosmetic one.
        assert window._name.text() == companion._pairing.name
        assert "port" in window._address.text()
        assert window._qr_label.pixmap() is not None

    def test_the_pin_is_hidden_until_it_is_needed(self, tmp_path: Path) -> None:
        from PySide6.QtWidgets import QApplication

        from tapdesk.ui.window import MainWindow, UiCallbacks

        app = QApplication.instance() or QApplication([])

        companion = Companion(headless=True, config_dir=tmp_path)
        window = MainWindow(
            UiCallbacks(
                on_disconnect=lambda: None,
                on_revoke=lambda device_id: None,
                on_quit=lambda: None,
            )
        )
        window.set_session(companion._pairing.current())

        # A one-time code on screen permanently would invite shoulder-surfing.
        assert window._manual.isVisible() is False

        window.show_pin(True)
        window.set_session(companion._pairing.current())
        assert "PIN" in window._manual.text()
