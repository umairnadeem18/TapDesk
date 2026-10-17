"""Tests for input planning and the stick.

The planner is separated from the thing that moves a real mouse precisely so
this can exist: `pynput` cannot be asserted against on a build machine. Every
decision that affects what happens on the user's desktop is made here.
"""

from __future__ import annotations

import pytest

from tapdesk.input import planner
from tapdesk.input.simulator import InputSimulator


class Recorder:
    """Captures actions instead of performing them."""

    def __init__(self) -> None:
        self.actions: list[tuple] = []

    def __call__(self, action: tuple) -> None:
        self.actions.append(action)

    def clear(self) -> None:
        self.actions.clear()


class TestSlide:
    def test_next_sends_pagedown(self) -> None:
        plan = planner.plan_slide("next")
        assert plan.actions == [
            ("key", "pgdn", "down"),
            ("key", "pgdn", "up"),
        ]

    @pytest.mark.parametrize(
        ("action", "expected"),
        [
            ("next", "pgdn"),
            ("prev", "pgup"),
            ("start", "f5"),
            ("end", "esc"),
            ("blank", "b"),
        ],
    )
    def test_every_action_maps_to_its_key(self, action: str, expected: str) -> None:
        plan = planner.plan_slide(action)
        assert plan.actions[0] == ("key", expected, "down")
        assert plan.actions[1] == ("key", expected, "up")

    def test_an_unknown_action_does_nothing(self) -> None:
        # Better a no-op than a guessed keystroke.
        assert not planner.plan_slide("forward")

    def test_a_slide_event_translates(self) -> None:
        assert planner.plan({"t": "slide", "a": "next"}).actions[0][1] == "pgdn"


