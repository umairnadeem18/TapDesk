/// The [EventSink] the app actually runs with.
///
/// Implements the same interface as `RecordingEventSink`, which is why no
/// screen changed in Phase 4. Its job is to turn "the user scanned a code" and
/// "the user tapped reconnect" into a live socket, and to keep one session per
/// computer so switching between two paired PCs is just a new session rather
/// than a new screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../state/connection_controller.dart';
import 'event_sink.dart';
import 'key_store.dart';
import 'pairing_payload.dart';
import 'session.dart';
import 'socket.dart';
import 'tapdesk_event.dart';

/// Owns the connection and presents it as an [EventSink].
///
/// The sink is always present so the UI never has to null-check it. Before
/// there is a session, or after one ends, [isReady] is false and [send]
/// refuses - the tabs stay on screen and inert rather than disappearing.
class LiveEventSink implements EventSink {
  LiveEventSink({
    required this.delegate,
    required this.keyStore,
    required this.factory,
    this.deviceName = 'TapDesk',
  });

  /// Receives status changes and errors for the UI.
  final SessionDelegate delegate;

  final KeyStore keyStore;

  /// Builds the socket. Injected so tests can drive the whole flow with no
  /// network; production passes [PinnedSocketFactory].
  final SocketFactory factory;

  final String deviceName;

  TapDeskSession? _session;
  PairingPayload? _payload;

  /// The PC the user is currently driving, if any.
  PairingPayload? get payload => _payload;

  bool _connecting = false;

  @override
  bool get isReady => _session?.isReady ?? false;

  @override
  int get sentCount => _session?.sentCount ?? 0;

  /// Connect to [payload], replacing any existing session.
  ///
  /// [token] overrides what the payload carries, which it normally already
  /// does. It is passed rather than read from storage because the pairing
  /// token is deliberately not persisted: it is single-use and short-lived,
  /// and there is no reason to write it to disk.
  Future<bool> connectTo(PairingPayload payload, {String? token}) async {
    if (_connecting) return false;
    _connecting = true;

    // A scanned payload already carries its token, so making the caller pass
    // it again was a trap - forgetting to produced "no device key and no
    // pairing token" at the moment the user scanned a perfectly good code. An
    // empty token means a remembered PC, where the saved device key is the
    // credential instead.
    final effectiveToken = token ?? (payload.token.isEmpty ? null : payload.token);

    await _session?.disconnect();
    _payload = payload;

    // The PC's identity is its certificate, not its address: the same computer
    // gets a new DHCP lease, and a different computer can be handed the old
    // one. Keying storage by the fingerprint means pairing survives a network
    // change and cannot be inherited by whatever appears at that IP later.
    final pcId = payload.fingerprint;
    final store = _SessionStore(keyStore: keyStore, pcId: pcId);
    // Read up front rather than on first use: the handshake needs the key
    // synchronously, and leaving this to a lazy read meant a key saved on a
    // previous run was never sent - every app restart tried to pair again with
    // a token the companion had long since spent.
    store.seed(await keyStore.read(pcId));

    final session = TapDeskSession(
      factory: factory,
      delegate: _Adapter(delegate, store),
      deviceName: deviceName,
      host: payload.ips.first,
      port: payload.port,
      fingerprint: payload.fingerprint,
    );

    try {
      await session.connect(token: effectiveToken, deviceKey: store.deviceKey());
    } catch (error) {
      // A failed certificate pin lands here. It must be reported as itself:
      // "could not connect" would leave the user retrying forever against a
      // server that is never going to be the computer they paired with.
      delegate.onError(describeConnectFailure(error));
      _connecting = false;
      return false;
    }

    _session = session;
    _connecting = false;
    return true;
  }

  Future<void> disconnect() async {
    await _session?.disconnect();
    _session = null;
  }

  @override
  bool send(TapDeskEvent event) => _session?.send(event) ?? false;

  Future<void> dispose() async {
    await _session?.dispose();
    _session = null;
  }
}

/// Adapts a [KeyStore] to the session's needs, remembering what it was told.
class _SessionStore implements SessionDelegate {
  _SessionStore({required this.keyStore, required this.pcId});

  final KeyStore keyStore;
  final String pcId;
  String? _key;

  /// Load the persisted key before the handshake asks for it.
  void seed(String? key) => _key = key;

  @override
  String? deviceKey() => _key;

  @override
  Future<void> saveDeviceKey(String deviceId, String deviceKey) async {
    _key = deviceKey;
    await keyStore.write(pcId, deviceKey);
  }

  @override
  Future<void> forgetDeviceKey() async {
    _key = null;
    await keyStore.forget(pcId);
  }

  @override
  void onStatus(ConnectionInfo info) => throw UnimplementedError();

  @override
  void onError(String message) => throw UnimplementedError();
}

/// Forwards the session's news to the real delegate while holding the key.
class _Adapter implements SessionDelegate {
  _Adapter(this._inner, this._store);

  final SessionDelegate _inner;
  final _SessionStore _store;

  @override
  String? deviceKey() => _store.deviceKey();

  @override
  Future<void> saveDeviceKey(String deviceId, String deviceKey) =>
      _store.saveDeviceKey(deviceId, deviceKey);

  @override
  Future<void> forgetDeviceKey() => _store.forgetDeviceKey();

  @override
  void onStatus(ConnectionInfo info) => _inner.onStatus(info);

  @override
  void onError(String message) => _inner.onError(message);
}

/// Turn a connect failure into something a person can act on.
///
/// A certificate mismatch is worth naming precisely, because it is the one
/// case where the user is probably not in the room with the PC - and the fix
/// is never to retry, it is to go and look at the right screen.
String describeConnectFailure(Object error) {
  if (error is ArgumentError) {
    return 'That pairing code was not read correctly. Scan it again.';
  }
  if (error is HandshakeException) {
    return switch (error.reason) {
      HandshakeFailure.fingerprintMismatch =>
        'This is not the computer you paired with. Nothing was sent to it.',
      HandshakeFailure.timedOut => 'The computer did not answer in time.',
    };
  }
  debugPrint('[tapdesk] connect failed: $error');
  return 'Could not reach that computer. Check they are on the same Wi-Fi.';
}