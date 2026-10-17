import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/state/pairing_store.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';

/// Tests for the Slides tab.
///
/// The value here is the frame assertions: pressing "Next" must put exactly
/// `{"t":"slide","a":"next"}` on the wire, because the companion maps that to
/// PageDown with a Right-arrow fallback. Getting the action name subtly wrong
/// produces a button that appears to work and does nothing.
void main() {
  Future<RecordingEventSink> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await _seededStore();

    final sink = RecordingEventSink(isReady: true);
    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();
    return sink;
  }

  Future<void> openSlides(WidgetTester tester) async {
    await tester.tap(find.text('Slides'));
    await tester.pumpAndSettle();
  }

  testWidgets('Next and Previous send the right slide actions',
      (tester) async {
    final sink = await pumpApp(tester);
    await openSlides(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();

    expect(sink.frames, [
      '{"t":"slide","a":"next"}',
      '{"t":"slide","a":"prev"}',
    ]);
  });

  testWidgets('Start, End and Black send the right slide actions',
      (tester) async {
    final sink = await pumpApp(tester);
    await openSlides(tester);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black'));
    await tester.pumpAndSettle();

    expect(sink.frames, [
      '{"t":"slide","a":"start"}',
      '{"t":"slide","a":"end"}',
      '{"t":"slide","a":"blank"}',
    ]);
  });

  testWidgets('controls are dead while disconnected', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _seededStore();

    // Not ready = not connected. The buttons must be inert, not merely dimmed.
    final sink = RecordingEventSink(isReady: false);
    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();
    await openSlides(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(sink.frames, isEmpty,
        reason: 'a disconnected app must not queue input silently');
  });

  testWidgets('the timer counts up and resets', (tester) async {
    await pumpApp(tester);
    await openSlides(tester);

    expect(find.text('00:00'), findsOneWidget);

    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();
    expect(find.text('Stop timer'), findsOneWidget);

    // Three seconds of a lecture timer.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('00:03'), findsOneWidget);

    await tester.tap(find.text('Stop timer'));
    await tester.pumpAndSettle();
    expect(find.text('00:00'), findsOneWidget);
  });

  group('slide actions', () {
    test('match the protocol vocabulary exactly', () {
      // These strings are the contract. If one is renamed here it must be
      // renamed in docs/protocol.md and in the companion at the same time.
      expect(
        const [
          SlideEvent(SlideAction.next),
          SlideEvent(SlideAction.prev),
          SlideEvent(SlideAction.start),
          SlideEvent(SlideAction.end),
          SlideEvent(SlideAction.blank),
        ].map((e) => e.encode()),
        [
          '{"t":"slide","a":"next"}',
          '{"t":"slide","a":"prev"}',
          '{"t":"slide","a":"start"}',
          '{"t":"slide","a":"end"}',
          '{"t":"slide","a":"blank"}',
        ],
      );
    });
  });
}

/// Seeds one remembered PC so the app opens on the tabs rather than pairing.
Future<void> _seededStore() async {
  final store = PairingStore();
  await store.remember(
    PairingPayload.tryParseManual(
      ip: '192.168.1.15',
      port: 8765,
      pin: '483920',
      fingerprint: 'a' * 64,
    )!,
  );
}
