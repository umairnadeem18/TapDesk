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
import '../state/diagnostics.dart';
import '../state/settings.dart';
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
class LiveEventSink extends EventSink {
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

  /// Told when the computer reports its settings, and when the phone wants to
  /// change them or unpair itself.
  ///
  /// Attached by whoever owns the settings screen, and left null when nothing
  /// is listening so the app runs in preview mode with no settings at all.
  AppSettings? settings;

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
    if (_connecting) {
      trace.add('connect ignored: an attempt is already running');
      return false;
    }
    _connecting = true;
    trace.reset();

    final effectiveToken = token ?? (payload.token.isEmpty ? null : payload.token);
    trace.add(
      'connect ${payload.ips.first}:${payload.port} '
      "name='${payload.name}' token=${effectiveToken != null ? 'yes' : 'no'} "
      "pcId fp=${payload.fingerprint.substring(0, 12)}…",
    );

    try {
      await _session?.disconnect();
      trace.add('previous session closed');
      _payload = payload;

      // The PC's identity is its certificate, not its address: the same
      // computer gets a new DHCP lease, and a different computer can be
      // handed the old one. Keying storage by the fingerprint means pairing
      // survives a network change and cannot be inherited by whatever
      // appears at that IP later.
      final pcId = payload.fingerprint;
      final store = _SessionStore(keyStore: keyStore, pcId: pcId);
      // Read up front rather than on first use: the handshake needs the key
      // synchronously, and leaving this to a lazy read meant a key saved on
      // a previous run was never sent - every app restart tried to pair
      // again with a token the companion had long since spent.
      try {
        store.seed(await keyStore.read(pcId));
      } catch (error) {
        // A secure-storage failure used to escape this method with
        // `_connecting` still true, which silenced every later attempt -
        // including the retry loop. Plant either null or the error's story,
        // never an exception nobody sees.
        trace.add('stored pairing unreadable ($error); continuing without it');
        store.seed(null);
      }
      trace.add(
        'saved device key: ${store.deviceKey() != null ? 'present' : 'none'}',
      );

      if (effectiveToken == null && store.deviceKey() == null) {
        // Nothing to prove who we are. Standing this up in the past left a
        // socket open with no hello - the server waited five seconds and
        // gave up - and a status that never left 'not connected'. One line
        // beats the whole silent dance.
        trace.add('no pairing token and no saved key: scan the QR again');
        delegate.onError(
          'This pairing is no longer valid. Scan the QR code on the PC '
          'to pair again.',
        );
        delegate.onStatus(
          ConnectionInfo(
            status: ConnectionStatus.failed,
            pcName: payload.name,
            lastError: 'forgotten pairing - scan again',
          ),
        );
        return false;
      }

      final session = TapDeskSession(
        factory: factory,
        delegate: _Adapter(delegate, store, notifyListeners),
        deviceName: deviceName,
        host: payload.ips.first,
        port: payload.port,
        fingerprint: payload.fingerprint,
      );

      // The computer's settings belong to a specific connection. A report
      // from the one being replaced must not be mistaken for the new one's.
      session.onRemoteSettings = (message) => settings?.applyRemote(message);

      try {
        await session.connect(token: effectiveToken, deviceKey: store.deviceKey());
      } catch (error) {
        // A failed certificate pin lands here. It must be reported as
        // itself: "could not connect" would leave the user retrying forever
        // against a server that is never going to be the computer they
        // paired with.
        final reason = describeConnectFailure(error);
        trace.add('connect failed: $reason ($error)');
        delegate.onError(reason);
        // Reporting the drop as well as the reason is what keeps the retry
        // loop alive. Without it the status stayed `connecting` with nobody
        // left to schedule the next attempt, and the app sat there for
        // good. The reason rides on the status too: the banner reads the
        // snapshot alone, and without it the user watched the loop go by
        // with never a word about what to do - the "connecting forever"
        // report, in full.
        delegate.onStatus(
          ConnectionInfo(
            status: ConnectionStatus.reconnecting,
            pcName: payload.name,
            lastError: reason,
          ),
        );
        return false;
      }

      _session = session;
      trace.add('session started');
      return true;
    } finally {
      _connecting = false;
    }
  }

  /// Re-open the connection to the PC we are already paired with.
  ///
  /// Used by the reconnect backoff. Takes no token on purpose: the saved device
  /// key is what authenticates a phone that has been paired before, and a
  /// pairing token is single-use and long since spent.
  Future<bool> reconnect() async {
    final target = _payload;
    if (target == null) return false;
    return connectTo(target);
  }

  Future<void> disconnect() async {
    await _session?.disconnect();
    _session = null;
    // The sliders must not keep showing a computer we are no longer driving.
    // Someone who disconnects and then scans a different PC would otherwise see
    // the first one's cursor speed and have no way to tell.
    settings?.clearRemote();
  }

  /// Let the settings screen reach this connection.
  ///
  /// Done here rather than in the screen so the wiring exists in exactly one
  /// place. A settings screen that silently does nothing when the transport
  /// forgets to call this looks identical to one that is not listening.
  void attachSettings(AppSettings value) {
    settings = value;
    value.onChange = (change) {
      send(
        SetEvent(
          cursorSpeed: change.cursorSpeed,
          accel: change.accel,
          safeMode: change.safeMode,
        ),
      );
    };
    value.onForget = () => send(const ForgetEvent());
  }

  @override
  bool send(TapDeskEvent event) => _session?.send(event) ?? false;

  @override
  Future<void> dispose() async {
    // The notifier must stop notifying before any await: the session's last
    // moments can still poke this sink, and after dispose that must be a
    // safe no-op rather than a change-notification into thin air.
    super.dispose();
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
  _Adapter(this._inner, this._store, this._onStatus);

  final SessionDelegate _inner;
  final _SessionStore _store;

  /// Called after every status change so the sink can rebuild the UI. This is
  /// the only place readiness is decided, so it is the only place that needs
  /// to say so - and forgetting it is what left every tab disabled after the
  /// PC had already said yes.
  final void Function() _onStatus;

  @override
  String? deviceKey() => _store.deviceKey();

  @override
  Future<void> saveDeviceKey(String deviceId, String deviceKey) =>
      _store.saveDeviceKey(deviceId, deviceKey);

  @override
  Future<void> forgetDeviceKey() => _store.forgetDeviceKey();

  @override
  void onStatus(ConnectionInfo info) {
    _inner.onStatus(info);
    _onStatus();
  }

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

  // Ordered by how often each is the actual cause, not by how interesting it
  // is. This message was "check they are on the same Wi-Fi", which sent the
  // user looking at their router while the real problem was that the companion
  // was not running at all - the state the app is in immediately after a
  // reinstall, because the installer only offers to start it.
  //
  // A refused TCP connection is the same error either way, so the one message
  // has to carry both causes. Naming the first is the point: somebody whose
  // phone and PC are on the same Wi-Fi can rule that out in a second and needs
  // to be told what to check instead.
  return 'Could not reach the computer. Check TapDesk is running on it, '
      'and that you are on the same Wi-Fi.';
}