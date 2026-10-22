"""Starting with Windows.

Requested as: "how about you make it a startup app, so when a windows launched
it also launched and qr appears so there is no need to navigate to the folder
where it is located or have to click it to work".

The reason this lives behind a function rather than a Startup-folder shortcut is
that a registry entry survives the app being moved or reinstalled elsewhere,
and can be inspected without the user hunting through AppData.

The important behaviour is the negative one: it must be OFF until asked for. A
program that starts itself without being asked is how software earns a
reputation for being malware, and this one holds an input-injection handle to the
user's whole desktop.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from tapdesk.app import is_autostart_enabled, set_autostart


@pytest.fixture(autouse=True)
def restore_registry():
    """Put the Run key back however it was, whatever the test does.

    These tests write to the real HKCU Run key. That is where the feature lives,
    so mocking it would test the mock rather than the behaviour - but leaving it
    modified would be worse than testing it at all.
    """
    was_enabled = is_autostart_enabled()
    yield
    set_autostart(was_enabled)


@pytest.mark.skipif(
    __import__("sys").platform != "win32", reason="the Run key is Windows-only"
)
class TestAutostart:
    def test_it_starts_off(self) -> None:
        # The whole point of the checkbox being unticked on first run.
        set_autostart(False)
        assert is_autostart_enabled() is False

    def test_turning_it_on_is_observable(self) -> None:
        set_autostart(True)
        assert is_autostart_enabled() is True

    def test_turning_it_off_removes_it(self) -> None:
        set_autostart(True)
        set_autostart(False)
        assert is_autostart_enabled() is False

    def test_turning_it_off_when_already_off_is_not_an_error(self) -> None:
        # Uninstall, or a user clicking twice, must not raise.
        set_autostart(False)
        assert set_autostart(False) is True

    def test_the_entry_points_at_this_executable(self) -> None:
        # A Run key pointing somewhere else is the classic version of this
        # feature: it works until the app is updated, then silently does
        # nothing forever.
        import sys
        import winreg

        set_autostart(True)
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_READ,
        ) as key:
            command, _ = winreg.QueryValueEx(key, "TapDesk")

        assert sys.executable.lower() in command.lower()

    def test_the_cli_reports_success(
        self, capsys: pytest.CaptureFixture, tmp_path: Path
    ) -> None:
        from tapdesk.app import main

        # A config dir of its own, because main() attaches the companion.log
        # handler to the root logger: without this the real ~/.tapdesk log
        # collects every later test's pairing noise.
        argv = ["--config-dir", str(tmp_path)]
        assert main([*argv, "--autostart", "on"]) == 0
        assert "start when Windows starts" in capsys.readouterr().out
        assert is_autostart_enabled() is True

        assert main([*argv, "--autostart", "off"]) == 0
        assert is_autostart_enabled() is False

    def test_the_cli_does_not_launch_the_app(
        self, capsys: pytest.CaptureFixture, tmp_path: Path
    ) -> None:
        # A settings change must not start a server as a side effect.
        from tapdesk.app import main

        main(["--config-dir", str(tmp_path), "--autostart", "on"])
        out = capsys.readouterr().out
        assert "listening" not in out.lower()
        assert "QR" not in out