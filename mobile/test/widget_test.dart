import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/theme/tokens.dart';

/// Smoke test for the shell.
///
/// This checks the things that break silently: the app starts on the dark
/// theme, the three tabs are present and switchable, and the settings route
/// opens. Anything deeper belongs with the screen it belongs to, in Phase 3.
void main() {
  testWidgets('starts dark, shows three tabs, and opens settings',
      (tester) async {
    await tester.pumpWidget(const TapDeskApp());

    // Dark background, not the default white.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, TapDeskColors.background);

    for (final tab in ['Slides', 'Mouse', 'Keyboard']) {
      expect(find.text(tab), findsOneWidget, reason: '$tab tab is missing');
    }

    // Switching tabs works even while disconnected: a user must be able to see
    // the "not connected" state on each tab.
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard tab'), findsOneWidget);
  });

  testWidgets('disconnected shows a reason, not a broken screen',
      (tester) async {
    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    // Idle is the only state with no banner - it opens on the pairing flow.
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect to a PC to use this tab.'), findsOneWidget);
  });

  testWidgets('settings opens from the app bar', (tester) async {
    await tester.pumpWidget(const TapDeskApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Settings arrive in Phase 3.5'), findsOneWidget);
  });
}
