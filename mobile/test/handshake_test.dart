/// Tests for the pairing handshake.
///
/// The handshake is where the app decides whether it is talking to the
/// computer the user paired with, and whether it is allowed to send anything.
/// It is tested as a pure state machine - no socket, no network - so every
/// branch, including the ones a real PC almost never produces, is reachable.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/state/connection_controller.dart';
import 'package:tapdesk_mobile/transport/handshake.dart';

Map<String, Object?> decode(String frame) =>
    jsonDecode(frame) as Map<String, Object?>;

String frame(Map<String, Object?> message) => jsonEncode(message);

void main() {
  late HandshakeMachine machine;

  setUp(() => machine = HandshakeMachine());

  /// Walk the machine to `connected`, which is where most of the interest is.
  void reachConnected({String device = 'Pixel 7'}) {
    machine
      ..startFrames(deviceName: device, token: 'TOKEN')
      ..handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'Teacher-Laptop'}}));
    machine.handle(frame({'t': 'auth_pending', 'device': device, 'ip': '1.2.3.4'}));
    machine.handle(frame({
      't': 'auth_ok',
      'deviceId': 'dev-1',
      'deviceKey': 'the-key',
    }));
  }

  group('start', () {
    test('sends hello first, then the token', () {
      final frames = machine.startFrames(deviceName: 'Pixel 7', token: 'TOKEN');

      expect(decode(frames.first), {
        't': 'hello',
        'v': 1,
        'device': 'Pixel 7',
        'platform': 'android',
      });
      expect(decode(frames.last), {'t': 'auth', 'token': 'TOKEN'});
    });

    test('prefers the saved key over the token', () {
      // Sending the token when we already have a key would burn a single-use
      // code the user may need for a second phone, and would re-prompt them on
      // a device they have already trusted.
      final frames = machine.startFrames(
        deviceName: 'Pixel 7',
        token: 'TOKEN',
        deviceKey: 'SAVED',
      );

      expect(decode(frames.last), {'t': 'auth', 'key': 'SAVED'});
    });

    test('refuses to start with nothing to authenticate with', () {
      // An unauthenticated socket that looked paired would be far worse than
      // a loud failure here.
      expect(
        () => machine.startFrames(deviceName: 'Pixel 7'),
        throwsStateError,
      );
    });

    test('moves to connecting', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      expect(machine.status, ConnectionStatus.connecting);
    });
  });

  group('the happy path', () {
    test('records the PC name from hello_ok', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      final outcome = machine.handle(
        frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'Teacher-Laptop'}}),
      ) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.handshaking);
      expect(outcome.pcName, 'Teacher-Laptop');
    });

    test('waits for the human on auth_pending', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      machine.handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));

      final outcome =
          machine.handle(frame({'t': 'auth_pending', 'device': 'Pixel 7'})) as AdvanceTo;

      // Awaiting approval is still *not* connected: input must not flow while
      // a human is being asked whether to allow it.
      expect(outcome.status, ConnectionStatus.awaitingApproval);
      expect(machine.status, isNot(ConnectionStatus.connected));
    });

    test('connects and hands over the device key exactly once', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      machine.handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
      machine.handle(frame({'t': 'auth_pending', 'device': 'Pixel 7'}));

      final outcome = machine.handle(
        frame({'t': 'auth_ok', 'deviceId': 'dev-1', 'deviceKey': 'the-key'}),
      ) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.connected);
      expect(outcome.deviceId, 'dev-1');
      expect(outcome.deviceKey, 'the-key');
    });

    test('a PC with no name is rejected rather than trusted', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      final outcome =
          machine.handle(frame({'t': 'hello_ok', 'v': 1})) as AdvanceTo;

      // A PC that cannot say what it is called is not a PC we can show the
      // user before they connect to it.
      expect(outcome.status, ConnectionStatus.failed);
    });
  });

  group('refusals', () {
    void reachPending() {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      machine.handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'PC'}}));
    }

    test('a denial is its own state, not a generic failure', () {
      reachPending();
      final outcome =
          machine.handle(frame({'t': 'auth_err', 'code': 'E_DENIED'})) as AdvanceTo;

      // Distinct because the message is different: the user was told no, which
      // is not the same as something going wrong.
      expect(outcome.status, ConnectionStatus.denied);
      expect(outcome.error, contains('no'));
    });

    test('an expired code fails closed and says to rescan', () {
      reachPending();
      final outcome =
          machine.handle(frame({'t': 'auth_err', 'code': 'E_BAD_TOKEN'})) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.failed);
      expect(outcome.error, contains('Scan'));
    });

    test('a revoked device is told to forget its key', () {
      reachPending();
      final outcome =
          machine.handle(frame({'t': 'auth_err', 'code': 'E_REVOKED'})) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.revoked);
    });

    test('an unknown error is still terminal', () {
      reachPending();
      final outcome = machine.handle(
        frame({'t': 'auth_err', 'code': 'E_SOMETHING_NEW'}),
      ) as AdvanceTo;

      // Terminal is the safe default: retrying an unexplained refusal in a
      // loop is how you get a phone that hammers the PC forever.
      expect(outcome.status, ConnectionStatus.failed);
    });

    test('nonsense on the wire fails rather than being tolerated', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      final outcome = machine.handle('this is not json') as AdvanceTo;

      expect(outcome.status, ConnectionStatus.failed);
    });

    test('a JSON array is not a message', () {
      machine.startFrames(deviceName: 'Pixel 7', token: 'T');
      expect(machine.handle('[1,2,3]'), isA<Ignore>());
    });
  });

  group('out-of-order and stray frames', () {
    test('hello_ok before connecting is ignored', () {
      // Otherwise a PC could talk a phone it never paired with into a state.
      final outcome =
          machine.handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'X'}}));
      expect(outcome, isA<Ignore>());
    });

    test('auth_ok on a token pairing that skipped the prompt is ignored', () {
      // This is the one that matters. A first pairing is holding a single-use
      // token, and the PC asking its user is the entire protection. An auth_ok
      // that skipped that is exactly what an impostor would send.
      machine.startFrames(deviceName: 'Pixel 7', token: 'TOKEN');
      machine.handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'X'}}));

      final outcome = machine.handle(
        frame({'t': 'auth_ok', 'deviceId': 'd', 'deviceKey': 'k'}),
      );

      expect(outcome, isA<Ignore>());
      expect(machine.status, isNot(ConnectionStatus.connected));
    });

    test('a reconnect with a saved key does not need the prompt', () {
      // The companion deliberately skips the prompt for an already-trusted
      // device - re-asking every reconnect would train the user to click
      // through it. The key is the proof instead.
      machine.startFrames(deviceName: 'Pixel 7', deviceKey: 'SAVED');
      machine.handle(frame({'t': 'hello_ok', 'v': 1, 'pc': {'name': 'X'}}));

      final outcome = machine.handle(
        frame({'t': 'auth_ok', 'deviceId': 'dev-1'}),
      ) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.connected);
      expect(outcome.deviceId, 'dev-1');
      // No new key on a reconnect; the one already held stays valid.
      expect(outcome.deviceKey, isNull);
    });

    test('an unknown message type while connected is ignored', () {
      // The PC may add event types; an old phone should keep working rather
      // than dropping the user's session over something it does not know.
      reachConnected();
      expect(machine.handleConnected(frame({'t': 'from_the_future'})), isA<Ignore>());
      expect(machine.status, ConnectionStatus.connected);
    });
  });

  group('while connected', () {
    test('being revoked makes the session forget its key', () {
      reachConnected();
      final outcome = machine.handleConnected(frame({'t': 'revoked'})) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.revoked);
    });

    test('being denied mid-session is reported', () {
      reachConnected();
      final outcome = machine.handleConnected(frame({'t': 'denied'})) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.denied);
    });

    test('the PC can ask us to disconnect', () {
      reachConnected();
      final outcome =
          machine.handleConnected(frame({'t': 'disconnect'})) as AdvanceTo;

      expect(outcome.status, ConnectionStatus.reconnecting);
    });

    test('goodbye is sent before hanging up', () {
      reachConnected();
      // The PC needs to know to let go of anything held, rather than waiting
      // out its own timeout to notice we left.
      expect(decode(machine.goodbyeFrames().single), {'t': 'bye'});
    });
  });

  group('terminal states do not retry', () {
    test('denied is not retryable', () {
      // Retrying would re-prompt the user forever, which is how people learn
      // to click through prompts without reading them.
      expect(ConnectionStatus.denied.isRetryable, isFalse);
      expect(ConnectionStatus.revoked.isRetryable, isFalse);
      expect(ConnectionStatus.failed.isRetryable, isFalse);
    });

    test('a dropped connection is retryable', () {
      expect(ConnectionStatus.reconnecting.isRetryable, isTrue);
      expect(ConnectionStatus.connecting.isRetryable, isTrue);
    });
  });
}