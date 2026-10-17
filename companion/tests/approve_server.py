"""A companion that approves every pairing request.

Exists purely so the cross-implementation test can get a phone past the
Allow/Deny prompt and reach the point where input frames are validated.

Deliberately a test fixture rather than a `--auto-approve` flag on the real
entry point. A flag that hands control of someone's computer to anybody who can
reach the port is exactly the capability the prompt exists to withhold, and
adding it to the shipped CLI would put that switch one mistyped argument away
from every user. Here it is a separate script that has to be named explicitly,
it lives in the test directory, and no part of `tapdesk.app` can reach it.
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

# Run straight from a checkout, without an editable install: pytest adds the
# rootdir but a plain `python tests/approve_server.py` does not.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tapdesk.app import Companion  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--config-dir", type=Path, required=True)
    args = parser.parse_args()

    logging.basicConfig(level=logging.WARNING)

    companion = Companion(
        config_dir=args.config_dir,
        port=args.port,
        headless=True,
        approve=lambda name, peer: True,
    )

    companion.start_backend()
    # The test needs the same token this process will accept, so publish it
    # exactly as the real companion does.
    companion._publish_link()
    print(f"listening {args.port}", flush=True)

    # The backend runs on its own thread, so there is no loop to block on.
    # Sleeping is what keeps the process alive and is where Ctrl+C lands.
    try:
        while True:
            time.sleep(0.25)
    except KeyboardInterrupt:
        pass
    finally:
        companion.stop_backend()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())