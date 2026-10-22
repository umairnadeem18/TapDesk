import 'dart:async';

import 'package:flutter/foundation.dart';

/// The phone's connection states, from `docs/protocol.md` section 3.5.
///
/// The names and the transitions between them are part of the contract with the
/// companion. `connected` is the only state in which the UI enables controls —
/// everything else must show a clear banner instead of looking broken.
enum ConnectionStatus {
  /// Nothing attempted yet; the app opens on the pairing screen.
  idle,

  /// TCP/TLS is being established.
  connecting,

  /// `hello` sent, waiting for `hello_ok`.
  handshaking,

  /// `auth_pending` received; the user must approve on the PC.
  awaitingApproval,

  /// `auth_ok` received. The only state where input is sent.
  connected,

  /// Lost the socket; retrying with backoff.
  reconnecting,

  /// The PC revoked this device. The stored key must be deleted.
  revoked,

  /// The user pressed Deny on the PC.
  denied,

  /// The server refused us for a reason that will not fix itself on retry.
  failed,
}

extension ConnectionStatusX on ConnectionStatus {
  /// Whether input may be sent to the PC right now.
  bool get isConnected => this == ConnectionStatus.connected;

  /// Whether the app should keep retrying on its own. `revoked`, `denied` and
  /// `failed` are terminal — retrying would either loop forever or hammer a
  /// server that has already said no.
  bool get isRetryable =>
      this == ConnectionStatus.connecting ||
      this == ConnectionStatus.handshaking ||
      this == ConnectionStatus.reconnecting;

  /// Whether losing the socket from this state is worth reconnecting.
  ///
  /// Deliberately wider than [isRetryable]. That one means "a scheduled retry
  /// is still in progress"; this one asks "would trying again stand a chance",
  /// and the commonest case by far is the socket dropping while
  /// [ConnectionStatus.connected] - a phone leaving Wi-Fi range, a laptop
  /// sleeping. Treating that as terminal would mean the user had to pair again
  /// every time the connection flickered.
  ///
  /// The states it excludes all need something from the user before another
  /// attempt could differ: there was nothing to reconnect to, or the attempt
  /// failed in a way that only a fresh scan or a new decision can change.
  bool get canRetryAfterDrop => switch (this) {
        ConnectionStatus.idle => false,
        ConnectionStatus.denied => false,
        ConnectionStatus.revoked => false,
        ConnectionStatus.failed => false,
        _ => true,
      };

  /// Colour of the connection dot in the app bar.
  ///
  /// Green only ever means connected, per the design system.
  String get label => switch (this) {
        ConnectionStatus.idle => 'Not connected',
        ConnectionStatus.connecting => 'Connecting',
        ConnectionStatus.handshaking => 'Connecting',
        ConnectionStatus.awaitingApproval => 'Waiting for approval',
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.reconnecting => 'Reconnecting',
        ConnectionStatus.revoked => 'Revoked by PC',
        ConnectionStatus.denied => 'Denied by PC',
        ConnectionStatus.failed => 'Connection failed',
      };

  /// Text for the banner shown under the tab bar. Null means no banner — the
  /// app opens on the pairing screen, which explains itself already.
  String? get bannerText => switch (this) {
        ConnectionStatus.idle => null,
        ConnectionStatus.connecting => 'Connecting',
        ConnectionStatus.handshaking => 'Connecting',
        ConnectionStatus.awaitingApproval => 'Waiting for approval on the PC',
        ConnectionStatus.reconnecting => 'Reconnecting',
        ConnectionStatus.revoked => 'This device was revoked on the PC',
        ConnectionStatus.denied => 'The PC declined this connection',
        ConnectionStatus.failed => 'Could not connect',
        ConnectionStatus.connected => null,
      };
}

/// Immutable snapshot of the connection, handed to the UI.
///
/// A plain value object rather than reading mutable fields during build, so
/// widgets rebuild only when something they care about actually changed.
@immutable
class ConnectionInfo {
  const ConnectionInfo({
    this.status = ConnectionStatus.idle,
    this.pcName,
    this.paired = false,
    this.latencyMs,
    this.lastError,
  });

  final ConnectionStatus status;

  /// Display name of the paired PC, shown in the app bar.
  final String? pcName;

  /// Whether we hold a device key for this PC, i.e. we can reconnect without
  /// scanning again.
  final bool paired;

  /// Round-trip latency from the last ping, shown in settings.
  final int? latencyMs;

  /// Human-readable reason for the last failure, shown in the banner.
  final String? lastError;

  /// Sentinel for "argument not supplied".
  ///
  /// A plain `?? this.field` in [copyWith] can never set a field back to null,
  /// which is exactly what clearing a stale error message requires.
  static const Object _unset = Object();

