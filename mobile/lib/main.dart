import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/connection_controller.dart';
import 'theme/tokens.dart';
import 'ui/app_shell.dart';

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
  const TapDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConnectionController(),
      child: MaterialApp(
        title: 'TapDesk',
        debugShowCheckedModeBanner: false,
        // Dark only, on purpose — see docs/design-system.md section 1.
        theme: TapDeskTheme.dark,
        darkTheme: TapDeskTheme.dark,
        themeMode: ThemeMode.dark,
        home: Consumer<ConnectionController>(
          builder: (context, connection, _) => AppShell(
            connection: connection,
          ),
        ),
      ),
    );
  }
}
