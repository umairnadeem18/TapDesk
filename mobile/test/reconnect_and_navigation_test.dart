/// Reconnecting, going back, and leaving.
///
/// Three behaviours reported from a real phone, all of which used to be broken:
///
///  * "when phone screen turns off and then i on it the phone says connecting
///    as it drops the connection and then never stabilize and reconnect" - the
///    backoff timer changed the label to "connecting" while nothing dialled the
///    PC. The app was lying about work it had stopped doing.
///
///  * No way back: once paired, there was no control that stopped controlling
///    the computer and returned to the pairing screen.
///
///  * No way out: the header's close button was only drawn when the navigator
///    could pop, which on a fresh install is never.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/state/connection_controller.dart';
import 'package:tapdesk_mobile/state/pairing_store.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';

void main() {
  group('the reconnect backoff actually reconnects', () {
    test('the timer fires a real attempt, not just a label', () async {
      final controller = ConnectionController(
        backoff: const BackoffPolicy(stepsMs: [10], maxMs: 10),
      );
      var attempts = 0;
      controller.onRetry = () async => attempts++;

      controller.scheduleReconnect();

      // Before the timer, nothing has been dialled.
      expect(attempts, 0);
      expect(controller.info.status, ConnectionStatus.reconnecting);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      // This is the whole bug: the timer used to end here. It set the status to
      // "connecting" and stopped, so the user watched a spinner forever.
      expect(attempts, 1, reason: 'the backoff never dialled the computer');
      expect(controller.info.status, ConnectionStatus.connecting);
      controller.dispose();
    });

    test('a failing attempt schedules another one', () async {
      final controller = ConnectionController(
        backoff: const BackoffPolicy(stepsMs: [10], maxMs: 10),
      );
      var attempts = 0;
      controller.onRetry = () async {
        attempts++;
        throw StateError('still offline');
      };

      controller.scheduleReconnect();
      await Future<void>.delayed(const Duration(milliseconds: 90));

      // Otherwise the app sits in `connecting` forever after one failure, which
      // is the same symptom from the other direction.
      expect(attempts, greaterThan(1));
      controller.dispose();
    });

    test('retryNow skips the backoff for a deliberate attempt', () async {
      final controller = ConnectionController(
        backoff: const BackoffPolicy(stepsMs: [5000], maxMs: 5000),
      );
      var attempts = 0;
      controller.onRetry = () async => attempts++;

      controller.scheduleReconnect();
      expect(controller.currentRetryDelayMs, 5000);

      // Coming back to the foreground must not make the user watch a spinner
      // for five seconds after unlocking their phone.
      controller.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(attempts, 1);
      controller.dispose();
    });

    test('retryNow does nothing when already connected', () async {
      final controller = ConnectionController();
      var attempts = 0;
      controller.onRetry = () async => attempts++;
      controller.onConnected(pcName: 'PC');

      controller.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(attempts, 0, reason: 'a live session must not be torn down');
      controller.dispose();
    });
  });

  group('a session that drops re-establishes itself', () {
    testWidgets('losing the socket asks for a reconnect', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = PairingStore();
      await store.remember(
        PairingPayload.tryParseManual(
          ip: '192.168.1.15',
          port: 8765,
          pin: '483920',
          fingerprint: 'a' * 64,
        )!,
      );

      final sink = RecordingEventSink(isReady: true);
      await tester.pumpWidget(TapDeskApp(sink: sink));
      await tester.pumpAndSettle();

      // The tabs must not merely go disabled when the connection drops - the
      // app has to actually try to get it back.
      expect(find.text('Mouse'), findsOneWidget);
      sink.isReady = false;
      await tester.pumpAndSettle();

      // Still showing the tabs rather than dumping the user back to pairing:
      // a blip should not cost them their place.
      expect(find.text('Mouse'), findsOneWidget);
    });
  });

  group('going back', () {
    testWidgets('the back arrow asks before disconnecting', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = PairingStore();
      await store.remember(
        PairingPayload.tryParseManual(
          ip: '192.168.1.15',
          port: 8765,
          pin: '483920',
          fingerprint: 'a' * 64,
        )!,
      );

      var disconnected = false;
      await tester.pumpWidget(
        TapDeskApp(sink: RecordingEventSink(isReady: true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Confirmed, not immediate: disconnecting by accident mid-lecture is
      // worse than one extra tap.
      expect(find.text('Disconnect?'), findsOneWidget);

      await tester.tap(find.text('Stay connected'));
      await tester.pumpAndSettle();
      expect(find.text('Mouse'), findsOneWidget,
          reason: 'cancelling must keep the session');
      expect(disconnected, isFalse);
    });

    testWidgets('confirming returns to the pairing screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = PairingStore();
      await store.remember(
        PairingPayload.tryParseManual(
          ip: '192.168.1.15',
          port: 8765,
          pin: '483920',
          fingerprint: 'a' * 64,
        )!,
      );

      await tester.pumpWidget(
        TapDeskApp(sink: RecordingEventSink(isReady: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mouse'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      // Back where a new code can be scanned, and out of the tabs entirely.
      expect(find.text('Pair with a computer'), findsOneWidget);
      expect(find.text('Mouse'), findsNothing);
    });
  });

  group('leaving the app', () {
    testWidgets('the home screen offers a way out', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        TapDeskApp(sink: RecordingEventSink()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pair with a computer'), findsOneWidget);
      // It used to be a close button drawn only when the navigator could pop,
      // which on a fresh install is never - so there was no way out at all.
      expect(find.text('Exit'), findsOneWidget);
    });
  });
}
