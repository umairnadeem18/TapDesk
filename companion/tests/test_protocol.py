"""Tests for the protocol mirror.

These are the companion's half of `docs/protocol.md`. The Flutter side has an
identical set of tests asserting the same frames; if either drifts, one of the
two suites fails rather than a message being silently dropped in a lecture hall.
"""

from __future__ import annotations

import json

import pytest

from tapdesk import protocol as p


class TestEncodeDecode:
    def test_round_trips_a_slide_action(self) -> None:
        wire = p.encode({"t": "slide", "a": "next"})
        assert wire == '{"t":"slide","a":"next"}'
        assert p.decode(wire) == {"t": "slide", "a": "next"}

    def test_rejects_a_frame_over_the_cap(self) -> None:
        with pytest.raises(p.ProtocolError) as caught:
            p.encode({"t": "text", "s": "x" * (p.MAX_FRAME_BYTES + 10)})
        assert caught.value.code == p.E_TOO_LARGE

    @pytest.mark.parametrize("bad", ["not json", "[]", '"a string"', "123", "{}"])
    def test_rejects_malformed_frames(self, bad: str) -> None:
        with pytest.raises(p.ProtocolError) as caught:
            p.decode(bad)
        assert caught.value.code == p.E_MALFORMED

    def test_unicode_survives_the_round_trip(self) -> None:
        # The whole reason printable characters travel as text rather than as
        # key ids: Urdu has no key to press.
        wire = p.encode({"t": "text", "s": "السلام"})
        assert p.decode(wire)["s"] == "السلام"


class TestStick:
    def test_accepts_the_range(self) -> None:
        p.validate({"t": "stick", "x": 0.42, "y": -0.15})

    @pytest.mark.parametrize("value", [1.4, -1.1, 2.0])
    def test_rejects_out_of_range(self, value: float) -> None:
        with pytest.raises(p.ProtocolError) as caught:
            p.validate({"t": "stick", "x": value, "y": 0})
        assert caught.value.code == p.E_BAD_FIELD

    def test_rejects_a_boolean_masquerading_as_a_number(self) -> None:
        # In Python True is an int. Without this check a client sending
        # {"x": true} would move the cursor to maximum deflection.
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "stick", "x": True, "y": 0})


class TestKeys:
    def test_accepts_every_documented_key_id(self) -> None:
        for key in sorted(p.KEY_IDS):
            p.validate({"t": "key", "k": key, "a": "tap"})

    @pytest.mark.parametrize("key", ["super", "cmd", "f13", "", "CTRL"])
    def test_rejects_unknown_key_ids(self, key: str) -> None:
        with pytest.raises(p.ProtocolError) as caught:
            p.validate({"t": "key", "k": key, "a": "tap"})
        assert caught.value.code == p.E_BAD_FIELD

    def test_rejects_a_bad_action(self) -> None:
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "key", "k": "a", "a": "smash"})


class TestCombos:
    def test_accepts_one_to_four_keys(self) -> None:
        p.validate({"t": "combo", "keys": ["ctrl"]})
        p.validate({"t": "combo", "keys": ["ctrl", "shift", "alt", "delete"]})

    @pytest.mark.parametrize("keys", [[], ["a", "b", "c", "d", "e"]])
    def test_rejects_out_of_range_chords(self, keys: list[str]) -> None:
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "combo", "keys": keys})

    def test_safe_mode_blocks_win_r(self) -> None:
        with pytest.raises(p.ProtocolError) as caught:
            p.validate({"t": "combo", "keys": ["win", "r"]})
        assert caught.value.code == p.E_UNSAFE

    def test_safe_mode_is_order_insensitive(self) -> None:
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "combo", "keys": ["r", "win"]})

    def test_safe_mode_allows_ordinary_chords(self) -> None:
        p.validate({"t": "combo", "keys": ["ctrl", "c"]})
        p.validate({"t": "combo", "keys": ["ctrl", "shift", "p"]})


class TestText:
    def test_accepts_urdu_and_emoji(self) -> None:
        p.validate({"t": "text", "s": "السلام 🎓"})

    def test_rejects_over_length(self) -> None:
        with pytest.raises(p.ProtocolError) as caught:
            p.validate({"t": "text", "s": "x" * (p.MAX_TEXT_CHARS + 1)})
        assert caught.value.code == p.E_BAD_FIELD

    def test_allows_newline_and_tab(self) -> None:
        p.validate({"t": "text", "s": "line one\nline two\tindented"})

    def test_rejects_other_control_characters(self) -> None:
        # Injecting a stray escape into whatever the user is typing in can do
        # confusing things in a shell or a terminal.
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "text", "s": "danger\x1b[31m"})


class TestSlide:
    def test_accepts_every_action(self) -> None:
        for action in sorted(p.SLIDE_ACTIONS):
            p.validate({"t": "slide", "a": action})

    def test_rejects_an_unknown_action(self) -> None:
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "slide", "a": "forward"})

    def test_every_action_maps_to_at_least_one_key(self) -> None:
        # A slide action with no keys would be a button that silently does
        # nothing, so this is checked explicitly.
        for action in p.SLIDE_ACTIONS:
            assert p.SLIDE_KEYS[action]


class TestUnknownTypes:
    def test_unknown_type_is_dropped_not_fatal(self) -> None:
        # An older phone talking to a newer companion must degrade quietly,
        # so this is explicitly not an error.
        p.validate({"t": "laser_pointer", "colour": "red"})

    def test_known_types_still_validate(self) -> None:
        with pytest.raises(p.ProtocolError):
            p.validate({"t": "click", "b": "thumb", "a": "click"})


class TestFrameCompatibility:
    def test_every_documented_example_from_the_protocol(self) -> None:
        """The worked examples in section 9 of the protocol."""
        examples = [
            '{"t":"ping","ts":1763308800123}',
            '{"t":"stick","x":0.42,"y":0.15}',
            '{"t":"text","s":"السلام"}',
            '{"t":"combo","keys":["ctrl","shift","p"]}',
            '{"t":"slide","a":"next"}',
        ]
        for wire in examples:
            message = p.decode(wire)
            if message["t"] != "ping":
                p.validate(message)

    def test_key_ids_match_the_shared_set(self) -> None:
        # A spot check against the ids the Flutter side declares. If these two
        # ever disagree, the phone sends something the PC drops with E_BAD_FIELD.
        for key in ["enter", "backspace", "space", "f5", "ctrl", "shift", "pgdn"]:
            assert key in p.KEY_IDS

    def test_rate_limit_table_covers_every_input_type(self) -> None:
        for kind in ["stick", "key", "click", "combo", "slide", "move", "scroll", "text"]:
            assert kind in p.RATE_LIMITS

    def test_rates_are_serialisable(self) -> None:
        # The companion writes its limits to the phone in `welcome`.
        json.dumps({k: list(v) for k, v in p.RATE_LIMITS.items()})
