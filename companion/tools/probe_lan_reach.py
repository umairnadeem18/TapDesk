"""Probe the real companion on the real network address, as a phone would.

The Dart cross-implementation test and the earlier shipped-binary probe both
talk to 127.0.0.1, which a phone can never do. This one connects to the
address the QR advertises (the PC's Wi-Fi IP) and therefore exercises every
layer the phone meets: TCP reachability to the real interface, the TLS layer
with the certificate fingerprint the QR claims, and the hello frame.
"""

import asyncio
import base64
import hashlib
import json
import ssl
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tapdesk import protocol as p  # noqa: E402

HOST = "192.168.2.110"
PORT = 8765
CERT = Path.home() / ".tapdesk" / "companion.crt"


def qr_fingerprint() -> str:
    """The fingerprint the QR advertises, decoded from the published link."""
    raw = (Path.home() / ".tapdesk" / "pairing.link").read_text(encoding="utf-8")
    first = [l for l in raw.splitlines() if l.strip()][0]
    encoded = first.split("d=")[1]
    payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    return payload["fp"]


async def main() -> int:
    from websockets.asyncio.client import connect

    advertised = qr_fingerprint()
    pem = CERT.read_bytes()
    actual = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem.decode())).hexdigest()
    print(f"  QR-advertised fingerprint : {advertised[:16]}…")
    print(f"  sha256 of the local cert  : {actual[:16]}…")
    print(f"  {'MATCH' if advertised == actual else 'MISMATCH - the QR and the served cert disagree'}")

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.load_verify_locations(cafile=str(CERT))

    # TLS to the physical IP, exactly as the phone reaches it. A failure here
    # is what the phone experiences, and 127.0.0.1 probes would never show it.
    try:
        async with connect(f"wss://{HOST}:{PORT}/", ssl=ctx, open_timeout=20) as ws:
            print(f"  TLS handshake to {HOST}:{PORT} OK")
            await ws.send(p.encode({"t": "hello", "v": 1, "device": "probe", "platform": "windows"}))
            reply = json.loads(await asyncio.wait_for(ws.recv(), 10))
            print(f"  hello -> {reply['t']}")
            return 0
    except Exception as exc:  # noqa: BLE001
        print(f"  FAILED talking to {HOST}:{PORT}: {type(exc).__name__}: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
