/// The pairing handshake, as a pure state machine.
///
/// This exists as its own file, separate from the socket, for the same reason
/// the companion splits planning from performing input: the interesting
/// decisions are "is this reply the one we were waiting for, and does it mean
/// the PC is trusted?" and those decisions deserve to be testable without a
/// network, a certificate, or a phone.
///
/// Feeding it a message returns the next state and the frames to send. Nothing
/// here performs I/O, so every branch below is reachable from a unit test.
library;

import 'dart:convert';

import '../state/connection_controller.dart';

/// What the session should do after handling a message.
sealed class HandshakeOutcome {
  const HandshakeOutcome();
}

/// Move to [status]; send nothing.
class AdvanceTo extends HandshakeOutcome {
  const AdvanceTo(this.status, {this.pcName, this.deviceId, this.deviceKey, this.error});

  final ConnectionStatus status;
  final String? pcName;

  /// Set on `auth_ok`. The phone stores these; the PC keeps only a hash.
  final String? deviceId;
  final String? deviceKey;
  final String? error;
}

/// Send [frames] and stay where you are.
///
/// Used for replies that arrive while we are already connected, such as the PC
/// asking us to disconnect.
class SendFrames extends HandshakeOutcome {
  const SendFrames(this.frames);
  final List<String> frames;
}

/// The message was not understood here. Deliberately not fatal: once connected
/// the server may add event types, and an old phone should ignore them rather
/// than drop the user's session.
class Ignore extends HandshakeOutcome {
  const Ignore();
}

/// Drives the phone's half of the pairing handshake.
///
/// The sequence is fixed by docs/protocol.md §5:
/// `hello` -> `hello_ok` -> `auth_pending` -> `auth_ok`, and the phone sends
/// nothing after `auth_ok` until the user actually touches something.
class HandshakeMachine {
  HandshakeMachine({this.protocolVersion = 1});

  final int protocolVersion;

  ConnectionStatus _status = ConnectionStatus.idle;

  /// Whether this attempt authenticated with a key the phone already had.
  ///
  /// This is the difference between a first pairing and a reconnection, and it
  /// decides whether `auth_ok` is allowed to arrive without the PC having
  /// asked its user. A reconnect proves itself with the key, so the PC does
  /// not re-prompt - the server sends `auth_ok` straight away (server.py
  /// `_auth_with_key`). A first pairing authenticates with a single-use token,
  /// so the prompt is the only thing standing between a stranger and control
  /// of the machine, and an `auth_ok` without one is ignored.
  bool _usedSavedKey = false;

  ConnectionStatus get status => _status;

  /// The frames to send once the socket is open.
  ///
  /// `hello` first, then either the saved device key or the pairing token.
  /// Sending the token when we have a key would be strictly worse: the token
  /// is single-use, so it would burn a code the user may need for a second
  /// phone, and it would re-prompt the user on a device that is already
  /// trusted.
  List<String> startFrames({
    required String deviceName,
    String? token,
    String? deviceKey,
  }) {
    _status = ConnectionStatus.connecting;
    _usedSavedKey = deviceKey != null;
    return <String>[
      encode(<String, Object?>{
        't': 'hello',
        'v': protocolVersion,
        'device': deviceName,
        'platform': 'android',
      }),
      if (deviceKey != null)
        encode(<String, Object?>{'t': 'auth', 'key': deviceKey})
      else if (token != null)
        encode(<String, Object?>{'t': 'auth', 'token': token})
      else
        // Nothing to authenticate with. Better a loud failure than an
        // unauthenticated socket that looks paired.
        throw StateError('no device key and no pairing token to authenticate with'),
    ];
  }

  /// Fold one decoded message from the PC into the next state.
  HandshakeOutcome handle(String raw) {
    final Map<String, Object?> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const Ignore();
      message = decoded;
    } on FormatException {
      // A server speaking nonsense is not something to keep talking to.
      _status = ConnectionStatus.failed;
      return const AdvanceTo(ConnectionStatus.failed, error: 'The computer sent something TapDesk could not read.');
    }

    final type = message['t'];

