/// A live connection to the companion.
///
/// Implements [EventSink] itself, so swapping it in for `RecordingEventSink` is
/// the whole of the Phase 4 change in `main.dart`. Screens that call
/// `sink.send(...)` need to know nothing about sockets.
library;

import 'dart:async';

import '../state/connection_controller.dart';
import '../state/diagnostics.dart';
import 'event_sink.dart';
import 'handshake.dart';
import 'socket.dart';
import 'tapdesk_event.dart';

/// Where the session reports what is happening, and asks for credentials.
abstract class SessionDelegate {
  /// The saved device key, if this PC has been paired before.
  String? deviceKey();

  /// Persist the key the PC just handed over. Called once, at pairing.
  Future<void> saveDeviceKey(String deviceId, String deviceKey);

  /// The PC has revoked us; the stored key must be forgotten.
  Future<void> forgetDeviceKey();

  void onStatus(ConnectionInfo info);

  /// A readable description of a failure, for the UI to show.
  void onError(String message);
}

/// Drives one socket from hello to connected, and relays input.
class TapDeskSession extends EventSink {
  TapDeskSession({
    required this.factory,
    required this.delegate,
    required this.deviceName,
    required this.host,
    required this.port,
    required this.fingerprint,
  });

  final SocketFactory factory;
  final SessionDelegate delegate;
  final String deviceName;
  final String host;
  final int port;
  final String fingerprint;

  final HandshakeMachine _machine = HandshakeMachine();
  TapDeskSocket? _socket;
  StreamSubscription<String>? _subscription;
  int _sentCount = 0;
  bool _disposed = false;

  /// Told what the computer says it is doing, as a `settings` frame.
  ///
  /// Set by the sink, which forwards it to the settings screen. A session does
  /// not know or care whether a settings screen exists, and the alternative -
  /// reaching into the notifier from here - would couple the transport to a
  /// screen it has no business knowing about.
  void Function(Map<Object?, Object?> message)? onRemoteSettings;

  ConnectionStatus get status => _machine.status;

  @override
  bool get isReady => _machine.status == ConnectionStatus.connected;

  /// Called whenever [isReady] changes, so anything watching this session sees
  /// the transition. The delegate is told separately - this is for whoever is
  /// watching the object itself.
  @override
  void notifyListeners() {
    final now = _machine.status == ConnectionStatus.connected;
    if (now == _lastReady) return;
    _lastReady = now;
    super.notifyListeners();
  }

  bool _lastReady = false;

  @override
  int get sentCount => _sentCount;

  /// Open the socket and start the handshake.
  ///
  /// Throws if the certificate does not match. That is not swallowed on
  /// purpose: a failed pin means this is not the computer the user paired
  /// with, and the UI has to say so rather than reconnecting in a loop.
  Future<void> connect({String? token, String? deviceKey}) async {
    _publish(ConnectionStatus.connecting);
    trace.add('dialing $host:$port (pinned to ${fingerprint.substring(0, 12)}…)');

    final socket = await factory.connect(
      host: host,
      port: port,
      fingerprint: fingerprint,
    );
    _socket = socket;
    trace.add('socket open');

    _subscription = socket.messages.listen(
      _onMessage,
      onDone: _onSocketClosed,
      onError: (Object error) => _onSocketClosed(),
    );

    try {
      // The caller's key wins, so a freshly reconnected PC is preferred over
      // a stale one that may since have been revoked.
      final frames = _machine.startFrames(
        deviceName: deviceName,
        token: token,
        deviceKey: deviceKey ?? delegate.deviceKey(),
      );
      for (final frame in frames) {
        socket.send(frame);
      }
      // Milestone, not vanity: three nights were spent with a phone whose
      // sockets opened and then went quiet, and without a line naming which
      // side stopped talking there was no way to point at one.
      trace.add('sent ${frames.length} frame(s) - hello${frames.length > 1 ? " + auth" : ""}');
    } on Object {
      // A machine or send failure right after opening used to leave the
      // socket open with nothing ever sent - on the server that looks like a
      // phone that dialled and said nothing, and it sat there for the full
      // hello timeout. Never leave a half-handshaken socket behind.
      await socket.close();
      _socket = null;
      rethrow;
    }
  }

  @override
  bool send(TapDeskEvent event) {
    if (!isReady) return false;
    _socket?.send(event.encode());
    _sentCount++;
    return true;
  }

  /// Release everything and hang up.
  ///
  /// Sends `bye` first so the PC can let go of anything held immediately,
  /// rather than waiting for its own timeout to notice we left.
  Future<void> disconnect({int code = 1000, String reason = ''}) async {
    if (isReady) {
      for (final frame in _machine.goodbyeFrames()) {
        _socket?.send(frame);
      }
    }
    await _teardown(code, reason);
  }

  void _onMessage(String raw) {
    // The text of each frame is duplicated in the strip; truncation keeps a
    // long frame from flooding it. This is how a reply that stalls (or
    // arrives and is not understood) becomes visible on the phone itself.
    trace.add('PC: ${raw.length > 80 ? "${raw.substring(0, 80)}…" : raw}');
    final outcome = isReady
        ? _machine.handleConnected(raw)
        : _machine.handle(raw);

    switch (outcome) {
      case AdvanceTo(:final status, :final pcName, :final deviceId, :final deviceKey, :final error):
        // _publish reports the error too, so it is not reported here.
        _publish(status, pcName: pcName, error: error);

        if (status == ConnectionStatus.connected && deviceId != null && deviceKey != null) {
          // Persist before announcing success: if the app dies between the
          // two, the user would otherwise have to scan the code again for a
          // pairing that actually succeeded.
          unawaited(delegate.saveDeviceKey(deviceId, deviceKey));
        }
        if (status == ConnectionStatus.revoked) {
          unawaited(delegate.forgetDeviceKey());
        }

      case SendFrames(:final frames):
        for (final frame in frames) {
          _socket?.send(frame);
        }

      case ReportSettings(:final message):
        onRemoteSettings?.call(message);

      case Ignore():
        break;
    }
  }

  void _onSocketClosed() {
    if (_disposed) return;
    trace.add('socket closed by PC (status was ${_machine.status.label})');
    // Losing a healthy connection is the common case - a phone leaving Wi-Fi
    // range, a laptop sleeping - and it should reconnect rather than send the
    // user back to the pairing screen. The machine decides, so its status and
    // what the UI is told can never disagree.
    final outcome = _machine.handleDrop();
    _publish(outcome.status, error: outcome.error);
  }

  Future<void> _teardown(int code, String reason) async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close(code, reason);
    _socket = null;
  }

  void _publish(ConnectionStatus status, {String? pcName, String? error}) {
    if (error != null) delegate.onError(error);
    // The reason rides with the status, not only through onError: the banner
    // reads ConnectionInfo alone, so a reason delivered purely as an event
    // reached everybody except the one widget that could show it. A denial
    // used to say only "Could not connect" with no word about why.
    delegate.onStatus(
      ConnectionInfo(
        status: status,
        pcName: pcName,
        paired: status == ConnectionStatus.connected,
        lastError: error,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    _disposed = true;
    await _teardown(1001, 'app closed');
  }
}