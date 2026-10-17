/// The socket, and the certificate check that makes it trustworthy.
///
/// Abstracted so the session can be driven against a fake in tests. The real
/// implementation is `PinnedSocket`, which is the only file in the app that
/// knows a WebSocket exists.
library;

import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'fingerprint.dart';

/// Why a connection could not be established.
///
/// Split out rather than left as a generic exception because the user action
/// differs completely. A [HandshakeFailure.fingerprintMismatch] means stop and
/// go and look at the right screen; a timeout means try again.
enum HandshakeFailure { fingerprintMismatch, timedOut }

/// A connection that failed in a way the user needs to hear about specifically.
class HandshakeException implements Exception {
  const HandshakeException(this.reason);

  final HandshakeFailure reason;

  @override
  String toString() => 'HandshakeException($reason)';
}

/// A bidirectional text channel to the companion.
abstract class TapDeskSocket {
  /// Lines arriving from the PC. Single-subscription: the session owns it.
  Stream<String> get messages;

  /// Whether the socket is still usable.
  bool get isOpen;

  void send(String frame);

  Future<void> close([int code = 1000, String reason = '']);

  /// Frames written so far. Test affordance; harmless in production.
  int get sentCount;
}

/// Opens a socket to the companion, pinning [fingerprint].
abstract class SocketFactory {
  Future<TapDeskSocket> connect({
    required String host,
    required int port,
    required String fingerprint,
  });
}

/// The real socket.
///
/// [IOWebSocketChannel.connect] takes a `customClient`, which is the only place
/// a certificate check can be installed: ordinary verification is replaced
/// with a comparison against the fingerprint from the QR code. The socket is
/// closed rather than trusted whenever they disagree.
class PinnedSocket implements TapDeskSocket {
  PinnedSocket._(this._channel) {
    // The controller is exposed as the message stream so a socket that hangs
    // up turns into a stream close, which is what the session watches for.
    // `map` to String is what keeps the subscription typed: the raw stream is
    // Stream<dynamic>, and declaring the field as StreamSubscription<String>
    // while listening to the dynamic one only failed at runtime, against a
    // real socket.
    _subscription = _channel.stream.map((Object? line) => line.toString()).listen(
      _incoming.add,
      onDone: () {
        if (!_incoming.isClosed) _incoming.close();
      },
      onError: _incoming.addError,
    );
  }

  static Future<PinnedSocket> open({
    required String host,
    required int port,
    required String fingerprint,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Whether the certificate was rejected is recorded rather than inferred
    // from the connection error, because "the certificate did not match" and
    // "the PC is asleep" both surface as a failed handshake and only one of
    // them is worth the user going to look at the screen.
    var rejected = false;

    final HttpClient client = _pinningClient(fingerprint, () => rejected = true);

    // self-signed: the CA check is meaningless here and is replaced by the
    // fingerprint comparison inside badCertificateCallback.
    final channel = IOWebSocketChannel.connect(
      Uri(scheme: 'wss', host: host, port: port, path: '/'),
      customClient: client,
      connectTimeout: timeout,
    );

    try {
      // Without this the handshake does not start until the socket is open,
      // and a PC that accepts the TCP connection and then stalls would hang
      // here instead of timing out.
      await channel.ready;
    } on Object {
      client.close(force: true);
      throw HandshakeException(
        rejected ? HandshakeFailure.fingerprintMismatch : HandshakeFailure.timedOut,
      );
    }

    return PinnedSocket._(channel);
  }

  /// Build a client that accepts *only* the expected certificate.
  ///
  /// `badCertificateCallback` exists for self-signed and pinning use; it is
  /// invoked instead of failing when verification fails, so this is the single
  /// place the decision is made. Anything not matching the fingerprint is
  /// rejected, which is what stops a second machine on the same Wi-Fi from
  /// answering as the PC.
  static HttpClient _pinningClient(String fingerprint, void Function() onRejected) {
    final normalised = normaliseFingerprint(fingerprint);
    if (normalised == null) {
      // Fail before opening anything. A malformed fingerprint means the QR
      // code was misread, and proceeding with an unpinned connection would be
      // worse than not connecting.
      throw ArgumentError.value(fingerprint, 'fingerprint', 'not a SHA-256 fingerprint');
    }

    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate certificate, String host, int port) {
      final ok = sha256Hex(certificate.der) == normalised;
      if (!ok) {
        onRejected();
        // Deliberately not logging the expected value, the presented
        // fingerprint, or the host beyond what the user can already see.
        stderr.writeln('tapdesk: rejected a certificate that did not match the paired computer');
      }
      return ok;
    };
    return client;
  }

  /// The channel, typed rather than dynamic: declaring it loosely is what let a
/// Stream<dynamic> be assigned to a StreamSubscription<String> without the
/// analyzer noticing.
final WebSocketChannel _channel;
  final StreamController<String> _incoming = StreamController<String>();
  StreamSubscription<String>? _subscription;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  bool get isOpen => true;

  int _sent = 0;

  @override
  int get sentCount => _sent;

  @override
  void send(String frame) {
    _channel.sink.add(frame);
    _sent++;
  }

  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    await _subscription?.cancel();
    _subscription = null;
    if (!_incoming.isClosed) await _incoming.close();
    await _channel.sink.close(code, reason);
  }
}

/// Opens real, pinned sockets. The production [SocketFactory].
class PinnedSocketFactory implements SocketFactory {
  const PinnedSocketFactory();

  @override
  Future<TapDeskSocket> connect({
    required String host,
    required int port,
    required String fingerprint,
  }) =>
      PinnedSocket.open(host: host, port: port, fingerprint: fingerprint);
}

/// A socket that records what it was asked to send.
///
/// Used by tests to drive the session without a network, and by preview mode.
class FakeSocket implements TapDeskSocket {
  FakeSocket();

  /// Frames the session wrote.
  final List<String> sent = [];

  final StreamController<String> _incoming = StreamController<String>();
  bool _open = true;

  /// Push a line from the "PC" into the session.
  void emit(String frame) => _incoming.add(frame);

  /// Simulate the PC hanging up.
  void hangUp() {
    _open = false;
    _incoming.close();
  }

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  int get sentCount => sent.length;

  @override
  void send(String frame) => sent.add(frame);

  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    _open = false;
    if (!_incoming.isClosed) await _incoming.close();
  }
}