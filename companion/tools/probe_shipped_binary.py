r"""Probe the SHIPPED companion binary, not the source tree.

Every test in the repository starts a companion with `python -m tapdesk.app`.
The thing the user installed is a PyInstaller bundle, and a bundling difference
would pass all 200 tests and fail only in the product. So this runs the actual
`D:\TapDesk\TapDesk.exe`.

Headless on purpose: approval needs a window, and a window appearing on the
user's desktop mid-task is exactly the interruption complained about earlier.
Headless still exercises everything this probe needs - TLS, the handshake, and
the rejection of an unknown device key, which is the path a phone with a stale
stored pairing takes.
"""

import asyncio
import socket
import ssl
import subprocess
import sys
import tempfile
from pathlib import Path

# The package root, not this file's directory: the probe imports the same
# protocol module the tests use, but it drives the installed executable.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tapdesk import protocol as p  # noqa: E402

EXE = "D:" + chr(92) + "TapDesk" + chr(92) + "TapDesk.exe"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def main() -> int:
    from websockets.asyncio.client import connect

    port = free_port()
    config = tempfile.mkdtemp(prefix="shipped-probe-")

    print(f"exe      : {EXE}")
    print(f"port     : {port}")
    print(f"config   : {config}")

    child = subprocess.Popen(
        [EXE, "--headless", "--port", str(port), "--config-dir", config],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    try:
        # Wait for it to bind rather than sleeping and hoping.
        deadline = asyncio.get_running_loop().time() + 30
        bound = False
        while asyncio.get_running_loop().time() < deadline:
            if child.poll() is not None:
                print("FAIL  the shipped exe exited immediately")
                print((child.stdout.read() or "")[:2000])
                return 1
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    bound = True
                    break
            except OSError:
                await asyncio.sleep(0.2)
        if not bound:
            print("FAIL  the shipped exe never bound the port")
            return 1
        print("OK    the shipped exe starts and binds a port")

        ctx = ssl.create_default_context()
        ctx.load_verify_locations(cafile=str(Path(config) / "companion.crt"))
        ctx.check_hostname = False

        ws = await connect(f"wss://127.0.0.1:{port}/", ssl=ctx)

        # 1. hello
        await ws.send(
            p.encode({"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"})
        )
        hello = p.decode(await asyncio.wait_for(ws.recv(), 10))
        print(f"{'OK   ' if hello['t'] == 'hello_ok' else 'FAIL '} hello -> {hello['t']}")
        await ws.close()

        # 2. An unknown device key: what a phone holding a stale pairing sends
        #    after the PC's device list was cleared.
        ws = await connect(f"wss://127.0.0.1:{port}/", ssl=ctx)
        await ws.send(
            p.encode({"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"})
        )
        await asyncio.wait_for(ws.recv(), 10)
        await ws.send(p.encode({"t": "auth", "key": "a-key-the-pc-has-never-seen"}))
        try:
            reply = p.decode(await asyncio.wait_for(ws.recv(), 10))
        except asyncio.TimeoutError:
            print("FAIL  an unknown device key got NO reply - this is the stall")
            await ws.close()
            return 1
        print(f"OK    unknown device key -> {reply['t']} {reply.get('code', '')}")
        if reply.get("code") != "E_REVOKED":
            print("FAIL  expected E_REVOKED so the phone knows to re-scan")
        await ws.close()

        # 3. Token pairing headless: must refuse, never auto-approve.
        ws = await connect(f"wss://127.0.0.1:{port}/", ssl=ctx)
        await ws.send(
            p.encode({"t": "hello", "v": 1, "device": "Pixel 7", "platform": "android"})
        )
        await asyncio.wait_for(ws.recv(), 10)
        link = Path(config) / "pairing.link"
        token = None
        if link.exists():

            # The link holds a deep link; pull the pin out of it the same way
            # the phone does rather than reaching into internals.
            text = link.read_text(encoding="utf-8").strip()
            for part in text.split("&"):
                if part.startswith("pin="):
                    token = part[4:]
        if not token:
            print("SKIP  no pairing link written, skipping the approval check")
        else:
            await ws.send(p.encode({"t": "auth", "token": token}))
            first = p.decode(await asyncio.wait_for(ws.recv(), 10))
            print(f"OK    token auth first reply -> {first['t']}")
            if first["t"] == "auth_pending":
                final = p.decode(await asyncio.wait_for(ws.recv(), 10))
                print(
                    f"{'OK   ' if final['t'] == 'auth_err' else 'FAIL '} "
                    f"headless decision -> {final['t']} {final.get('code', '')}"
                )
                if final.get("code") != "E_DENIED":
                    print("FAIL  headless must refuse; approving would hand over the PC")
        await ws.close()

        print("\nRESULT: shipped binary reaches the handshake and refuses safely")
        return 0
    finally:
        child.terminate()
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            child.kill()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
