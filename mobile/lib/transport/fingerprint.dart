/// Certificate pinning.
///
/// The companion generates its own certificate and shows its SHA-256
/// fingerprint in the QR code. Ordinary TLS verification cannot help here: the
/// certificate is self-signed, so every connection would fail, and turning
/// verification off would let anything on the network impersonate the PC and
/// take control of the machine.
///
/// So verification is not on or off - it is *replaced*. The certificate must
/// match the fingerprint the user actually scanned. That is the whole trust
/// story: the QR code is the credential, and it is only trustworthy because
/// pairing is confirmed out of band, by the user pointing a camera at the
/// screen of the computer they are sitting at.
///
/// The comparison is constant-time. It does not need to be for the *result* -
/// a wrong fingerprint is rejected either way - but it does need to be for the
/// *timing*: a byte-by-byte early-exit comparison leaks how much of a guess was
/// right, and an attacker who can measure that no longer has to guess a
/// 256-bit value blindly.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Whether [der] is the certificate the user actually scanned.
///
/// [der] is the raw certificate bytes, which is what the platform's TLS stack
/// hands to a certificate callback. Hashing the DER rather than the PEM text
/// matters: PEM is a base64 wrapper that can be re-wrapped with different line
/// endings without changing the certificate, so hashing the text would reject
/// a perfectly good one.
bool matchesFingerprintBytes(List<int> der, String expectedFingerprint) {
  final expected = normaliseFingerprint(expectedFingerprint);
  if (expected == null) return false;
  return _constantTimeEquals(sha256Hex(der), expected);
}

/// [matchesFingerprintBytes] for a certificate in PEM form.
///
/// Only for tests and for the rare case where the certificate has to be read
/// back from disk.
bool matchesFingerprint(String certificatePem, String expectedFingerprint) {
  final der = derFromPem(certificatePem);
  if (der == null) return false;
  return matchesFingerprintBytes(der, expectedFingerprint);
}

/// The SHA-256 of [der], lowercase hex.
String sha256Hex(List<int> der) =>
    sha256.convert(der).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The DER bytes of a PEM certificate, or null if it is not one.
List<int>? derFromPem(String pem) {
  const begin = '-----BEGIN CERTIFICATE-----';
  const end = '-----END CERTIFICATE-----';

  final start = pem.indexOf(begin);
  if (start < 0) return null;
  final bodyStart = start + begin.length;
  final bodyEnd = pem.indexOf(end, bodyStart);
  if (bodyEnd < 0) return null;

  final base64 = pem.substring(bodyStart, bodyEnd).replaceAll(RegExp(r'\s'), '');
  try {
    return base64Decode(base64);
  } on FormatException {
    return null;
  }
}

/// Strip separators and lowercase, or null if the result is not 64 hex digits.
///
/// Returning null rather than guessing matters: a mistyped fingerprint has to
/// fail closed. Coercing a short string into something that might match would
/// turn a typo into a subtle weakening of the only thing standing between an
/// attacker and the user's computer.
String? normaliseFingerprint(String raw) {
  final cleaned =
      raw.replaceAll(':', '').replaceAll(' ', '').replaceAll('-', '').trim().toLowerCase();

  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(cleaned)) return null;
  return cleaned;
}

/// Compare two hex strings without leaking how much matched.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}