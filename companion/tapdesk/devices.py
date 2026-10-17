"""Paired devices.

Section 7.5 of `docs/protocol.md`: the PC stores **only the hash** of a device
key. That matters because the companion's data directory is the weakest link in
this product - it is a file on a laptop that anyone with physical access can
read. If the keys were stored in the clear, a stolen disk would let an attacker
impersonate a paired phone and control the computer indefinitely, with no way
for the user to detect it. Storing hashes means a stolen disk yields nothing
usable.

The phone holds the real key, in the Android Keystore.
"""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

#: Device keys are long-lived and currently never expire. `ttl: 0` on the wire
#: means exactly that, and is explicit so the phone does not have to guess.
DEVICE_KEY_BYTES = 32

#: A fresh pairing token is this long; unrelated to the device key.
KEY_PREFIX = "tdk_"


def new_device_key() -> str:
    """A fresh device key, prefixed so it is recognisable in a log."""
    raw = secrets.token_bytes(DEVICE_KEY_BYTES)
    return KEY_PREFIX + secrets.token_urlsafe(DEVICE_KEY_BYTES)[:40]


def new_device_id() -> str:
    """An opaque id for a paired device. Not derived from anything guessable."""
    return "d_" + secrets.token_hex(8)


def hash_key(key: str) -> str:
    """SHA-256 of the key, hex. This is the only form ever written to disk."""
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def key_matches(key: str, stored_hash: str) -> bool:
    """Constant-time comparison, so a wrong key leaks no timing information."""
    if not key or not stored_hash:
        return False
    return secrets.compare_digest(hash_key(key), stored_hash)


@dataclass
class Device:
    """One paired phone.

    `key_hash` is the only secret kept. There is deliberately no field here for
    the raw key: adding one would make it easy to log or serialise the secret by
    accident.
    """

    device_id: str
    name: str
    key_hash: str
    fingerprint: str
    paired_at: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)

    def to_json(self) -> dict[str, Any]:
        return {
            "deviceId": self.device_id,
            "name": self.name,
            "keyHash": self.key_hash,
            "fingerprint": self.fingerprint,
            "pairedAt": self.paired_at,
            "lastSeen": self.last_seen,
        }

    @staticmethod
    def from_json(data: dict[str, Any]) -> "Device | None":
        required = ("deviceId", "name", "keyHash", "fingerprint")
        if any(not isinstance(data.get(k), str) for k in required):
            return None
        return Device(
            device_id=data["deviceId"],
            name=data["name"],
            key_hash=data["keyHash"],
            fingerprint=data["fingerprint"],
            paired_at=float(data.get("pairedAt", time.time())),
            last_seen=float(data.get("lastSeen", time.time())),
        )


class DeviceStore:
    """The paired-device list, persisted as JSON.

    Reads the whole file on every load rather than keeping a handle open: it is
    rewritten atomically on every change, so a crash mid-write cannot leave a
    half-written file that loses every pairing.
    """

    def __init__(self, path: Path) -> None:
        self._path = path
        self._devices: dict[str, Device] = {}
        self._lock = threading.Lock()
        self.load()

    @property
    def devices(self) -> list[Device]:
        with self._lock:
            return sorted(self._devices.values(), key=lambda d: -d.last_seen)

    def __len__(self) -> int:
        return len(self._devices)

    def get(self, device_id: str) -> Device | None:
        with self._lock:
            return self._devices.get(device_id)

    def load(self) -> None:
        if not self._path.exists():
            return
        try:
            raw = json.loads(self._path.read_text("utf-8"))
        except (ValueError, OSError):
            return
        entries = raw.get("devices", []) if isinstance(raw, dict) else []
        with self._lock:
            self._devices = {}
            for entry in entries:
                device = Device.from_json(entry)
                if device is not None:
                    self._devices[device.device_id] = device

    def _save(self) -> None:
        payload = {"version": 1, "devices": [d.to_json() for d in self.devices]}
        self._path.parent.mkdir(parents=True, exist_ok=True)
        # Write to a temporary file and replace, so an interrupted write cannot
        # destroy the pairing list.
        temporary = self._path.with_suffix(".tmp")
        temporary.write_text(json.dumps(payload, indent=2), "utf-8")
        os.replace(temporary, self._path)

    def find_by_key(self, key: str) -> Device | None:
        """The device a presented key belongs to, if any."""
        with self._lock:
            for device in self._devices.values():
                if key_matches(key, device.key_hash):
                    return device
        return None

    def is_revoked(self, key: str) -> bool:
        """Whether this key was presented after revocation.

        Revocation removes the hash, so `find_by_key` simply stops matching.
        This exists to make the intent explicit at the call site.
        """
        return self.find_by_key(key) is None

    def pair(
        self, name: str, fingerprint: str, device_id: str | None = None
    ) -> tuple[Device, str]:
        """Register a newly approved device.

        Returns the device record and the **raw key**, which is handed to the
        phone exactly once and never stored anywhere.
        """
        key = new_device_key()
        device = Device(
            device_id=device_id or new_device_id(),
            name=name[:64],
            key_hash=hash_key(key),
            fingerprint=fingerprint,
        )
        with self._lock:
            self._devices[device.device_id] = device
        self._save()
        return device, key

    def touch(self, device_id: str) -> None:
        """Record that a device connected, for the 'last used' column."""
        with self._lock:
            device = self._devices.get(device_id)
            if device is None:
                return
            device.last_seen = time.time()
        self._save()

    def revoke(self, device_id: str) -> bool:
        """Forget a device. Its key stops working on the very next connection."""
        with self._lock:
            existed = self._devices.pop(device_id, None) is not None
        if existed:
            self._save()
        return existed

    def rename(self, device_id: str, name: str) -> bool:
        with self._lock:
            device = self._devices.get(device_id)
            if device is None:
                return False
            device.name = name[:64]
        self._save()
        return True
