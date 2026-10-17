import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';

/// These tests are the app's half of the contract.
///
/// `docs/protocol.md` was written so that two implementations could agree
/// without talking to each other. Asserting on the exact frames here is how we
/// prove this implementation agrees with the document; if someone changes a
/// field name on one side only, these fail instead of the bug surfacing as a
/// silently dropped message on a PC in a lecture hall.
void main() {
  group('event wire format', () {
    test('stick matches the catalogue', () {
      expect(const StickEvent(0.42, -0.15).encode(),
          '{"t":"stick","x":0.42,"y":-0.15}');
    });

    test('click and scroll match the catalogue', () {
      expect(const ClickEvent(MouseButton.left, ClickAction.click).encode(),
          '{"t":"click","b":"left","a":"click"}');
      expect(const ScrollEvent(-3).encode(), '{"t":"scroll","dy":-3}');
    });

    test('key and combo match the catalogue', () {
      expect(
          const KeyEvent(ProtocolKey.right, 'press').encode(),
          '{"t":"key","k":"right","a":"press"}');
      expect(ComboEvent(const ['ctrl', 'c']).encode(),
          '{"t":"combo","keys":["ctrl","c"]}');
    });

    test('text is unicode-safe, so Urdu round-trips intact', () {
      expect(const TextEvent('السلام').encode(),
          '{"t":"text","s":"السلام"}');
    });

    test('slide actions match the catalogue', () {
      expect(const SlideEvent(SlideAction.next).encode(),
          '{"t":"slide","a":"next"}');
    });

    test('stick rejects out-of-range values at construction', () {
      // The dead zone and range rules are in the protocol; catching a bad value
      // here beats sending something the companion will silently drop.
      expect(() => StickEvent(1.4, 0), throwsA(isA<AssertionError>()));
      expect(() => StickEvent(0, -2), throwsA(isA<AssertionError>()));
    });

    test('combo accepts 1 to 4 keys only', () {
      expect(() => ComboEvent(const []), throwsA(isA<AssertionError>()));
      expect(() => ComboEvent(const ['a', 'b', 'c', 'd', 'e']),
          throwsA(isA<AssertionError>()));
      expect(ComboEvent(const ['ctrl', 'shift', 'p']).keys, hasLength(3));
    });

    test('every key id used by the keyboard is in the canonical set', () {
      // If a future screen invents an id, it must exist in ProtocolKey.all or
      // the companion will reject it with E_BAD_FIELD.
      for (final id in [
        ProtocolKey.enter, ProtocolKey.backspace, ProtocolKey.space,
        ProtocolKey.up, ProtocolKey.down, ProtocolKey.left, ProtocolKey.right,
        ProtocolKey.shift, ProtocolKey.ctrl, ProtocolKey.alt, ProtocolKey.win,
        ProtocolKey.tab, ProtocolKey.esc, ProtocolKey.functionKey(5),
        ProtocolKey.minus, ProtocolKey.period, ProtocolKey.slash,
      ]) {
        expect(ProtocolKey.all.contains(id), isTrue, reason: '$id missing');
      }
    });

    test('function keys are f1..f12 and all declared', () {
      expect(ProtocolKey.functionKeys.first, 'f1');
      expect(ProtocolKey.functionKeys.last, 'f12');
      for (final id in ProtocolKey.functionKeys) {
        expect(ProtocolKey.all.contains(id), isTrue, reason: '$id missing');
      }
    });
  });

  group('pairing payload parsing', () {
    String deepLink(Map<String, dynamic> payload) {
      final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)))
          .replaceAll('=', '');
      return 'tapdesk://pair?d=$encoded';
    }

    Map<String, dynamic> valid() => {
          'v': 1,
          'name': 'Teacher-Laptop',
          'ips': ['192.168.1.15', '192.168.1.22'],
          'port': 8765,
          'token': 'k' * 43,
          'fp': 'a' * 64,
        };

    test('accepts a well-formed deep link', () {
      final payload = PairingPayload.tryParseDeepLink(deepLink(valid()));
      expect(payload, isNotNull);
      expect(payload!.name, 'Teacher-Laptop');
      expect(payload.port, 8765);
      expect(payload.ips, ['192.168.1.15', '192.168.1.22']);
      expect(payload.fingerprint.length, 64);
    });

    test('rejects the wrong scheme', () {
      expect(
          PairingPayload.tryParseDeepLink('https://example.com?d=${base64Url.encode(utf8.encode(jsonEncode(valid())))}'),
          isNull);
    });

    test('rejects a payload with no data parameter', () {
      expect(PairingPayload.tryParseDeepLink('tapdesk://pair'), isNull);
      expect(PairingPayload.tryParseDeepLink('tapdesk://pair?x=1'), isNull);
    });

    test('rejects an unsupported protocol version rather than guessing', () {
      final bad = valid()..['v'] = 2;
      expect(PairingPayload.tryParseDeepLink(deepLink(bad)), isNull);
    });

    test('rejects an uppercase fingerprint instead of normalising it', () {
      // A fingerprint that needs cleaning up is a fingerprint we should not
      // trust to pin a certificate.
      final bad = valid()..['fp'] = 'A' * 64;
      expect(PairingPayload.tryParseDeepLink(deepLink(bad)), isNull);
    });

    test('rejects a fingerprint of the wrong length', () {
      final bad = valid()..['fp'] = 'a' * 63;
      expect(PairingPayload.tryParseDeepLink(deepLink(bad)), isNull);
    });

    test('rejects a token that is not 32 base64url bytes', () {
      final bad = valid()..['token'] = 'short';
      expect(PairingPayload.tryParseDeepLink(deepLink(bad)), isNull);
    });

    test('rejects an out-of-range port', () {
      final bad = valid()..['port'] = 80;
      expect(PairingPayload.tryParseDeepLink(deepLink(bad)), isNull);
    });

    test('rejects a malformed IP', () {
      final bad = valid()..['ips'] = ['192.168.1.999'];
      expect(PairingPayload.tryParseDeepLink(deepLink(bad)), isNull);
    });

    test('rejects garbage that is not JSON', () {
      expect(PairingPayload.tryParseBase64Payload(
          base64Url.encode(utf8.encode('not json at all'))), isNull);
    });

    test('manual entry reaches the same shape as a scan', () {
      final payload = PairingPayload.tryParseManual(
        ip: '192.168.1.15',
        port: 8765,
        pin: '483920',
        fingerprint: 'a' * 64,
      );
      expect(payload, isNotNull);
      expect(payload!.ips, ['192.168.1.15']);

      final manual = payload.toManualJson('483920');
      expect(manual['ip'], '192.168.1.15');
      expect(manual['port'], 8765);
    });

    test('manual entry rejects a PIN that is not six digits', () {
      expect(
        PairingPayload.tryParseManual(
            ip: '192.168.1.15',
            port: 8765,
            pin: '12345',
            fingerprint: 'a' * 64),
        isNull,
      );
    });
  });
}
