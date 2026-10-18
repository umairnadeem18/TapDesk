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
///
/// It is a [ChangeNotifier] and that is load-bearing, not decoration. The tabs
/// are built once, while the phone is still waiting for the person at the PC to
/// tap Allow, so every control is built disabled. Nothing told them they were
/// stale afterwards: `context.watch<EventSink>()` on a plain object never
/// rebuilds, and an ancestor rebuilding with the same `const` children skips
/// their subtrees. Mouse and Keyboard stayed dead forever; Slides only looked
/// alive because its buttons still animate and buzz when disabled.
abstract class EventSink extends ChangeNotifier {
  /// Send one event. Returns false if it was dropped locally — for example
  /// because the app is not connected, or a rate limit was hit.
  bool send(TapDeskEvent event);

  /// Whether input is currently accepted.
  ///
  /// Screens check this to decide whether to disable themselves, so "never
  /// look broken" is enforced in one place rather than in every widget.
  ///
  /// Implementations must call [notifyListeners] whenever this flips. A control
  /// that stays disabled after the user has been told they are connected is
  /// the bug this note exists to prevent.
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
class RecordingEventSink extends EventSink {
  RecordingEventSink({bool isReady = false}) : _isReady = isReady;

  bool _isReady;

  /// Whether input is currently accepted. Mutable so a test can flip it the way
  /// `connected` would - and notifying here is what lets the tabs in front of
  /// it rebuild, which is the whole reason a real connection works at all.
  @override
  bool get isReady => _isReady;

  set isReady(bool value) {
    if (_isReady == value) return;
    _isReady = value;
    notifyListeners();
  }

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
