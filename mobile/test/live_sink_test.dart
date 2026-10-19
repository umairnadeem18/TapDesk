/// Tests for the app-level wiring: key storage and the live sink.
///
/// These are the layer between "the user scanned a code" and "there is a
/// socket". It owns the credential, so it is worth testing even though most of
/// it is plumbing.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/state/connection_controller.dart';
import 'package:tapdesk_mobile/transport/key_store.dart';
import 'package:tapdesk_mobile/transport/live_sink.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/transport/session.dart';
import 'package:tapdesk_mobile/transport/socket.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';

class _FakeFactory implements SocketFactory {
  FakeSocket socket = FakeSocket();
  final List<String> fingerprints = [];

  @override
  Future<TapDeskSocket> connect({
    required String host,
    required int port,
    required String fingerprint,
  }) async {
    fingerprints.add(fingerprint);
    return socket;
  }
}

class _RecordingDelegate implements SessionDelegate {
  final List<ConnectionStatus> statuses = [];
  final List<String> errors = [];

  @override
  String? deviceKey() => null;

  @override
  Future<void> saveDeviceKey(String deviceId, String deviceKey) async {}

  @override
  Future<void> forgetDeviceKey() async {}

  @override
  void onStatus(ConnectionInfo info) => statuses.add(info.status);

  @override
  void onError(String message) => errors.add(message);
}

Map<String, Object?> decode(String frame) => jsonDecode(frame) as Map<String, Object?>;

PairingPayload payload({String? fingerprint, String host = '192.168.1.15'}) =>
    PairingPayload(
      version: 1,
      name: 'Teacher-Laptop',
      ips: [host],
      port: 8765,
      token: 'THE-TOKEN',
      fingerprint: fingerprint ?? 'a' * 64,
    );

