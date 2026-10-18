"""Entry point for the frozen executable.

Kept deliberately thin. `tapdesk.app.main` is the real entry point and is what
tests import; this exists only so PyInstaller has a file to point at, and so
that a frozen app and a source checkout behave identically.

The `multiprocessing.freeze_support()` call is what stops a frozen build from
re-executing itself when a child process is spawned - without it, PySide6's
image loader can launch the app a second time.
"""

from __future__ import annotations

import multiprocessing
import sys


def run() -> int:
    # Frozen builds inherit the parent's argv otherwise, which makes PySide6
    # try to parse build-tool arguments as Qt options.
    if getattr(sys, "frozen", False):
        multiprocessing.freeze_support()

    from tapdesk.app import main

    return main()


if __name__ == "__main__":
    raise SystemExit(run())