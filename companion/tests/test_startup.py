"""What happens when the companion cannot start.

The user reported this as an unhandled Python traceback reading "the companion
server did not start listening". The traceback was true and useless: it never
mentioned the port, and the actual cause - another copy of the app already
holding it - was thrown on a background thread and silently discarded.

So these tests reproduce the exact failure by occupying the port first, and
then insist the message says what happened and what to do about it.
"""

from __future__ import annotations

import socket
import sys
from pathlib import Path

import pytest

from tapdesk.app import (
    StartupError,
    describe_startup_error,
)

pytestmark = pytest.mark.timeout(30)


def occupy(port: int) -> socket.socket:
    """Hold a port the way a second copy of TapDesk would."""
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", port))
    sock.listen(1)
    return sock


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def busy_port_error() -> OSError:
    """What Windows actually raises when the port is taken.

    Built with an explicit winerror rather than a bare OSError, because a bare
    one carries no code and would fall through to the generic branch - which is
    how the original bug survived a test that "checked the message".
    """
    error = OSError(10048, "Only one usage of each socket address is normally permitted")
    error.winerror = 10048  # type: ignore[attr-defined]
    return error


def denied_error() -> OSError:
    error = OSError(10013, "Access is denied")
    error.winerror = 10013  # type: ignore[attr-defined]
    return error


class TestMessages:
    def test_a_busy_port_names_the_port(self) -> None:
        message = describe_startup_error(busy_port_error(), 8765)
        assert "8765" in message

    def test_a_busy_port_says_what_the_user_should_do(self) -> None:
        # The whole point. "Port in use" is a fact; the user needs the remedy.
        message = describe_startup_error(busy_port_error(), 8765)
        lowered = message.lower()
        assert "already running" in lowered
        assert "tray" in lowered or "quit" in lowered

    def test_the_same_condition_is_recognised_on_other_platforms(self) -> None:
        # The protocol is platform-neutral and this message is the one place the
        # app explains itself, so it should not stop making sense off Windows.
        message = describe_startup_error(OSError(98, "Address already in use"), 8765)
        assert "already running" in message.lower()

    def test_a_denied_port_suggests_something_different(self) -> None:
        # A firewall or another program blocks it; quitting a second copy of
        # TapDesk would not help, so the advice must differ.
        message = describe_startup_error(denied_error(), 8765)
        assert "firewall" in message.lower()

    def test_an_unknown_error_still_repeats_the_system_message(self) -> None:
        message = describe_startup_error(OSError("something odd"), 8765)
        assert "something odd" in message

    def test_every_message_says_something_actionable(self) -> None:
        for error in (busy_port_error(), denied_error(), OSError("weird")):
            message = describe_startup_error(error, 8765)
            assert len(message) > 40, message
            assert "\n\n" in message, "expected advice after the problem"


class TestStartingOnABusyPort:
    def test_it_raises_with_an_actionable_message(self, tmp_path: Path) -> None:
        from tapdesk.app import Companion

        port = free_port()
        blocker = occupy(port)
        try:
            companion = Companion(config_dir=tmp_path, port=port, headless=True)

            with pytest.raises(StartupError) as caught:
                companion.start_backend()

            # Before this was fixed the user got a bare TimeoutError whose text
            # never mentioned the port, so there was nothing to act on.
            assert str(port) in str(caught.value)
            assert "already" in str(caught.value).lower()

            companion.stop_backend()
        finally:
            blocker.close()

    def test_headless_reports_it_instead_of_a_traceback(
        self, tmp_path: Path, capsys: pytest.CaptureFixture
    ) -> None:
        from tapdesk.app import Companion

        port = free_port()
        blocker = occupy(port)
        try:
            companion = Companion(config_dir=tmp_path, port=port, headless=True)
            code = companion._run_headless()
            companion.stop_backend()

            captured = capsys.readouterr()
            assert code != 0, "a failure must be visible to a script"
            assert "could not start" in captured.err.lower()
            assert "Traceback" not in captured.err, (
                "a user-facing failure must not show a Python stack trace"
            )
        finally:
            blocker.close()

    def test_it_does_not_wait_the_full_timeout_to_fail(self, tmp_path: Path) -> None:
        # A bind failure is immediate. Waiting ten seconds to be told the port
        # is taken is ten seconds of a frozen-looking app for no reason.
        import time

        from tapdesk.app import Companion

        port = free_port()
        blocker = occupy(port)
        try:
            companion = Companion(config_dir=tmp_path, port=port, headless=True)
            started = time.monotonic()
            with pytest.raises(StartupError):
                companion.start_backend(timeout=30)
            elapsed = time.monotonic() - started

            assert elapsed < 5, f"took {elapsed:.1f}s to report a bind failure"
            companion.stop_backend()
        finally:
            blocker.close()


@pytest.fixture(autouse=True)
def no_dialogs(monkeypatch: pytest.MonkeyPatch) -> None:
    """Stop _explain_and_quit from putting a modal dialog on screen.

    These tests are about the message and the log file, not about Qt. Left
    alone, `exec()` blocks and the test times out - which is exactly the
    behaviour a user would get, and precisely why it cannot run unattended.
    """
    import PySide6.QtWidgets as widgets

    monkeypatch.setattr(widgets.QMessageBox, "exec", lambda self: 0)


class TestTheMessageReachesTheUser:
    """A dialog is a window, and a window can fail.

    The log file is the guarantee. If the dialog is suppressed, auto-dismissed,
    or blocked by whatever has focus - all plausible at exactly the moment
    something has gone wrong - the user must still be able to find out why.
    """

    def test_the_reason_is_written_where_the_user_can_find_it(
        self, tmp_path: Path
    ) -> None:
        from tapdesk.app import Companion

        companion = Companion(config_dir=tmp_path, port=8765, headless=True)
        companion._explain_and_quit("Port 8765 is already in use.")

        written = (tmp_path / "startup-error.log").read_text(encoding="utf-8")
        assert "8765" in written
        assert "already in use" in written

    def test_the_file_also_keeps_the_technical_detail(
        self, tmp_path: Path
    ) -> None:
        # The plain message for the user, the traceback for whoever is asked to
        # help them. Both, because a bug report with neither is useless.
        from tapdesk.app import Companion

        companion = Companion(config_dir=tmp_path, port=8765, headless=True)
        companion._explain_and_quit("Something went wrong.")

        written = (tmp_path / "startup-error.log").read_text(encoding="utf-8")
        assert "Full detail" in written

    def test_a_broken_dialog_does_not_hide_the_message(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # If showing the dialog itself fails, the log must already be written.
        import PySide6.QtWidgets as widgets

        def explode(*args: object, **kwargs: object) -> None:
            raise RuntimeError("no display")

        monkeypatch.setattr(widgets.QMessageBox, "exec", explode)

        from tapdesk.app import Companion

        companion = Companion(config_dir=tmp_path, port=8765, headless=True)
        companion._explain_and_quit("Port 8765 is already in use.")

        assert "already in use" in (
            tmp_path / "startup-error.log"
        ).read_text(encoding="utf-8")


class TestFreePortStillWorks:
    def test_an_unobstructed_port_starts_normally(self, tmp_path: Path) -> None:
        # The fix must not have broken the ordinary case.
        from tapdesk.app import Companion

        companion = Companion(config_dir=tmp_path, port=free_port(), headless=True)
        try:
            companion.start_backend()
            assert companion._started.is_set()
            assert companion._startup_error is None
        finally:
            companion.stop_backend()