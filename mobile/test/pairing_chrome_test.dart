import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';

/// Tests for the pairing screen's chrome.
///
/// The close button had a genuine bug: on a fresh install pairing is the home
/// route, so pressing it popped nothing and it looked broken. The rule now is
/// that a control is either functional or not drawn, and these tests hold it
/// to that.
void main() {
  testWidgets('no dead close button on a fresh install', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(TapDeskApp(sink: RecordingEventSink()));
    await tester.pumpAndSettle();

    // Nothing to go back to on a first launch, so the button must be absent
    // rather than present and inert.
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('preview entry is reachable and clearly labelled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(TapDeskApp(sink: RecordingEventSink()));
    await tester.pumpAndSettle();

    // This is the only route to the controller while the companion that shows
    // a QR code does not exist, so its absence means the whole UI is
    // unreachable on a device.
    expect(find.text('Preview the controller (debug build)'), findsOneWidget);
  });

  testWidgets('tapping preview reaches all three tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(TapDeskApp(sink: RecordingEventSink()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview the controller (debug build)'));
    await tester.pumpAndSettle();

    for (final tab in ['Slides', 'Mouse', 'Keyboard']) {
      expect(find.text(tab), findsOneWidget, reason: '$tab is not reachable');
    }
  });
}
