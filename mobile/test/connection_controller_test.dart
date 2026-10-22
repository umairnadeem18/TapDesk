import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/state/connection_controller.dart';

/// Tests for the parts of the shell that are already real.
///
/// The transport arrives in Phase 4, so these cover the state machine and the
/// backoff — the two pieces of the contract from `docs/protocol.md` section 3.5
/// that are easiest to get subtly wrong and hardest to notice on a phone.
void main() {
  group('BackoffPolicy', () {
    const policy = BackoffPolicy();

    test('follows the 1s, 2s, 4s, 8s sequence from the protocol', () {
      expect(policy.delayFor(0), 1000);
      expect(policy.delayFor(1), 2000);
      expect(policy.delayFor(2), 4000);
      expect(policy.delayFor(3), 8000);
    });

    test('caps at 10s instead of growing without bound', () {
      expect(policy.delayFor(4), 10000);
      expect(policy.delayFor(50), 10000);
    });
  });

  group('ConnectionStatus', () {
    test('only connected may send input', () {
      for (final status in ConnectionStatus.values) {
        expect(
          status.isConnected,
          status == ConnectionStatus.connected,
          reason: '$status should ${status == ConnectionStatus.connected ? '' : 'not '}allow input',
        );
      }
    });

    test('terminal states are not retried automatically', () {
      // Retrying a revoked or denied device would either loop forever or
      // hammer a PC that has already said no.
      expect(ConnectionStatus.revoked.isRetryable, isFalse);
      expect(ConnectionStatus.denied.isRetryable, isFalse);
      expect(ConnectionStatus.failed.isRetryable, isFalse);
      expect(ConnectionStatus.reconnecting.isRetryable, isTrue);
    });

    test('connected shows no banner, everything else does', () {
      expect(ConnectionStatus.connected.bannerText, isNull);
      expect(ConnectionStatus.idle.bannerText, isNull);
      for (final status in ConnectionStatus.values) {
        if (status == ConnectionStatus.connected ||
            status == ConnectionStatus.idle) {
          continue;
        }
        expect(status.bannerText, isNotNull, reason: '$status needs a banner');
      }
    });
  });

  group('ConnectionController', () {
    test('reports connected once the transport says so', () {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      expect(controller.info.status, ConnectionStatus.idle);

      controller.onConnected(pcName: 'Teacher-Laptop');

      expect(controller.info.status, ConnectionStatus.connected);
      expect(controller.info.status.isConnected, isTrue);
      expect(controller.info.pcName, 'Teacher-Laptop');
      expect(controller.info.paired, isTrue);
    });

    test('a successful connection resets the backoff to the first step', () {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      controller
        ..scheduleReconnect()
        ..scheduleReconnect()
        ..scheduleReconnect();
      expect(controller.currentRetryDelayMs, 4000);

      controller.onConnected(pcName: 'Teacher-Laptop');
      controller.scheduleReconnect();

      expect(controller.currentRetryDelayMs, 1000,
          reason: 'backoff must restart after a good connection');
    });

    test('notifies listeners only when the snapshot actually changes', () {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.goTo(ConnectionStatus.connecting);
      controller.goTo(ConnectionStatus.connecting); // duplicate
      controller.goTo(ConnectionStatus.handshaking);

      expect(notifications, 2,
          reason: 'identical state must not rebuild the UI');
    });

    test('a stale error message is cleared when reconnecting', () {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      controller.goTo(ConnectionStatus.failed, error: 'Bad token');
      expect(controller.info.lastError, 'Bad token');

      controller.goTo(ConnectionStatus.connecting);
      expect(controller.info.lastError, isNull,
          reason: 'a stale error next to a spinner reads as a live failure');
    });
  });

  group('failure reasons during the retry loop', () {
    test('the reason survives a reason-less reconnecting snapshot', () {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      controller.update(ConnectionInfo(
        status: ConnectionStatus.reconnecting,
        pcName: 'Teacher-Laptop',
        lastError: 'Check TapDesk is running on the computer',
      ));

      // A second drop arriving mid-loop carries no reason of its own: the
      // transport reports status and reason separately.
      controller.update(ConnectionInfo(
        status: ConnectionStatus.reconnecting,
        pcName: 'Teacher-Laptop',
      ));

      expect(controller.info.lastError, 'Check TapDesk is running on the computer',
          reason: 'the reason must not blink away while the loop continues');
    });

    test('the reason survives being rescheduled', () {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      controller.update(ConnectionInfo(
        status: ConnectionStatus.reconnecting,
        lastError: 'Could not reach the computer',
      ));
      controller.scheduleReconnect();

      expect(controller.info.lastError, 'Could not reach the computer',
          reason: 'scheduleReconnect is set right after the failure; wiping '
              'the message here is what made the banner alternate between '
              'the reason and a bare "Reconnecting" forever');
    });

    test('a fresh attempt starts without the reason', () async {
      final controller = ConnectionController(
        backoff: const BackoffPolicy(stepsMs: [20], maxMs: 20),
      );
      addTearDown(controller.dispose);

      controller.update(ConnectionInfo(
        status: ConnectionStatus.reconnecting,
        lastError: 'Could not reach the computer',
      ));
      controller.scheduleReconnect();
      expect(controller.info.lastError, 'Could not reach the computer');

      // The timer fires, the attempt begins, and the old reason must not sit
      // beside the spinner.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.info.status, ConnectionStatus.connecting);
      expect(controller.info.lastError, isNull);
    });
  });

  group('retryNow', () {
    test('does not interrupt an attempt that is still in flight', () async {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      var attempts = 0;
      controller.onRetry = () async => attempts++;

      for (final status in const [
        ConnectionStatus.connecting,
        ConnectionStatus.handshaking,
        ConnectionStatus.awaitingApproval,
      ]) {
        controller.goTo(status);

        final before = controller.info.status;
        controller.retryNow();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(attempts, 0, reason: '$status owns a live attempt');
        expect(controller.info.status, before,
            reason: 'retrying underneath a dial burns the one-time pairing '
                'token and turns one good scan into a pairing that never '
                'finishes');
      }
    });

    test('does nothing when there is nothing to retry', () async {
      final controller = ConnectionController();
      addTearDown(controller.dispose);

      var attempts = 0;
      controller.onRetry = () async => attempts++;

      controller.goTo(ConnectionStatus.idle);
      controller.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(attempts, 0);
    });
  });
}
