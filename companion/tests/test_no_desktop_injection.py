"""A test suite must never touch the real desktop.

This exists because it already happened. `InputSimulator` used to fall back to
`pynput` when it was constructed without an executor, which meant every test
that built a bare simulator - and every companion started with `--headless`,
which is what `--print-link` and the Dart cross-implementation tests use - was
quietly driving the real mouse and keyboard of whoever happened to be running
it. It moved the developer's pointer in the middle of other work and pressed
Ctrl+P on whatever window had focus, opening a print dialog.

A regression here is invisible in the sense that matters: the suite still
passes. Nothing fails, nothing is logged at warning level, and the person
running it is the thing that gets disturbed. So the assertions here are about
*how* a simulator was built, not about input behaviour.
"""

from __future__ import annotations

import builtins
from pathlib import Path

import pytest

from tapdesk.app import Companion
from tapdesk.input.simulator import InputSimulator


class TestTheDefaultExecutorIsInert:
    def test_a_bare_simulator_is_not_allowed_to_perform_input(self) -> None:
        simulator = InputSimulator()

        # No executor and no opt-in, so it must not be wired to the desktop.
        assert simulator.desktop_input is False

    def test_asking_for_desktop_input_is_the_only_way_to_get_it(self) -> None:
        # The windowed companion relies on this, so it has to keep working.
        assert InputSimulator(desktop_input=True).desktop_input is True

    def test_an_injected_executor_counts_as_safe(self) -> None:
        # A test that passes a recorder is performing nothing regardless of
        # what it asked for, and must not be reported as capable of injection.
        simulator = InputSimulator(executor=lambda action: None, desktop_input=True)

        assert simulator.desktop_input is False

    def test_the_inert_executor_swallows_everything(self) -> None:
        """It must accept anything, including actions it does not know.

        A default that raised on an unrecognised action would turn "harmless"
        into "a test failure about an unrelated thing", which is its own kind
        of nuisance.
        """
        simulator = InputSimulator()

        simulator.handle({"t": "text", "s": "hello"})
        simulator.handle({"t": "click", "b": "left", "a": "click"})
        simulator.handle({"t": "combo", "keys": ["ctrl", "c"]})
        simulator.release_all()


class TestHeadlessNeverInjects:
    """The rule, stated where it is enforced."""

    @pytest.mark.parametrize("headless", [True, False])
    def test_the_flag_decides(self, tmp_path: Path, headless: bool) -> None:
        companion = Companion(config_dir=tmp_path, port=0, headless=headless)

        assert companion._simulator.desktop_input is (not headless)

    def test_a_headless_companion_would_not_reach_pynput(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Proves it by making pynput explode if it is imported.

        Asserting on a flag only proves the flag was set. This fails if any code
        path reaches the real backend another way, which is the only way this
        bug could come back.
        """
        real_import = builtins.__import__

        def guarded(name: str, *args: object, **kwargs: object) -> object:
            if name == "pynput" or name.startswith("pynput."):
                raise AssertionError(
                    "a headless companion reached for pynput, which would move "
                    "the real mouse and press real keys"
                )
            return real_import(name, *args, **kwargs)

        monkeypatch.setattr(builtins, "__import__", guarded)

        companion = Companion(config_dir=tmp_path, port=0, headless=True)
        simulator = companion._simulator
        simulator.handle({"t": "text", "s": "this would have been typed"})
        simulator.handle({"t": "stick", "x": 1.0, "y": 1.0})
        simulator.release_all()