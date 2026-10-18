import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/connection_controller.dart';
import 'state/pairing_store.dart';
import 'state/preview_mode.dart';
import 'theme/tokens.dart';
import 'transport/event_sink.dart';
import 'transport/key_store.dart';
import 'transport/live_sink.dart';
import 'transport/pairing_payload.dart';
import 'transport/session.dart';
import 'transport/socket.dart';
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

class TapDeskApp extends StatefulWidget {
  const TapDeskApp({super.key, this.sink});

  /// Overridable so tests can inspect exactly what the UI tried to send.
  /// When null, a real connection is made and a real key store is used.
  final EventSink? sink;

  @override
  State<TapDeskApp> createState() => _TapDeskAppState();
}

class _TapDeskAppState extends State<TapDeskApp> {
  late final ConnectionController _controller;
  late final EventSink _sink;
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _controller = ConnectionController();

    // An injected sink wins, which is what keeps the widget tests free of a
    // network and a Keystore. Only the real app builds a live session.
    _sink = widget.sink ??
        LiveEventSink(
          delegate: _UiDelegate(_controller, _error),
          keyStore: SecureKeyStore(),
          factory: const PinnedSocketFactory(),
        );
  }

  @override
  void dispose() {
    final sink = _sink;
    if (sink is LiveEventSink) sink.dispose();
    _controller.dispose();
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _controller),
        // Loaded once at startup so a paired phone does not flash the pairing
        // screen before remembering what it knows.
        ChangeNotifierProvider(create: (_) => PairingStore()..load()),
        ChangeNotifierProvider(create: (_) => PreviewMode()),
        // ChangeNotifierProvider, not Provider: the tabs watch the sink to learn
        // whether they may accept input, and watching a plain object never
        // rebuilds anything. The tabs are built while the PC is still deciding
        // whether to allow this phone, so every control starts disabled and
        // has to be told when that changes - otherwise Mouse and Keyboard stay
        // dead for the whole session.
        ChangeNotifierProvider<EventSink>.value(value: _sink),
        ValueListenableProvider<String?>.value(value: _error),
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

/// Turns session news into things the UI already knows how to show.
///
/// A thin adapter rather than logic: the connection state machine lives in
/// `transport/handshake.dart`, and the retry timer lives in
/// `ConnectionController`. Neither this class nor the widgets should grow a
/// second opinion about what the connection is doing.
class _UiDelegate implements SessionDelegate {
  _UiDelegate(this._controller, this._error);

  final ConnectionController _controller;
  final ValueNotifier<String?> _error;

  @override
  String? deviceKey() => null;

  @override
  Future<void> saveDeviceKey(String deviceId, String deviceKey) async {}

  @override
  Future<void> forgetDeviceKey() async {}

  @override
  void onStatus(ConnectionInfo info) {
    _controller.update(info);
    if (info.status == ConnectionStatus.reconnecting) {
      _controller.scheduleReconnect();
    } else if (info.status == ConnectionStatus.connected) {
      _error.value = null;
    }
  }

  @override
  void onError(String message) {
    _error.value = message;
    if (kDebugMode) debugPrint('[tapdesk] $message');
  }
}

/// Chooses between pairing and the main shell.
///
/// `AppShell` stays the home of the three tabs; this widget only decides which
/// of the two the user should land on, and starts the connection when there is
/// somewhere to start it.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    // Connecting after the first frame: the providers are built during it,
    // and reading them here would be reading a tree that does not exist yet.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectToRemembered());
  }

  /// Connect to the computer this phone was last paired with, if any.
  Future<void> _connectToRemembered() async {
    final store = context.read<PairingStore>();
    final sink = context.read<EventSink>();
    if (sink is! LiveEventSink) return;

    final remembered = store.devices.isEmpty ? null : store.devices.last;
    if (remembered == null) return;

    await sink.connectTo(
      PairingPayload(
        version: 1,
        name: remembered.name,
        ips: [remembered.host],
        port: remembered.port,
        // No token: this PC is already paired, so the saved device key is
        // what authenticates. The companion deliberately does not re-prompt
        // for a device it already trusts.
        token: '',
        fingerprint: remembered.fingerprint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPaired = context.select<PairingStore, bool>(
      (store) => store.hasPairedDevices,
    );
    final preview = context.select<PreviewMode, bool>((p) => p.isActive);

    // Preview wins over pairing: the point of it is to reach the tabs when
    // there is no PC and no pairing.
    if (preview) return const AppShell(preview: true);

    if (!hasPaired) {
      return PairingScreen(
        onPaired: _onPaired,
        onReconnect: (_) => _connectToRemembered(),
      );
    }
    return const AppShell();
  }

  Future<void> _onPaired(PairingPayload payload) async {
    final sink = context.read<EventSink>();
    if (sink is LiveEventSink) {
      // The token is passed straight through and never stored. It is
      // single-use; once the companion has spent it, the saved device key
      // takes over for good.
      await sink.connectTo(payload, token: payload.token);
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
      (route) => false,
    );
  }
}