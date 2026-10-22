"""Refusal-path probe: connect with no token and no device key.

Mimics the phone's auto-reconnect against a PC whose device list was wiped
(reinstall) using the QR's own IP, cert and fingerprint. Expects a prompt
auth_err, not a hang. Deliberately does NOT send the pairing token, so the
live QR stays valid for the user's next scan.
"""

import asyncio
import base64
import json
import ssl
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

HOST = "192.168.2.110"
PORT = 8765
CERT = Path.home() / ".tapdesk" / "companion.crt"


def qr_payload() -> dict:
    raw = (Path.home() / ".tapdesk" / "pairing.link").read_text(encoding="utf-8")
    first = [l for l in raw.splitlines() if l.strip()][0]
    encoded = first.split("d=")[1]
    return json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))


async def main() -> int:
    from websockets.asyncio.client import connect

    payload = qr_payload()
    assert HOST in payload["ips"], f"QR advertises {payload['ips']}"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.load_verify_locations(cafile=str(CERT))

    async with connect(f"wss://{HOST}:{PORT}/", ssl=ctx, open_timeout=20) as ws:
        hello = json.dumps({"t": "hello", "v": 1, "device": "probe", "platform": "windows"})
        await ws.send(hello)
        reply = json.loads(await asyncio.wait_for(ws.recv(), 10))
        assert reply["t"] == "hello_ok", reply

        # No token, no device key: a bare auth frame is out of contract. The
        # companion closes with 4001/E_MALFORMED rather than hanging - that is
        # the property under test here (a prompt refusal, never a stall).
        await ws.send(json.dumps({"t": "auth"}))
        try:
            refusal = json.loads(await asyncio.wait_for(ws.recv(), 10))
            print(f"  auth -> {refusal.get('t')}  code={refusal.get('code')}")
            ok = refusal.get("t") == "auth_err"
            print("  REFUSED PROMPTLY" if ok else "  UNEXPECTED REPLY")
            return 0 if ok else 1
        except Exception as exc:  # noqa: BLE001
            closed = getattr(exc, "rcvd", None)
            ok = closed is not None and closed.code == 4001
            code = closed.code if closed else "?"
            print(f"  closed with {code} ({'E_MALFORMED as expected' if ok else exc})")
            print("  REFUSED PROMPTLY" if ok else "  UNEXPECTED CLOSURE")
            return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
