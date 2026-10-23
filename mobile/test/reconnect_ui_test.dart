/// Why Mouse and Keyboard were dead while Slides looked alive.
///
/// The report from a real phone: "only slides buttons are working, mouse and
/// keyboard are not working... the mouse analog stick is also not even
/// moving."
///
/// Three tabs, all reading the same `context.watch<EventSink>()` and the same
/// `sink.isReady`. So the difference was not in the tabs - it was *when* the UI
/// found out the connection had come up.
///
/// The tabs are built while the phone is still waiting for the person at the PC
/// to tap Allow, so every control is built disabled. Nothing then told those
/// widgets they were stale: watching a plain object never rebuilds, and an
/// ancestor rebuilding with the same `const` children skips their subtrees
/// entirely. Mouse and Keyboard stayed dead for the whole session.
///
/// Slides only *looked* alive because its buttons still animate and buzz while
/// disabled. The stick has no such consolation: a disabled stick does nothing
/// at all, which is exactly what was reported.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/state/pairing_store.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';
import 'package:tapdesk_mobile/widgets/analog_stick.dart';
import 'package:tapdesk_mobile/widgets/mouse_controls.dart';

void main() {
  /// Drag the way a thumb does: pointer held down across frames.
  ///
  /// `tester.drag` completes the whole gesture inside one batch, so the 60 Hz
  /// timer behind the stick never gets a chance to fire and nothing is sent.
  /// That is a property of the test helper, not a bug in the app - but it is an
  /// easy one to write a test that wrongly concludes the stick is broken.
  Future<void> thumbDrag(WidgetTester tester, Finder stick) async {
    final centre = tester.getCenter(stick);
    final gesture = await tester.startGesture(centre);
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(centre + Offset(60.0 * i / 6, 0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pump();
  }

  Future<RecordingEventSink> pumpApp(
    WidgetTester tester, {
    required bool ready,
  }) async {
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

    // Deliberately starts NOT ready and is flipped after the app is on screen.
    // That is the real sequence: the tabs build while the PC is still waiting
    // for someone to tap Allow.
    final sink = RecordingEventSink(isReady: ready);
    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();
    return sink;
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  group('becoming connected after the tabs are already on screen', () {
    testWidgets('the controls are rebuilt enabled, not left stale', (tester) async {
      final sink = await pumpApp(tester, ready: false);
      await openTab(tester, 'Mouse');

      expect(
        tester.widget<MouseButtonWidget>(find.byType(MouseButtonWidget).first).enabled,
        isFalse,
      );

      sink.isReady = true;
      await tester.pumpAndSettle();

      // The core regression: this stayed false before the fix, so every mouse
      // and keyboard control was dead for the entire session.
      expect(
        tester.widget<MouseButtonWidget>(find.byType(MouseButtonWidget).first).enabled,
        isTrue,
      );
      expect(tester.widget<AnalogStick>(find.byType(AnalogStick)).enabled, isTrue);
    });

    testWidgets('the mouse stick streams once the PC accepts', (tester) async {
      final sink = await pumpApp(tester, ready: false);
      await openTab(tester, 'Mouse');
      final stick = find.byType(AnalogStick);

      // Nothing while disconnected - and the stick must let go cleanly.
      await thumbDrag(tester, stick);
      expect(
        sink.events.whereType<StickEvent>(),
        isEmpty,
        reason: 'a disconnected phone must not send input',
      );

      sink.isReady = true;
      await tester.pumpAndSettle();

      await thumbDrag(tester, stick);
      final streamed = sink.events.whereType<StickEvent>().toList();

      expect(streamed, isNotEmpty, reason: 'the stick was still dead after connecting');
      expect(streamed.any((e) => e.x > 0), isTrue);
      // The zero on release is what stops the cursor sliding forever.
      expect(streamed.last.x, 0);
    });

    testWidgets('the mouse buttons send once connected', (tester) async {
      final sink = await pumpApp(tester, ready: false);
      await openTab(tester, 'Mouse');

      sink.isReady = true;
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MouseButtonWidget).first);
      await tester.pump();

      expect(sink.events.whereType<ClickEvent>(), isNotEmpty);
    });

    testWidgets('the keyboard sends once connected', (tester) async {
      final sink = await pumpApp(tester, ready: false);
      await openTab(tester, 'Keyboard');

      sink.isReady = true;
      await tester.pumpAndSettle();

      await tester.tap(find.text('A').first);
      await tester.pump();

      expect(sink.events.whereType<TextEvent>(), isNotEmpty);
    });

    testWidgets('the slides tab keeps working too', (tester) async {
      // So the fix cannot be "make everything notify" if it breaks the one tab
      // that already appeared to work.
      final sink = await pumpApp(tester, ready: false);
      await openTab(tester, 'Slides');

      sink.isReady = true;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pump();

      expect(sink.events.whereType<SlideEvent>(), isNotEmpty);
    });
  });

  group('disconnecting again', () {
    testWidgets('controls go dead rather than silently dropping input', (tester) async {
      final sink = await pumpApp(tester, ready: true);
      await openTab(tester, 'Mouse');
      final stick = find.byType(AnalogStick);

      await thumbDrag(tester, stick);
      expect(sink.events.whereType<StickEvent>(), isNotEmpty);

      sink.clear();
      sink.isReady = false;
      await tester.pumpAndSettle();

      await thumbDrag(tester, stick);
      expect(
        sink.events.whereType<StickEvent>(),
        isEmpty,
        reason: 'input must stop the moment the connection does',
      );
    });
  });
}