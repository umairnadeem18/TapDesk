"""Tests for pairing: tokens, the QR payload and the certificate fingerprint."""

from __future__ import annotations

import base64
import json
import time
from pathlib import Path

import pytest

from tapdesk import pairing, tls


class TestTokens:
    def test_is_32_bytes_base64url(self) -> None:
        token = pairing.new_token()
        assert len(token) == pairing.TOKEN_LENGTH == 43
        assert pairing.is_valid_token(token)

    def test_no_padding_is_present(self) -> None:
        # 32 bytes base64url is 43 characters with one '=' of padding removed.
        assert "=" not in pairing.new_token()

    def test_tokens_are_unique(self) -> None:
        assert len({pairing.new_token() for _ in range(200)}) == 200

    @pytest.mark.parametrize(
        "bad", ["", "short", "x" * 42, "x" * 44, "has spaces here", "a+b/c" * 5]
    )
    def test_rejects_malformed_tokens(self, bad: str) -> None:
        assert not pairing.is_valid_token(bad)

    def test_a_fresh_token_is_valid(self) -> None:
        assert pairing.PairingToken().valid() == (True, "")

    def test_a_consumed_token_is_rejected(self) -> None:
        token = pairing.PairingToken()
        token.consume()
        ok, code = token.valid()
        assert ok is False
        assert code == "E_TOKEN_USED"

    def test_an_expired_token_is_rejected(self, monkeypatch: pytest.MonkeyPatch) -> None:
        token = pairing.PairingToken()
        # Push its creation into the past rather than sleeping.
        token.created_at = time.monotonic() - (pairing.TOKEN_TTL_SECONDS + 1)
        ok, code = token.valid()
        assert ok is False
        assert code == "E_TOKEN_EXPIRED"

    def test_expiry_is_two_minutes(self) -> None:
        assert pairing.TOKEN_TTL_SECONDS == 120

    def test_matches_compares_correctly(self) -> None:
        token = pairing.PairingToken()
        assert token.matches(token.value)
        assert not token.matches(pairing.new_token())
        assert not token.matches(None)


class TestQRPayload:
    def payload(self, **overrides: object) -> dict:
        """A valid payload dictionary, with fields corrupted as requested.

        Built as a plain dict rather than through QRPayload on purpose: the
        point is to feed the validator something a *malicious or buggy* client
        might send, and the dataclass would reject some of these at
        construction time instead of at validation time.
        """
        payload: dict = {
            "v": 1,
            "name": "Teacher-Laptop",
            "ips": ["192.168.1.15", "192.168.1.22"],
            "port": 8765,
            "token": pairing.new_token(),
            "fp": "a" * 64,
        }
        payload.update(overrides)
        return payload

    def qr(self, payload: dict | None = None) -> pairing.QRPayload:
        """A QRPayload for the same data, so a round trip compares like with like.

        Taking the dict matters: payload() mints a fresh token each call, so
        building both sides separately would compare two different tokens.
        """
        base = payload if payload is not None else self.payload()
        return pairing.QRPayload(
            name=base["name"],
            ips=tuple(base["ips"]),
            port=base["port"],
            token=base["token"],
            fingerprint=base["fp"],
        )

    def test_a_well_formed_payload_validates(self) -> None:
        assert pairing.validate_payload(self.payload()) == (True, "")

    def test_deep_link_round_trips(self) -> None:
        original = self.payload()
        link = self.qr(original).to_deep_link()

        assert link.startswith("tapdesk://pair?d=")
        encoded = link.split("d=", 1)[1]
        assert "=" not in encoded, "base64url must be unpadded"
        padded = encoded + "=" * (-len(encoded) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(padded))
        assert decoded == original

    @pytest.mark.parametrize(
        ("field", "value"),
        [
            ("v", 2),
            ("name", ""),
            ("name", "x" * 33),
            ("ips", []),
            ("ips", ["999.1.1.1"]),
            ("ips", ["not-an-ip"]),
            ("port", 80),
            ("port", "8765"),
            ("token", "short"),
            ("fp", "A" * 64),
            ("fp", "a" * 63),
            ("fp", "a:1" * 21),
        ],
    )
    def test_rejects_bad_fields(self, field: str, value: object) -> None:
        ok, reason = pairing.validate_payload(self.payload(**{field: value}))
        assert ok is False, f"{field}={value!r} should be rejected"
        assert reason

    def test_rejects_an_uppercase_fingerprint_rather_than_normalising(self) -> None:
        # A fingerprint that needs cleaning up is a fingerprint we should not
        # be quietly repairing before pinning a certificate to it.
        ok, _ = pairing.validate_payload(self.payload(fp="A" * 64))
        assert ok is False


class TestIPv4:
    @pytest.mark.parametrize("value", ["192.168.1.15", "10.0.0.1", "0.0.0.0"])
    def test_accepts_valid(self, value: str) -> None:
        assert pairing.is_valid_ipv4(value)

    @pytest.mark.parametrize(
        "value",
        ["256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "", "abc", None, 12345],
    )
    def test_rejects_invalid(self, value: object) -> None:
        assert not pairing.is_valid_ipv4(value)


class TestCertificate:
    def test_fingerprint_is_64_lowercase_hex(self) -> None:
        certificate = tls.generate()
        assert pairing.is_valid_fingerprint(certificate.fingerprint)

    def test_fingerprint_is_the_sha256_of_the_der_bytes(self) -> None:
        # Computed independently here, because getting this wrong silently
        # breaks pairing on every device and nothing else would notice.
        import hashlib

        from cryptography.hazmat.primitives import serialization

        certificate = tls.generate()
        expected = hashlib.sha256(
            certificate.cert.public_bytes(serialization.Encoding.DER)
        ).hexdigest()
        assert certificate.fingerprint == expected

    def test_fingerprint_is_stable_for_one_certificate(self) -> None:
        certificate = tls.generate()
        assert tls.fingerprint_of(certificate.cert) == certificate.fingerprint

    def test_survives_a_save_and_load(self, tmp_path: Path) -> None:
        # Reusing the certificate is what stops the phone having to re-scan a
        # QR code every time the PC is switched on.
        first = tls.ensure(tmp_path)
        second = tls.ensure(tmp_path)
        assert first.fingerprint == second.fingerprint

    def test_generates_one_when_missing(self, tmp_path: Path) -> None:
        assert tls.load(tmp_path) is None
        certificate = tls.ensure(tmp_path)
        assert (tmp_path / "companion.crt").exists()
        assert (tmp_path / "companion.key").exists()
        assert certificate.fingerprint

    def test_the_local_addresses_are_covered_by_the_certificate(
        self,
    ) -> None:
        # A phone connects to an address it read from the QR, and TLS refuses a
        # name that is not in the SAN list. If the address is missing, pairing
        # fails with a certificate error that looks like a bug.
        from cryptography import x509

        addresses = tls.local_ips()
        if not addresses:
            pytest.skip("no non-loopback address on this machine")

        certificate = tls.generate()
        san = certificate.cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        ).value
        covered = {str(ip) for ip in san.get_values_for_type(x509.IPAddress)}
        for address in addresses:
            assert address in covered

    def test_local_ips_excludes_loopback(self) -> None:
        assert all(not ip.startswith("127.") for ip in tls.local_ips())
