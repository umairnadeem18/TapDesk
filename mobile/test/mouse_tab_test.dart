import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/state/pairing_store.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/transport/tapdesk_event.dart';
import 'package:tapdesk_mobile/widgets/analog_stick.dart';
import 'package:tapdesk_mobile/widgets/mouse_controls.dart';

/// Tests for the Mouse tab.
///
/// The gestures here are the fiddly part of the whole app: a tap must be
/// instant, a hold must become a drag, and a release must never leave the PC
/// thinking a button is still down. These assert the exact frames produced.
void main() {
  Future<RecordingEventSink> pumpApp(
    WidgetTester tester, {
    bool ready = true,
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

    final sink = RecordingEventSink(isReady: ready);
    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mouse'));
    await tester.pumpAndSettle();
    return sink;
  }

  group('click button gestures', () {
    testWidgets('a quick tap sends a single click', (tester) async {
      final sink = await pumpApp(tester);
      final button = find.byType(MouseButtonWidget).first;

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(sink.frames, ['{"t":"click","b":"left","a":"click"}']);
    });

    testWidgets('two quick taps send a double-click, not two clicks',
        (tester) async {
      final sink = await pumpApp(tester);
      final button = find.byType(MouseButtonWidget).first;

      final centre = tester.getCenter(button);
      final gesture = await tester.startGesture(centre);
      await gesture.up();
      await tester.pumpAndSettle();

      final second = await tester.startGesture(centre);
      await second.up();
      await tester.pumpAndSettle();

      // A double-click replaces the first click: the PC must not see
      // click+click and then double on top.
      expect(sink.frames, [
        '{"t":"click","b":"left","a":"click"}',
        '{"t":"click","b":"left","a":"double"}',
      ]);
    });

    testWidgets('holding then releasing sends down then up, for dragging',
        (tester) async {
      final sink = await pumpApp(tester);
      final button = find.byType(MouseButtonWidget).first;

      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(MouseButtonWidget.dragThreshold + const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(sink.frames, [
        '{"t":"click","b":"left","a":"down"}',
        '{"t":"click","b":"left","a":"up"}',
      ]);
    });

    testWidgets('the right button sends right-button clicks', (tester) async {
      final sink = await pumpApp(tester);

      await tester.tap(find.byType(MouseButtonWidget).last);
      await tester.pumpAndSettle();

      expect(sink.frames, ['{"t":"click","b":"right","a":"click"}']);
    });
  });

  group('analog stick', () {
    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      // Several moves, because the value is streamed on a timer rather than
      // per frame.
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
    }

    testWidgets('dragging streams stick values and ends with a zero',
        (tester) async {
      final sink = await pumpApp(tester);
      final stick = find.byType(AnalogStick);

      await drag(tester, tester.getCenter(stick),
          tester.getCenter(stick) + const Offset(60, 0));

      final stickFrames =
          sink.events.whereType<StickEvent>().toList();

      expect(stickFrames.length, greaterThan(3),
          reason: 'must stream at roughly 60 Hz, not once per drag');
      expect(stickFrames.any((e) => e.x > 0), isTrue,
          reason: 'dragging right must produce a positive x');
      expect(stickFrames.every((e) => e.x >= -1 && e.x <= 1), isTrue);
      expect(stickFrames.every((e) => e.y >= -1 && e.y <= 1), isTrue);

      // The zero on release is what stops the cursor. Without it a stream that
      // ends mid-deflection leaves the mouse sliding forever.
      expect(stickFrames.last.x, 0);
      expect(stickFrames.last.y, 0);
    });

    testWidgets('dragging up produces a positive y', (tester) async {
      final sink = await pumpApp(tester);
      final stick = find.byType(AnalogStick);

      await drag(tester, tester.getCenter(stick),
          tester.getCenter(stick) - const Offset(0, 60));

      final stickFrames = sink.events.whereType<StickEvent>().toList();
      expect(stickFrames.any((e) => e.y > 0), isTrue,
          reason: '+y is up, per protocol section 4.2');
    });

    testWidgets('a tap inside the dead zone sends nothing', (tester) async {
      final sink = await pumpApp(tester);
      final stick = find.byType(AnalogStick);

      await drag(tester, tester.getCenter(stick),
          tester.getCenter(stick) + const Offset(2, 0));

      expect(sink.events.whereType<StickEvent>(), isEmpty,
          reason: 'a resting thumb must not drift the cursor');
    });
  });

  group('scroll strip', () {
    testWidgets('dragging up scrolls up with a positive value', (tester) async {
      final sink = await pumpApp(tester);
      final strip = find.byType(ScrollStrip);

      final gesture = await tester.startGesture(tester.getCenter(strip));
      for (var i = 1; i <= 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final scrolls = sink.events.whereType<ScrollEvent>().toList();
      expect(scrolls, isNotEmpty);
      // Positive is up, away from the user, per protocol section 4.2.
      expect(scrolls.every((e) => e.dy > 0), isTrue);
    });
  });

  group('while disconnected', () {
    testWidgets('nothing is sent, and the stick is inert', (tester) async {
      final sink = await pumpApp(tester, ready: false);

      await tester.tap(find.byType(MouseButtonWidget).first);
      await tester.pumpAndSettle();

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(AnalogStick)));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(sink.frames, isEmpty);
    });
  });
}
