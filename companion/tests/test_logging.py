"""The companion's own flight recorder.

~/.tapdesk/companion.log - or the config dir a caller passes - is the only
record a windowed exe keeps of who connected, who was refused and why. These
tests pin the property that made the first logs readable rather than noise:
one process, one handler.
"""

from __future__ import annotations

import logging
from pathlib import Path

from tapdesk.app import _enable_file_logging


def test_attaches_exactly_one_handler_no_matter_how_often_it_runs(tmp_path: Path) -> None:
    before = list(logging.getLogger().handlers)
    try:
        for _ in range(3):
            _enable_file_logging(tmp_path)

        file_handlers = [
            handler
            for handler in logging.getLogger().handlers
            if getattr(handler, "_tapdesk_file_log", False)
        ]
        assert len(file_handlers) == 1, (
            "repeated runs stacked handlers and wrote every line of the log "
            "once per stacking - the first companion.log was read through "
            "this exact nonsense"
        )
    finally:
        for handler in list(logging.getLogger().handlers):
            if handler not in before:
                logging.getLogger().removeHandler(handler)
                handler.close()


def test_the_log_lands_where_the_caller_says(tmp_path: Path) -> None:
    before = list(logging.getLogger().handlers)
    # The real app runs basicConfig(INFO) before this; reproduce that, since a
    # fresh root logger defaults to WARNING and would swallow the probe line.
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    try:
        _enable_file_logging(tmp_path)
        root.info("probe line for the test's own directory")
        for handler in root.handlers:
            handler.flush()

        log = tmp_path / "companion.log"
        assert "probe line" in log.read_text(encoding="utf-8")
    finally:
        root.setLevel(logging.WARNING)
        for handler in list(root.handlers):
            if handler not in before:
                root.removeHandler(handler)
                handler.close()
