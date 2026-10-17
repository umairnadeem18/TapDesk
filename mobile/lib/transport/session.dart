/// A live connection to the companion.
///
/// Implements [EventSink] itself, so swapping it in for `RecordingEventSink` is
/// the whole of the Phase 4 change in `main.dart`. Screens that call
/// `sink.send(...)` need to know nothing about sockets.
library;

import 'dart:async';

import '../state/connection_controller.dart';
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
class TapDeskSession implements EventSink {
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

  ConnectionStatus get status => _machine.status;

  @override
  bool get isReady => _machine.status == ConnectionStatus.connected;

  @override
  int get sentCount => _sentCount;

  /// Open the socket and start the handshake.
  ///
  /// Throws if the certificate does not match. That is not swallowed on
  /// purpose: a failed pin means this is not the computer the user paired
  /// with, and the UI has to say so rather than reconnecting in a loop.
  Future<void> connect({String? token, String? deviceKey}) async {
    _publish(ConnectionStatus.connecting);

    final socket = await factory.connect(
      host: host,
      port: port,
      fingerprint: fingerprint,
    );
    _socket = socket;

    _subscription = socket.messages.listen(
      _onMessage,
      onDone: _onSocketClosed,
      onError: (Object error) => _onSocketClosed(),
    );

    // The caller's key wins, so a freshly reconnected PC is preferred over a
    // stale one that may since have been revoked.
    final frames = _machine.startFrames(
      deviceName: deviceName,
      token: token,
      deviceKey: deviceKey ?? delegate.deviceKey(),
    );
    for (final frame in frames) {
      socket.send(frame);
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

      case Ignore():
        break;
    }
  }

  void _onSocketClosed() {
    if (_disposed) return;
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
    delegate.onStatus(
      ConnectionInfo(
        status: status,
        pcName: pcName,
        paired: status == ConnectionStatus.connected,
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown(1001, 'app closed');
  }
}