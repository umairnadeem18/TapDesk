/// Tests for certificate pinning.
///
/// Pinning is the only thing standing between an attacker on the same Wi-Fi
/// and the user's computer, so these tests care as much about *failing* as
/// about succeeding.
///
/// The certificate in `fixtures/companion.crt` is a real self-signed one, and
/// `expectedFingerprint` is its actual SHA-256. Using a real certificate
/// matters: hashing something that is not a certificate would pass a test that
/// says nothing about the real path.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/transport/fingerprint.dart';

/// SHA-256 of the DER of fixtures/companion.crt.
const expectedFingerprint =
    '6fe52a4836b2ec7ec9e61f034c9f6a15bb4f0811e2ad182bc20de75ee70ff746';

void main() {
  late String pem;
  late List<int> der;

  setUpAll(() {
    pem = File('test/fixtures/companion.crt').readAsStringSync();
    der = derFromPem(pem)!;
  });

  group('hashing', () {
    test('a PEM certificate becomes bytes', () {
      expect(der, isNotEmpty);
    });

    test('the real certificate hashes to the fingerprint the QR shows', () {
      // If this ever drifts from the constant above, one of them is wrong and
      // every user would be told to re-pair. It is checked rather than
      // computed-and-assumed.
      expect(sha256Hex(der), expectedFingerprint);
    });

    test('the fingerprint is 64 hex characters', () {
      expect(sha256Hex(der), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('re-wrapping the PEM does not change the fingerprint', () {
      // This is why the DER is hashed rather than the text. PEM is a base64
      // wrapper; a server or proxy that re-wraps it with different line
      // endings has not changed the certificate at all, and hashing the text
      // would reject a perfectly good one.
      final body = base64.encode(der);
      final rewrapped = '-----BEGIN CERTIFICATE-----\n'
          '${body.substring(0, 32)}\n'
          '${body.substring(32)}\n'
          '-----END CERTIFICATE-----\n';
      expect(sha256Hex(derFromPem(rewrapped)!), expectedFingerprint);
    });

    test('something that is not a certificate yields no bytes', () {
      expect(derFromPem('hello'), isNull);
      expect(derFromPem('-----BEGIN CERTIFICATE-----\nnot base64!!\n-----END CERTIFICATE-----'), isNull);
      expect(derFromPem('-----BEGIN CERTIFICATE-----\nAAAA\n'), isNull);
    });
  });

  group('matching', () {
    test('the right certificate matches', () {
      expect(matchesFingerprintBytes(der, expectedFingerprint), isTrue);
    });

    test('a different certificate does not', () {
      expect(matchesFingerprintBytes(der, sha256Hex([1, 2, 3])), isFalse);
    });

    test('one flipped character does not match', () {
      // The near-miss case. A comparison that accepted "almost right" would
      // make the whole scheme decorative.
      final flipped = expectedFingerprint[0] == 'a'
          ? 'b${expectedFingerprint.substring(1)}'
          : 'a${expectedFingerprint.substring(1)}';
      expect(matchesFingerprintBytes(der, flipped), isFalse);
    });

    test('a truncated fingerprint does not match', () {
      expect(
        matchesFingerprintBytes(der, expectedFingerprint.substring(0, 32)),
        isFalse,
      );
    });

    test('an empty fingerprint does not match', () {
      expect(matchesFingerprintBytes(der, ''), isFalse);
    });

    test('an expired certificate still pins', () {
      // Fixtures/companion.crt expired in 2018. Pinning deliberately replaces
      // expiry checking: the fingerprint is the trust anchor, and the
      // companion mints its own certificate per installation, so there is no
      // authority whose expiry could be consulted. Asserted so nobody later
      // reads it as an oversight.
      expect(matchesFingerprintBytes(der, expectedFingerprint), isTrue);
    });
  });

  group('normalising', () {
    test('uppercase is accepted', () {
      expect(
        normaliseFingerprint(expectedFingerprint.toUpperCase()),
        expectedFingerprint,
      );
    });

    test('colons are accepted', () {
      // Users retype this by hand, and every keyboard and QR reader offers
      // different formatting, so the common ones all have to work.
      final colon = expectedFingerprint
          .replaceAllMapped(RegExp(r'(..)(?=.)'), (m) => '${m[1]}:')
          .replaceAll(RegExp(r':$'), '');
      expect(normaliseFingerprint(colon), expectedFingerprint);
    });

    test('spaces are accepted', () {
      final spaced =
          expectedFingerprint.replaceAllMapped(RegExp(r'(.{8})(?=.)', multiLine: false), (m) => '${m[1]} ');
      expect(normaliseFingerprint(spaced), expectedFingerprint);
    });

    test('dashes are accepted', () {
      final dashed =
          expectedFingerprint.replaceAllMapped(RegExp(r'(.{8})(?=.)'), (m) => '${m[1]}-');
      expect(normaliseFingerprint(dashed), expectedFingerprint);
    });

    test('non-hex is rejected rather than coerced', () {
      // Failing closed is the point. Coercing a short or malformed string into
      // something that might match would be a silent weakening of the only
      // check there is.
      expect(normaliseFingerprint('z' * 64), isNull);
      expect(normaliseFingerprint('abc'), isNull);
      expect(normaliseFingerprint(''), isNull);
      expect(normaliseFingerprint('${expectedFingerprint}0'), isNull);
      expect(normaliseFingerprint('0$expectedFingerprint'), isNull);
    });
  });
}