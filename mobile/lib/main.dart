import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/connection_controller.dart';
import 'state/pairing_store.dart';
import 'theme/tokens.dart';
import 'transport/event_sink.dart';
import 'ui/app_shell.dart';
import 'screens/pairing_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(TapDeskTheme.systemOverlay);
  // Portrait only: the three tabs are laid out for a hand-held phone, and
  // rotating mid-lecture should not reflow the controls under the thumb.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const TapDeskApp());
}

class TapDeskApp extends StatelessWidget {
  const TapDeskApp({super.key, this.sink});

  /// Overridable so tests can inspect exactly what the UI tried to send.
  final EventSink? sink;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionController()),
        // Loaded once at startup so a paired phone does not flash the pairing
        // screen before remembering what it knows.
        ChangeNotifierProvider(create: (_) => PairingStore()..load()),
        Provider<EventSink>.value(value: sink ?? RecordingEventSink()),
      ],
      child: MaterialApp(
        title: 'TapDesk',
        debugShowCheckedModeBanner: false,
        // Dark only, on purpose — see docs/design-system.md section 1.
        theme: TapDeskTheme.dark,
        darkTheme: TapDeskTheme.dark,
        themeMode: ThemeMode.dark,
        home: const _Root(),
      ),
    );
  }
}

/// Chooses between pairing and the main shell.
///
/// `AppShell` stays the home of the three tabs; this widget only decides which
/// of the two the user should land on. Keeping the decision in one small place
/// means Phase 4 can change "when are we paired" without touching either.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final hasPaired = context.select<PairingStore, bool>(
      (store) => store.hasPairedDevices,
    );

    if (!hasPaired) {
      return PairingScreen(onPaired: (_) => _openShell(context));
    }
    return const AppShell();
  }

  void _openShell(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
      (route) => false,
    );
  }
}
