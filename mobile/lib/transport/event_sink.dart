import 'package:flutter/foundation.dart';

import 'tapdesk_event.dart';

/// Where events go.
///
/// The screens in Phase 3 are written against this interface, not against a
/// socket. That separation is what let the whole UI be built and reviewed while
/// no networking existed yet, and it is what makes the UI testable without a
/// PC anywhere in sight.
///
/// Phase 4 supplies the real implementation, which also owns certificate
/// pinning and the reconnect state machine. Nothing in `screens/` or `ui/`
/// should ever import a WebSocket directly.
abstract class EventSink {
  /// Send one event. Returns false if it was dropped locally — for example
  /// because the app is not connected, or a rate limit was hit.
  bool send(TapDeskEvent event);

  /// Whether input is currently accepted.
  ///
  /// Screens check this to decide whether to disable themselves, so "never
  /// look broken" is enforced in one place rather than in every widget.
  bool get isReady;

  /// Monotonic counter of events actually put on the wire. Used by tests and
  /// by the settings screen's diagnostics.
  int get sentCount;
}

/// The Phase 3 implementation: records events instead of sending them.
///
/// This is deliberate, not a stub left behind. Until Phase 4 exists there is
/// nothing to send to, and a no-op would make it impossible to tell a working
/// button from a dead one. Recording every event means the UI can be driven
/// and asserted in tests, and it makes the eventual transport swap a
/// one-line change in `main.dart`.
class RecordingEventSink implements EventSink {
  RecordingEventSink({this.isReady = false});

  /// Whether input is currently accepted. Mutable so a test or a future
  /// connection can flip it the way `connected` would.
  @override
  bool isReady;

  int _sentCount = 0;
  final List<TapDeskEvent> _events = [];

  /// Everything sent so far, oldest first.
  List<TapDeskEvent> get events => List.unmodifiable(_events);

  /// The encoded frames, exactly as they would go on the wire. Asserting on
  /// these is how we prove the app agrees with `docs/protocol.md`.
  List<String> get frames => _events.map((e) => e.encode()).toList();

  @override
  int get sentCount => _sentCount;

  @override
  bool send(TapDeskEvent event) {
    if (!isReady) return false;
    _events.add(event);
    _sentCount++;
    if (kDebugMode) {
      debugPrint('[tapdesk] ${event.encode()}');
    }
    return true;
  }

  void clear() {
    _events.clear();
    _sentCount = 0;
  }
}