void main() {
  late MemoryKeyStore keyStore;
  late _FakeFactory factory;
  late _RecordingDelegate delegate;
  late LiveEventSink sink;

  setUp(() {
    keyStore = MemoryKeyStore();
    factory = _FakeFactory();
    delegate = _RecordingDelegate();
    sink = LiveEventSink(
      delegate: delegate,
      keyStore: keyStore,
      factory: factory,
    );
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> approve(FakeSocket socket) async {
    socket.emit(jsonEncode({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'Teacher-Laptop'}}));
    await pump();
    socket.emit(jsonEncode({'t': 'auth_pending', 'device': 'TapDesk', 'ip': '1.2.3.4'}));
    await pump();
    socket.emit(jsonEncode({
      't': 'auth_ok',
      'deviceId': 'dev-1',
      'deviceKey': 'the-key',
    }));
    await pump();
  }

  group('before connecting', () {
    test('the sink exists but is not ready', () {
      // The tabs must stay on screen and inert rather than disappearing, which
      // is why the sink is always present.
      expect(sink.isReady, isFalse);
      expect(sink.send(SlideEvent(SlideAction.next)), isFalse);
    });

    test('nothing was pinned yet', () {
      expect(factory.fingerprints, isEmpty);
    });
  });

  group('a first pairing', () {
    test('sends the token from the scanned code', () async {
      await sink.connectTo(payload(), token: payload().token);

      expect(decode(factory.socket.sent.first)['t'], 'hello');
      expect(decode(factory.socket.sent.last), {'t': 'auth', 'token': 'THE-TOKEN'});
    });

    test('pins to the scanned fingerprint', () async {
      await sink.connectTo(payload());

      expect(factory.fingerprints, ['a' * 64]);
    });

    test('stores the device key against the fingerprint', () async {
      // Keyed by certificate, not by IP: the same computer gets a new DHCP
      // lease, and a different one can be handed the old address. Keying by
      // address would let pairing be inherited by whatever turned up there.
      await sink.connectTo(payload());
      await approve(factory.socket);

      expect(await keyStore.read('a' * 64), 'the-key');
    });

    test('becomes ready once approved', () async {
      await sink.connectTo(payload());
      await approve(factory.socket);

      expect(sink.isReady, isTrue);
      expect(sink.send(SlideEvent(SlideAction.next)), isTrue);
    });

    test('the token is never written to storage', () async {
      // It is single-use; persisting it would put a credential on disk for
      // nothing, since the device key takes over immediately afterwards.
      await sink.connectTo(payload(), token: 'THE-TOKEN');
      await approve(factory.socket);

      expect(await keyStore.read('a' * 64), isNot('THE-TOKEN'));
    });
  });

  group('reconnecting', () {
    test('uses the saved key rather than the stale token', () async {
      // A restarted app has a key on disk but no token: the one in the QR
      // was spent at pairing. If the key is not read, the phone re-pairs with
      // a dead code and the user is told to scan again for no reason.
      await keyStore.write('a' * 64, 'saved-key');

      await sink.connectTo(payload());
      await approve(factory.socket);

      final authFrames =
          factory.socket.sent.map(decode).where((m) => m['t'] == 'auth').toList();
      expect(authFrames.single, {'t': 'auth', 'key': 'saved-key'});
    });

    test('two different PCs keep separate keys', () async {
      // Revoking one computer must not unpair the other, and pairing a second
      // must not clobber the first.
      await sink.connectTo(payload(fingerprint: 'b' * 64));
      await approve(factory.socket);

      expect(await keyStore.read('b' * 64), 'the-key');
      expect(await keyStore.read('a' * 64), isNull);
    });
  });

  group('revocation', () {
    test('forgets the key so it is never reused', () async {
      await keyStore.write('a' * 64, 'saved-key');
      await sink.connectTo(payload());
      await approve(factory.socket);
      expect(await keyStore.read('a' * 64), 'the-key');

      factory.socket.emit(jsonEncode({'t': 'revoked'}));
      await pump();
      await pump();

      // The key has to go: it will never authenticate again, and retrying
      // with it would just fail forever.
      expect(await keyStore.read('a' * 64), isNull);
    });
  });

  group('failures', () {
    test('a mismatch is named, not called a generic failure', () {
      // "Could not connect" would leave the user retrying against a server
      // that is never going to be the computer they paired with.
      final message = describeConnectFailure(
        const HandshakeException(HandshakeFailure.fingerprintMismatch),
      );

      expect(message, contains('not the computer you paired with'));
    });

    test('a timeout suggests trying again', () {
      final message = describeConnectFailure(
        const HandshakeException(HandshakeFailure.timedOut),
      );

      expect(message, contains('did not answer'));
    });

    test('a misread code asks for another scan', () {
      final message = describeConnectFailure(
        ArgumentError.value('nope', 'fingerprint', 'not a SHA-256 fingerprint'),
      );

      expect(message, contains('Scan it again'));
    });

    test('anything else names the companion before the network', () {
      // The state this was wrong about: the phone and the PC were on the same
      // Wi-Fi, and the message told the user to check that. What was actually
      // true is that the companion was not running - the state the app is in
      // immediately after a reinstall, because the installer only offers to
      // start it.
      //
      // Both causes fit in one message because a refused TCP connection looks
      // identical either way. The order is the part being asserted: the thing
      // a user cannot rule out in a second comes first.
      final message = describeConnectFailure(StateError('boom'));

      expect(message, contains('TapDesk is running'));
      expect(message, contains('same Wi-Fi'));
      expect(
        message.indexOf('TapDesk is running'),
        lessThan(message.indexOf('same Wi-Fi')),
        reason: 'the most likely cause must be the first one named',
      );
    });
  });

  group('the key store', () {
    test('namespaces by PC', () async {
      await keyStore.write('pc-1', 'k1');
      await keyStore.write('pc-2', 'k2');

      expect(await keyStore.read('pc-1'), 'k1');
      expect(await keyStore.read('pc-2'), 'k2');
    });

    test('forgetting one leaves the others', () async {
      await keyStore.write('pc-1', 'k1');
      await keyStore.write('pc-2', 'k2');

      await keyStore.forget('pc-1');

      expect(await keyStore.read('pc-1'), isNull);
      expect(await keyStore.read('pc-2'), 'k2');
    });

    test('reading an unknown PC is not an error', () async {
      expect(await keyStore.read('never-paired'), isNull);
    });
  });
}