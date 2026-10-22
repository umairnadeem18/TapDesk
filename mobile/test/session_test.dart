/// Tests for the live session, driven against a fake socket.
///
/// The socket is injected, so a whole pairing - hello, prompt, approval, input,
/// revoke - runs here with no network and no certificate. What is left
/// untested is the socket itself, which is the thinnest possible layer around
/// `web_socket_channel`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/state/connection_controller.dart';
import 'package:tapdesk_mobile/transport/session.dart';
import 'package:tapdesk_mobile/transport/socket.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';

/// A socket factory that hands back the socket it was given.
class _FakeFactory implements SocketFactory {
  _FakeFactory(this.socket);

  FakeSocket socket;
  String? askedHost;
  int? askedPort;
  String? askedFingerprint;

  @override
  Future<TapDeskSocket> connect({
    required String host,
    required int port,
    required String fingerprint,
  }) async {
    askedHost = host;
    askedPort = port;
    askedFingerprint = fingerprint;
    return socket;
  }
}

class _RecordingDelegate implements SessionDelegate {
  final List<ConnectionStatus> statuses = [];
  final List<String> errors = [];
  final List<String> savedKeys = [];
  String? key;
  int forgetCount = 0;

  @override
  String? deviceKey() => key;

  @override
  Future<void> saveDeviceKey(String deviceId, String deviceKey) async {
    savedKeys.add(deviceKey);
    key = deviceKey;
  }

  @override
  Future<void> forgetDeviceKey() async {
    forgetCount++;
    key = null;
  }

  @override
  void onStatus(ConnectionInfo info) {
    statuses.add(info.status);
    snapshots.add(info);
  }
  /// The full snapshots, so tests can assert on the reason a status carried.
  final List<ConnectionInfo> snapshots = [];

  @override
  void onError(String message) => errors.add(message);
}

Map<String, Object?> decode(String frame) => jsonDecode(frame) as Map<String, Object?>;

String frame(Map<String, Object?> message) => jsonEncode(message);

