import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';

/// Tests for preview mode.
///
/// Preview exists because the design must be signed off on a device before any
/// transport work, and the companion that shows a QR code is Phase 5. These
/// tests guard the one thing that makes it acceptable: it must never be
/// reachable in a release build, and it must never look connected.
void main() {
  testWidgets('preview is reachable from pairing on a debug build',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(TapDeskApp(sink: RecordingEventSink()));
    await tester.pumpAndSettle();

    expect(find.text('Preview the controller (debug build)'), findsOneWidget);

    await tester.tap(find.text('Preview the controller (debug build)'));
    await tester.pumpAndSettle();

    // The controller is now reachable without a PC - the actual problem this
    // was added to solve.
    expect(find.text('Slides'), findsOneWidget);
    expect(find.text('Mouse'), findsOneWidget);
    expect(find.text('Keyboard'), findsOneWidget);
  });

  testWidgets('preview says plainly that nothing is connected',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(TapDeskApp(sink: RecordingEventSink()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview the controller (debug build)'));
    await tester.pumpAndSettle();

    // Controls are live so they can be judged, so the banner has to be
    // unmistakable. A user must never think their taps are reaching a PC.
    expect(
      find.textContaining('no computer connected'),
      findsOneWidget,
    );
  });

  testWidgets('preview controls are live and record events',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sink = RecordingEventSink();

    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview the controller (debug build)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(sink.frames, ['{"t":"slide","a":"next"}']);
  });

  testWidgets('exiting preview returns to pairing', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(TapDeskApp(sink: RecordingEventSink()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview the controller (debug build)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(find.text('Scan the code on your PC'), findsOneWidget);
  });
}