  ConnectionInfo copyWith({
    ConnectionStatus? status,
    Object? pcName = _unset,
    bool? paired,
    Object? latencyMs = _unset,
    Object? lastError = _unset,
  }) {
    return ConnectionInfo(
      status: status ?? this.status,
      pcName: identical(pcName, _unset) ? this.pcName : pcName as String?,
      paired: paired ?? this.paired,
      latencyMs: identical(latencyMs, _unset) ? this.latencyMs : latencyMs as int?,
      lastError:
          identical(lastError, _unset) ? this.lastError : lastError as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionInfo &&
      other.status == status &&
      other.pcName == pcName &&
      other.paired == paired &&
      other.latencyMs == latencyMs &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(status, pcName, paired, latencyMs, lastError);
}

/// Holds the connection state and drives the UI.
///
/// This is deliberately a shell in Phase 2: it owns state transitions and the
/// backoff timer, but the socket itself arrives in Phase 4. Keeping the state
/// machine here — rather than inside the future transport class — means the
/// app shell can be built and signed off on now, before any networking exists.
class ConnectionController extends ChangeNotifier {
  ConnectionController({BackoffPolicy? backoff})
      : _backoff = backoff ?? const BackoffPolicy();

  final BackoffPolicy _backoff;
  ConnectionInfo _info = const ConnectionInfo();

  ConnectionInfo get info => _info;

  int _attempt = 0;
  int _retryMs = 0;
  Timer? _retryTimer;

  void update(ConnectionInfo next) {
    // While the reconnect loop owns the wait, a reason already on record
    // survives a reason-less snapshot. The transport reports the status and
    // the reason separately, and a second drop arriving mid-loop used to
    // overwrite the stored reason with null - the banner blinking back to a
    // bare "Reconnecting" with nothing about why.
    final merged =
        next.status == ConnectionStatus.reconnecting &&
            _info.status == ConnectionStatus.reconnecting &&
            next.lastError == null &&
            _info.lastError != null
        ? next.copyWith(lastError: _info.lastError)
        : next;

    if (merged == _info) return;
    _info = merged;
    notifyListeners();
  }

  /// Move to a new state.
  ///
  /// Reaching [ConnectionStatus.connected] resets the reconnect backoff, so a
  /// session that recovers once starts its next drop from 1s rather than
  /// inheriting a long delay from an earlier outage.
  void goTo(ConnectionStatus status, {String? error}) {
    _retryTimer?.cancel();
    _retryTimer = null;

    if (status == ConnectionStatus.connected) {
      _attempt = 0;
      _retryMs = 0;
    }

    // A reconnecting transition keeps the reason the last attempt failed:
    // it is scheduled immediately after that failure was reported, and
    // wiping the message here made the banner alternate between the reason
    // and a bare "Reconnecting" every time the wait was set. Every other
    // state clears it - a fresh attempt starts clean and earns its reason
    // again if it fails too.
    final reason = error ??
        (status == ConnectionStatus.reconnecting ? _info.lastError : null);

    update(_info.copyWith(
      status: status,
      // Always cleared unless a caller supplies a new message: a stale error
      // shown beside a connecting spinner reads as a live failure.
      lastError: reason,
      pcName: status == ConnectionStatus.revoked ? null : _info.pcName,
    ));
  }

  /// Backoff sequence from the protocol: 1s, 2s, 4s, 8s, then 10s forever.
  /// The delay most recently scheduled by [scheduleReconnect].
  ///
  /// This is the delay the reconnect timer is actually running on, which is
  /// what tests and diagnostics want to see — not the delay the *next* attempt
  /// would use.
  int get currentRetryDelayMs => _retryMs;

  /// Re-dials the socket. Supplied by the transport, because only it knows how
  /// to open a connection; the controller owns *when*, not *how*.
  ///
  /// This was the missing half of reconnecting. The timer below used to fire
  /// and set the status to `connecting`, which showed a spinner forever: the
  /// label said connecting while nothing was actually dialling the PC. The
  /// symptom - "it says connecting and never stabilises" - was really the app
  /// politely lying about work it had stopped doing.
  Future<void> Function()? onRetry;

  /// Schedule the next reconnect attempt and move to `reconnecting`.
  void scheduleReconnect() {
    _retryMs = _backoff.delayFor(_attempt);
    _attempt++;
    goTo(ConnectionStatus.reconnecting);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: _retryMs), () async {
      goTo(ConnectionStatus.connecting);
      try {
        await onRetry?.call();
      } catch (error) {
        // The attempt itself failed rather than reporting a drop. Ask for
        // another one, or the app sits in `connecting` forever - which is the
        // same bug from the other direction.
        scheduleReconnect();
      }
    });
  }

  /// Retry immediately, skipping the remaining backoff.
  ///
  /// Used when the app comes back to the foreground. Waiting out a 10 second
  /// backoff after the user has unlocked their phone looks broken, and the
  /// delay exists for a loop, not for one deliberate attempt.
  ///
  /// Fires only while the backoff owns the wait — a status of `reconnecting`.
  /// An attempt still in flight (`connecting`, `handshaking`,
  /// `awaitingApproval`) must not be interrupted: the retry tears the session
  /// down underneath the dial and re-runs it, which at pairing time burns the
  /// single-use token and turns one perfectly good scan into a pairing that
  /// can never finish.
  void retryNow() {
    if (_info.status != ConnectionStatus.reconnecting) return;
    _attempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    goTo(ConnectionStatus.connecting);
    unawaited(_runRetry());
  }

  Future<void> _runRetry() async {
    try {
      await onRetry?.call();
    } catch (_) {
      scheduleReconnect();
    }
  }

  /// Called by the transport when a connection is established.
  void onConnected({String? pcName}) {
    _attempt = 0;
    _retryMs = 0;
    _retryTimer?.cancel();
    _retryTimer = null;

    update(_info.copyWith(
      status: ConnectionStatus.connected,
      pcName: pcName ?? _info.pcName,
      paired: true,
      lastError: null,
    ));
  }

  /// Called by the transport when the socket closes unexpectedly.
  void onDropped() => scheduleReconnect();

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

/// The reconnect backoff, as a value so it can be unit tested.
class BackoffPolicy {
  const BackoffPolicy({
    this.stepsMs = const [1000, 2000, 4000, 8000],
    this.maxMs = 10000,
  });

  final List<int> stepsMs;
  final int maxMs;

  /// Delay for attempt number [attempt], counting from zero.
  int delayFor(int attempt) {
    if (attempt < stepsMs.length) return stepsMs[attempt];
    return maxMs;
  }
}
