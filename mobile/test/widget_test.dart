import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/state/pairing_store.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/theme/tokens.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';

/// Smoke tests for the app's entry flow.
///
/// These cover the two things that break silently: which screen a fresh
/// install lands on, and that a paired phone skips straight past pairing.
/// Anything deeper belongs with the screen it belongs to.
void main() {
  /// Seed a remembered PC.
  ///
  /// Written through `PairingStore` rather than by setting the preference key
  /// literally - a hardcoded key here would drift from the real one and fail
  /// for a reason that has nothing to do with the app.
  Future<void> givenPairedDevice() async {
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
  }

  testWidgets('a fresh install opens on pairing, not the tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    // The camera rationale comes before the system prompt, so that is the
    // first thing a new user sees - not a bare permission dialog.
    expect(find.text('Scan the code on your PC'), findsOneWidget);
    expect(find.text('Allow camera'), findsOneWidget);

    // The manual fallback is offered from the start, so a user who denies the
    // camera is never stuck.
    expect(find.text('Enter code manually'), findsOneWidget);
    expect(find.text('Slides'), findsNothing);
  });

  testWidgets('a paired phone goes straight to the tabs', (tester) async {
    await givenPairedDevice();

    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    for (final tab in ['Slides', 'Mouse', 'Keyboard']) {
      expect(find.text(tab), findsOneWidget, reason: '$tab tab is missing');
    }
    expect(find.text('Computer'), findsOneWidget);
  });

  testWidgets('starts dark, shows three tabs, and switches between them',
      (tester) async {
    await givenPairedDevice();

    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, TapDeskColors.background);

    // Switching tabs works even while disconnected: a user must be able to
    // see the "not connected" state on each tab.
    await tester.tap(find.text('Slides'));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Mouse'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.touch_app_outlined), findsOneWidget);
  });

  testWidgets('disconnected explains itself rather than looking broken',
      (tester) async {
    await givenPairedDevice();

    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    expect(find.text('Not connected'), findsOneWidget);

    // Slides is a real screen now, so it shows its controls and relies on the
    // banner plus inert buttons rather than placeholder text.
    expect(find.text('Next'), findsOneWidget);

    // Keyboard is not built yet, so it still explains itself.
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    expect(find.text('Connect to a PC to use this tab.'), findsOneWidget);
  });

  testWidgets('settings opens from the app bar', (tester) async {
    await givenPairedDevice();

    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Settings arrive in Phase 3.5'), findsOneWidget);
  });

  testWidgets('an event sink can be injected for inspection', (tester) async {
    await givenPairedDevice();
    final sink = RecordingEventSink();

    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();

    // Proves the seam exists: Phase 4 swaps this one object for the real
    // transport without any screen changing.
    expect(find.text('Mouse'), findsOneWidget);
    expect(sink.sentCount, 0);
  });
}
