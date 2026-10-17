"""TapDesk companion.

The PC side of TapDesk. Mirrors `docs/protocol.md` v1; that document is the
contract and this package is one of its two implementations.

Module map:

    protocol.py  message encode/parse and the canonical vocabularies
    pairing.py   one-time tokens, the QR payload and its deep link
    tls.py       self-signed certificate generation and fingerprinting
    server.py    the WebSocket server and the handshake
    devices.py   paired-device keys, stored hashed
    input/       OS-level mouse and keyboard simulation
    ui/          the PySide6 window and the tray icon
"""

__version__ = "1.0.0"

PROTOCOL_VERSION = 1