    switch (type) {
      case 'hello_ok':
        if (_status != ConnectionStatus.connecting) return const Ignore();
        final pc = message['pc'];
        final name = pc is Map ? pc['name'] as String? : null;
        if (name == null) {
          _status = ConnectionStatus.failed;
          return const AdvanceTo(
            ConnectionStatus.failed,
            error: 'The computer did not say what it was called.',
          );
        }
        return _moveTo(ConnectionStatus.handshaking, pcName: name);

      case 'auth_pending':
        // The PC is asking its user. We just wait - and we are still not
        // allowed to send input.
        if (_status != ConnectionStatus.handshaking) return const Ignore();
        return _moveTo(ConnectionStatus.awaitingApproval);

      case 'auth_ok':
        // Two legitimate shapes. A reconnect has already proved itself with
        // its saved key and the PC sends this without asking anyone, so it is
        // accepted from `handshaking`. A first pairing is holding a
        // single-use token, so the prompt is the entire point and an `auth_ok`
        // that skipped it is ignored - that is exactly what an impostor would
        // send.
        if (_status == ConnectionStatus.awaitingApproval) {
          return _moveTo(
            ConnectionStatus.connected,
            deviceId: message['deviceId'] as String?,
            deviceKey: message['deviceKey'] as String?,
          );
        }
        if (_status == ConnectionStatus.handshaking && _usedSavedKey) {
          return _moveTo(
            ConnectionStatus.connected,
            deviceId: message['deviceId'] as String?,
          );
        }
        return const Ignore();

      case 'auth_err':
      case 'error':
        return _reject(message);

      case 'revoked':
        // Handled here as well as on the connected path: the companion can
        // revoke a device while it is still pairing, and ignoring that would
        // leave the app retrying with a key that can never work again.
        _status = ConnectionStatus.revoked;
        return const AdvanceTo(ConnectionStatus.revoked);

      case 'denied':
        _status = ConnectionStatus.denied;
        return const AdvanceTo(ConnectionStatus.denied);

      default:
        return const Ignore();
    }
  }

  /// A frame received while connected, rather than during pairing.
  HandshakeOutcome handleConnected(String raw) {
    final Map<String, Object?> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const Ignore();
      message = decoded;
    } on FormatException {
      return const Ignore();
    }

    switch (message['t']) {
      case 'denied':
        _status = ConnectionStatus.denied;
        return const AdvanceTo(ConnectionStatus.denied);

      case 'revoked':
        // The PC has forgotten us. The stored key is dead and must go, or
        // every reconnect would try to reuse it.
        _status = ConnectionStatus.revoked;
        return const AdvanceTo(ConnectionStatus.revoked);

      case 'disconnect':
        _status = ConnectionStatus.reconnecting;
        return const AdvanceTo(ConnectionStatus.reconnecting);

      default:
        return const Ignore();
    }
  }

  /// The PC asked us to stop. Sent back before dropping the socket so the
  /// desktop knows to release anything held, rather than waiting for a
  /// timeout to notice we vanished.
  List<String> goodbyeFrames() => <String>[
        encode(<String, Object?>{'t': 'bye'}),
      ];

  /// The socket went away.
///
/// Lives here rather than in the session so the machine's own status is the
/// single source of truth. When this was done in the session instead, the
/// delegate was told "reconnecting" while the machine still believed it was
/// connected - so input was accepted and written to a dead socket.
AdvanceTo handleDrop() {
  return _moveTo(
    _status.canRetryAfterDrop ? ConnectionStatus.reconnecting : ConnectionStatus.idle,
  );
}

HandshakeOutcome _reject(Map<String, Object?> message) {
    final code = message['code'] as String?;
    switch (code) {
      case 'E_DENIED':
        _status = ConnectionStatus.denied;
        return const AdvanceTo(
          ConnectionStatus.denied,
          error: 'The person at the computer said no.',
        );
      case 'E_BAD_TOKEN':
        // The QR code is spent or was never valid. Retrying with it cannot
        // work, so this is terminal and the user needs a new code.
        _status = ConnectionStatus.failed;
        return const AdvanceTo(
          ConnectionStatus.failed,
          error: 'That pairing code has expired. Scan the code on screen again.',
        );
      case 'E_REVOKED':
        _status = ConnectionStatus.revoked;
        return const AdvanceTo(ConnectionStatus.revoked);
      default:
        _status = ConnectionStatus.failed;
        return const AdvanceTo(
          ConnectionStatus.failed,
          error: 'The computer refused the connection.',
        );
    }
  }

  AdvanceTo _moveTo(
    ConnectionStatus status, {
    String? pcName,
    String? deviceId,
    String? deviceKey,
    String? error,
  }) {
    _status = status;
    return AdvanceTo(status, pcName: pcName, deviceId: deviceId, deviceKey: deviceKey, error: error);
  }
}

/// Encode a frame exactly as it goes on the wire.
String encode(Map<String, Object?> message) => jsonEncode(message);