void main() {
  late FakeSocket socket;
  late _FakeFactory factory;
  late _RecordingDelegate delegate;
  late TapDeskSession session;

  setUp(() {
    socket = FakeSocket();
    factory = _FakeFactory(socket);
    delegate = _RecordingDelegate();
    session = TapDeskSession(
      factory: factory,
      delegate: delegate,
      deviceName: 'Pixel 7',
      host: '192.168.1.15',
      port: 8765,
      fingerprint: 'a' * 64,
    );
  });

  /// Let the socket's stream deliver what the "PC" just said.
  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> connect({String? token, String? key}) async {
    delegate.key = key;
    await session.connect(token: token);
    await pump();
  }

  Future<void> approve() async {
    socket.emit(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'Teacher-Laptop'}}));
    await pump();
    socket.emit(frame({'t': 'auth_pending', 'device': 'Pixel 7', 'ip': '1.2.3.4'}));
    await pump();
    socket.emit(frame({'t': 'auth_ok', 'deviceId': 'dev-1', 'deviceKey': 'the-key'}));
    await pump();
  }

  group('connecting', () {
    test('pins to the fingerprint it was given', () async {
      await connect(token: 'TOKEN');

      expect(factory.askedFingerprint, 'a' * 64);
      expect(factory.askedHost, '192.168.1.15');
      expect(factory.askedPort, 8765);
    });

    test('sends hello and the token', () async {
      await connect(token: 'TOKEN');

      expect(decode(socket.sent.first)['t'], 'hello');
      expect(decode(socket.sent.last), {'t': 'auth', 'token': 'TOKEN'});
    });

    test('is not ready to send input', () async {
      await connect(token: 'TOKEN');

      expect(session.isReady, isFalse);
      expect(session.send(SlideEvent(SlideAction.next)), isFalse);
    });
  });

  group('pairing', () {
    test('reaches connected and reports the PC name', () async {
      await connect(token: 'TOKEN');
      await approve();

      expect(session.status, ConnectionStatus.connected);
      expect(session.isReady, isTrue);
      expect(delegate.statuses, contains(ConnectionStatus.connected));
    });

    test('stores the device key it was handed', () async {
      await connect(token: 'TOKEN');
      await approve();

      // Persisted before the user is told it worked: if the app dies in
      // between, they would have to scan a QR code again for a pairing that
      // actually succeeded.
      expect(delegate.savedKeys, ['the-key']);
    });

    test('a reconnect sends the saved key, not the token', () async {
      await connect(key: 'SAVED');

      expect(decode(socket.sent.last), {'t': 'auth', 'key': 'SAVED'});
    });

    test('the saved key survives being read again', () async {
      await connect(key: 'SAVED');
      socket.emit(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
      await pump();

      expect(session.status, ConnectionStatus.handshaking);
      expect(delegate.deviceKey(), 'SAVED');
    });
  });

  group('sending input', () {
    setUp(() async {
      await connect(token: 'TOKEN');
      await approve();
      socket.sent.clear();
    });

    test('a slide action reaches the wire', () async {
      expect(session.send(SlideEvent(SlideAction.next)), isTrue);

      expect(socket.sent, hasLength(1));
      expect(decode(socket.sent.single), {
        't': 'slide',
        'a': 'next',
      });
    });

    test('counts what it sent', () async {
      session.send(SlideEvent(SlideAction.next));
      session.send(SlideEvent(SlideAction.prev));

      expect(session.sentCount, 2);
    });

    test('text is sent as text, not as keys', () async {
      // Sending characters rather than key codes is the only reason Urdu and
      // emoji survive the trip.
      session.send(TextEvent('السلام'));

      expect(decode(socket.sent.single), {'t': 'text', 's': 'السلام'});
    });
  });

  group('losing the connection', () {
    test('a hang-up leads to reconnecting, not to connected', () async {
      await connect(token: 'TOKEN');
      await approve();

      socket.hangUp();
      await pump();

      expect(delegate.statuses.last, ConnectionStatus.reconnecting);
    });

    test('input stops the moment it drops', () async {
      await connect(token: 'TOKEN');
      await approve();
      socket.hangUp();
      await pump();

      expect(session.send(SlideEvent(SlideAction.next)), isFalse);
    });

    test('a deliberate disconnect says goodbye first', () async {
      // The PC needs to know to let go of anything held, rather than waiting
      // out its own timeout to notice we left.
      await connect(token: 'TOKEN');
      await approve();
      socket.sent.clear();

      await session.disconnect();

      expect(decode(socket.sent.single), {'t': 'bye'});
    });
  });

  group('messages that arrive while connected', () {
    setUp(() async {
      await connect(token: 'TOKEN');
      await approve();
    });

    test('a revocation forgets the stored key', () async {
      // The key is dead. Keeping it would mean every reconnect tries a
      // credential that can never work.
      socket.emit(frame({'t': 'revoked'}));
      await pump();

      expect(session.status, ConnectionStatus.revoked);
      expect(delegate.forgetCount, 1);
      expect(delegate.deviceKey(), isNull);
    });

    test('the PC asking us to stop shows reconnecting', () async {
      socket.emit(frame({'t': 'disconnect'}));
      await pump();

      expect(session.status, ConnectionStatus.reconnecting);
    });

    test('an unknown frame does not drop the session', () async {
      // The PC may add event types. An old phone should keep working rather
      // than disconnecting the user over something it does not recognise.
      socket.emit(frame({'t': 'something_new', 'payload': 1}));
      await pump();

      expect(session.status, ConnectionStatus.connected);
      expect(session.isReady, isTrue);
    });

    test('malformed input does not drop the session', () async {
      socket.emit('not json at all');
      await pump();

      expect(session.status, ConnectionStatus.connected);
    });
  });

  group('failures reach the user', () {
    test('a denial is reported in words', () async {
      await connect(token: 'TOKEN');
      socket.emit(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
      await pump();
      socket.emit(frame({'t': 'auth_err', 'code': 'E_DENIED'}));
      await pump();

      expect(delegate.errors.single, contains('no'));
      expect(session.status, ConnectionStatus.denied);
    });

    test('an expired code tells the user to scan again', () async {
      await connect(token: 'TOKEN');
      socket.emit(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
      await pump();
      socket.emit(frame({'t': 'auth_err', 'code': 'E_BAD_TOKEN'}));
      await pump();

      expect(delegate.errors.single, contains('Scan'));
    });

    test('nothing is stored when pairing failed', () async {
      await connect(token: 'TOKEN');
      socket.emit(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
      await pump();
      socket.emit(frame({'t': 'auth_err', 'code': 'E_DENIED'}));
      await pump();

      expect(delegate.savedKeys, isEmpty);
    });

    test('a denial is carried on the status snapshot, not only as an event', () async {
      await connect(token: 'TOKEN');
      socket.emit(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
      await pump();
      socket.emit(frame({'t': 'auth_err', 'code': 'E_DENIED'}));
      await pump();

      expect(delegate.snapshots.last.lastError, delegate.errors.single,
          reason: 'the banner reads the snapshot alone; a reason that only '
              'rides as an event is never actually shown to the user');
    });
  });

  group('teardown', () {
    test('disposing does not report a drop afterwards', () async {
      // Otherwise quitting the app would kick off a reconnect attempt against
      // a socket that no longer exists.
      await connect(token: 'TOKEN');
      await approve();

      await session.dispose();
      socket.hangUp();
      await pump();

      expect(session.status, ConnectionStatus.connected);
    });
  });
}