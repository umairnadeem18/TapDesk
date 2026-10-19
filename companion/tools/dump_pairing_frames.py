"""Dump every frame the companion sends during a token pairing.

The cross-implementation test saw `auth_err` where it expected `auth_pending`,
and failed without saying which error. This prints the whole sequence so the
cause is a fact rather than a guess.
"""

import asyncio
import json
import socket
import ssl
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tapdesk import protocol as p  # noqa: E402

PYTHON = str(Path(__file__).resolve().parent.parent / ".venv" / "Scripts" / "python.exe")
COMPANION = Path(__file__).resolve().parent.parent


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def main() -> int:
    from websockets.asyncio.client import connect

    port = free_port()
    config = Path(tempfile.mkdtemp(prefix="pairdump-"))
    print(f"port {port}, config {config}")

    child = subprocess.Popen(
        [PYTHON, "-m", "tapdesk.app", "--headless", "--port", str(port), "--config-dir", str(config)],
        cwd=str(COMPANION),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        deadline = asyncio.get_running_loop().time() + 30
        while asyncio.get_running_loop().time() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    break
            except OSError:
                await asyncio.sleep(0.2)

        link_out = await asyncio.to_thread(
            subprocess.run,
            [PYTHON, "-m", "tapdesk.app", "--print-link", "--port", str(port), "--config-dir", str(config)],
            cwd=str(COMPANION),
            capture_output=True,
            text=True,
            timeout=60,
        )
        lines = [l.strip() for l in link_out.stdout.splitlines() if l.strip()]
        deep = lines[0]
        payload = json.loads(
            __import__("base64").urlsafe_b64decode(
                deep.split("d=")[1] + "=" * ((4 - len(deep.split("d=")[1]) % 4) % 4)
            )
        )
        token = payload.get("token")
        print(f"token from link: {str(token)[:12]}...")

        ctx = ssl.create_default_context()
        ctx.load_verify_locations(cafile=str(config / "companion.crt"))
        ctx.check_hostname = False

        ws = await connect(f"wss://127.0.0.1:{port}/", ssl=ctx)
        await ws.send(p.encode({"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"}))
        print("<-", (await asyncio.wait_for(ws.recv(), 10))[:120])

        await ws.send(p.encode({"t": "auth", "token": token}))
        for _ in range(4):
            try:
                raw = await asyncio.wait_for(ws.recv(), 5)
            except asyncio.TimeoutError:
                print("<- (nothing more)")
                break
            print("<-", raw[:160])
            if '"auth_err"' in raw or '"auth_ok"' in raw:
                break
        await ws.close()
        return 0
    finally:
        child.terminate()
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            child.kill()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))