class TestCombos:
    def test_modifiers_are_released_in_reverse(self) -> None:
        # The releases are part of the sequence, not optional: a chord that
        # pressed Ctrl and never released it would leave Ctrl latched on the
        # desktop for the rest of the session.
        plan = planner.plan_combo(["ctrl", "shift", "p"])
        assert plan.actions == [
            ("key", "ctrl", "down"),
            ("key", "shift", "down"),
            ("key", "p", "down"),
            ("key", "p", "up"),
            ("key", "shift", "up"),
            ("key", "ctrl", "up"),
        ]

    def test_a_combo_leaves_nothing_held(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.handle({"t": "combo", "keys": ["ctrl", "shift", "p"]})
        assert simulator.held.keys == set()

    def test_a_single_key_presses_and_releases(self) -> None:
        plan = planner.plan_combo(["c"])
        assert plan.actions == [("key", "c", "down"), ("key", "c", "up")]
        assert plan.release == []

    def test_an_empty_chord_does_nothing(self) -> None:
        assert not planner.plan_combo([])


class TestClicks:
    def test_click_presses_and_releases(self) -> None:
        assert planner.plan_click("left", "click").actions == [
            ("button", "left", "down"),
            ("button", "left", "up"),
        ]

    def test_double_click_is_two_presses(self) -> None:
        actions = planner.plan_click("left", "double").actions
        assert len(actions) == 4
        assert actions[0] == actions[2] == ("button", "left", "down")

    def test_down_alone_holds_the_button(self) -> None:
        assert planner.plan_click("left", "down").actions == [
            ("button", "left", "down")
        ]

    def test_an_unknown_button_does_nothing(self) -> None:
        assert not planner.plan_click("thumb", "click")


class TestText:
    def test_unicode_passes_through_untouched(self) -> None:
        plan = planner.plan_text("السلام 🎓")
        assert plan.actions == [("text", "السلام 🎓")]

    def test_empty_text_does_nothing(self) -> None:
        assert not planner.plan_text("")


class TestStick:
    def test_centre_is_dead(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(0.0, 0.0)
        assert simulator.stick_delta() == (0, 0)

    def test_inside_the_dead_zone_is_dead(self) -> None:
        # A thumb resting slightly off-centre must not creep the cursor.
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(0.05, 0.03)
        assert simulator.stick_delta() == (0, 0)

    def test_a_deflected_stick_moves_in_that_direction(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(1.0, 0.0)
        dx, dy = simulator.stick_delta()
        assert dx > 0
        assert dy == 0

        simulator.set_stick(0.0, 1.0)
        dx, dy = simulator.stick_delta()
        # +y is up on the wire, so the cursor moves up, which is negative in
        # screen coordinates.
        assert dy < 0

    def test_full_deflection_reaches_the_configured_speed(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(1.0, 0.0)
        assert simulator.stick_delta()[0] == 25

    def test_the_users_speed_setting_scales_it(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(1.0, 0.0)
        simulator.cursor_speed = 2.0
        assert simulator.stick_delta()[0] == 50

    def test_the_curve_gives_finer_control_near_centre(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(0.2, 0.0)
        near_centre = abs(simulator.stick_delta()[0])

        simulator.set_stick(1.0, 0.0)
        at_edge = abs(simulator.stick_delta()[0])

        # Halfway should travel less than half as far, because the curve
        # exponent is above 1.
        assert near_centre < at_edge / 2

    def test_a_stale_stick_stops_moving(self) -> None:
        # The phone died mid-drag. Without this the cursor slides forever.
        import time

        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(1.0, 0.0)
        simulator.stick_updated = time.monotonic() - 5
        assert simulator.stick_delta() == (0, 0)

    def test_tick_applies_the_stick_once_per_frame(self) -> None:
        recorder = Recorder()
        simulator = InputSimulator(executor=recorder)
        simulator.set_stick(1.0, 0.0)
        simulator.tick()
        assert recorder.actions == [("move", 25, 0)]

    def test_a_missive_still_moves(self) -> None:
        # The phone reporting 60 Hz must not cost 60 OS calls a second; the
        # value is sampled on the timer instead.
        recorder = Recorder()
        simulator = InputSimulator(executor=recorder)
        for _ in range(60):
            simulator.handle({"t": "stick", "x": 1.0, "y": 0.0})
        assert recorder.actions == []
        simulator.tick()
        assert len(recorder.actions) == 1


class TestMovement:
    def test_move_deltas_accumulate(self) -> None:
        # Many small moves must add up, not overwrite each other.
        simulator = InputSimulator(executor=Recorder())
        simulator.handle({"t": "move", "dx": 5, "dy": 3})
        simulator.handle({"t": "move", "dx": 2, "dy": -1})
        simulator.tick()
        # stick is centred, so the only move is the accumulated one.
        assert simulator.pending_move == (0, 0)


class TestReleasing:
    def test_release_all_lets_go_of_everything_held(self) -> None:
        # Section 7.10: a disconnected app must never leave the desktop in a
        # state the user cannot diagnose.
        recorder = Recorder()
        simulator = InputSimulator(executor=recorder)

        simulator.handle({"t": "key", "k": "ctrl", "a": "press"})
        simulator.handle({"t": "click", "b": "left", "a": "down"})
        assert simulator.held.keys == {"ctrl"}
        assert simulator.held.buttons == {"left"}

        recorder.clear()
        simulator.release_all()

        assert recorder.actions == [
            ("key", "ctrl", "up"),
            ("button", "left", "up"),
        ]
        assert simulator.held.keys == set()
        assert simulator.held.buttons == set()

    def test_release_all_clears_a_stuck_stick(self) -> None:
        simulator = InputSimulator(executor=Recorder())
        simulator.set_stick(1.0, 1.0)
        simulator.release_all()
        assert simulator.stick == (0.0, 0.0)

    def test_nothing_is_released_that_was_not_held(self) -> None:
        recorder = Recorder()
        simulator = InputSimulator(executor=recorder)
        simulator.handle({"t": "key", "k": "a", "a": "tap"})
        recorder.clear()
        simulator.release_all()
        # A completed tap is already up; releasing again would send a spurious
        # key-up and can confuse an application that tracks its own state.
        assert recorder.actions == []


class TestKeyMapping:
    def test_every_protocol_key_can_reach_the_desktop(self) -> None:
        from tapdesk.input.simulator import _PYNPUT_SPECIAL
        from tapdesk import protocol as p

        # A key with no mapping is a key that silently does nothing on the
        # desktop while looking perfectly fine on the phone. Single characters
        # are typed literally, so only named keys need an entry.
        single_characters = {k for k in p.KEY_IDS if len(k) == 1}
        missing = sorted(
            (p.KEY_IDS - set(_PYNPUT_SPECIAL)) - single_characters
        )
        assert missing == [], f"no desktop mapping for: {missing}"

    def test_the_named_mappings_exist_on_the_pynput_controller(self) -> None:
        # An earlier version used controller.ctrl and friends, which do not
        # exist: pynput exposes named keys through Key enum members. This walks
        # the real objects so the mapping cannot rot silently.
        from pynput.keyboard import Controller

        from tapdesk.input.simulator import _PYNPUT_SPECIAL

        controller = Controller()
        for key_id, attribute in _PYNPUT_SPECIAL.items():
            assert hasattr(controller, attribute), (
                f"{key_id} maps to controller.{attribute}, which does not exist"
            )
