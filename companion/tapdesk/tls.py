"""Self-signed TLS for the local WebSocket.

Section 1 and 7 of `docs/protocol.md`.

The certificate is self-signed because there is no server authority on a home
LAN - and nobody is going to get one. Trust comes from the phone pinning the
fingerprint it read out of the QR code, not from a chain of trust. That is the
entire security model, so the two things this module must get right are:

  * the fingerprint is the SHA-256 of the DER bytes, lowercase hex, no
    separators - the same string on both sides or nothing connects
  * the certificate is generated once and reused, so the phone keeps trusting
    it across restarts instead of re-pairing every time the PC is switched on
"""

from __future__ import annotations

import datetime as dt
import hashlib
import ipaddress
import socket
from dataclasses import dataclass
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.x509.oid import NameOID

#: Long enough that nobody has to re-pair for a few years. There is no
#: revocation path for a self-signed certificate, so expiry is the only lever.
VALIDITY_DAYS = 3650


@dataclass(frozen=True)
class Certificate:
    """A generated certificate and the fingerprint derived from it."""

    cert: x509.Certificate
    key: object
    fingerprint: str


def fingerprint_of(cert: x509.Certificate) -> str:
    """SHA-256 of the DER encoding, lowercase hex, no separators.

    This exact string is what the QR carries and what the phone compares. Any
    change to this function silently breaks pairing on every device.
    """
    return hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest()


def local_ips() -> list[str]:
    """Non-loopback IPv4 addresses of this machine.

    Order matters: the phone tries them in sequence, so the address most likely
    to be the Wi-Fi one should come first. Resolving the hostname first
    generally returns the LAN address before the virtual adapters, which is why
    it is tried before the socket trick.
    """
    found: list[str] = []

    def add(candidate: str) -> None:
        if candidate not in found and not candidate.startswith("127."):
            found.append(candidate)

    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            add(info[4][0])
    except OSError:
        pass

    # A UDP "connect" does not send anything; it just asks the OS which
    # interface it would use to reach the outside world. That is the Wi-Fi
    # address a phone on the same network would be able to reach.
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        add(probe.getsockname()[0])
    except OSError:
        pass
    finally:
        probe.close()

    return found


def hostname() -> str:
    """A friendly PC name for the window and the QR payload."""
    name = socket.gethostname().split(".")[0].strip()
    return name or "TapDesk PC"


def generate(
    common_name: str | None = None,
    ips: list[str] | None = None,
    days: int = VALIDITY_DAYS,
) -> Certificate:
    """Create a self-signed certificate covering this machine's addresses."""
    from cryptography.hazmat.primitives.asymmetric import ec

    name = common_name or hostname()
    addresses = ips if ips is not None else local_ips()

    key = ec.generate_private_key(ec.SECP256R1())

    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, name),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "TapDesk"),
        ]
    )

    # A phone connects to an IP it read from the QR, so every local address has
    # to be in the SAN list or TLS will refuse the name. The hostname goes in
    # too so a future mDNS-based discovery path keeps working.
    alternatives: list[x509.GeneralName] = [
        x509.DNSName(name),
        x509.DNSName("localhost"),
    ]
    for raw in addresses:
        try:
            alternatives.append(
                x509.IPAddress(ipaddress.ip_address(raw))
            )
        except ValueError:
            continue

    now = dt.datetime.now(dt.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - dt.timedelta(minutes=5))
        .not_valid_after(now + dt.timedelta(days=days))
        .add_extension(x509.SubjectAlternativeName(alternatives), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )

    return Certificate(cert=cert, key=key, fingerprint=fingerprint_of(cert))


def save(certificate: Certificate, directory: Path) -> tuple[Path, Path]:
    """Write the key and certificate to disk, owner-readable only."""
    directory.mkdir(parents=True, exist_ok=True)
    cert_path = directory / "companion.crt"
    key_path = directory / "companion.key"

    cert_path.write_bytes(
        certificate.cert.public_bytes(serialization.Encoding.PEM)
    )
    key_path.write_bytes(
        certificate.key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    # The key is the trust anchor for this machine's whole pairing model. It
    # does not need to be encrypted - it protects nothing on its own - but it
    # should not be world-readable.
    key_path.chmod(0o600)
    return cert_path, key_path


def load(directory: Path) -> Certificate | None:
    """Read a previously saved certificate, or None if there is not one yet."""
    cert_path = directory / "companion.crt"
    key_path = directory / "companion.key"
    if not cert_path.exists() or not key_path.exists():
        return None
    try:
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        key = serialization.load_pem_private_key(key_path.read_bytes(), None)
    except (ValueError, TypeError):
        return None
    return Certificate(cert=cert, key=key, fingerprint=fingerprint_of(cert))


def ensure(directory: Path) -> Certificate:
    """Load the stored certificate, or generate one on first run.

    Reusing the certificate is the point: a new fingerprint on every launch
    would force the phone to re-scan a QR code every time the PC was switched
    on, which would make the product unusable.
    """
    existing = load(directory)
    if existing is not None:
        return existing
    certificate = generate()
    save(certificate, directory)
    return certificate
