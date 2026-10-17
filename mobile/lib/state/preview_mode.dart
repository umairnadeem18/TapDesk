import 'package:flutter/foundation.dart';

/// Whether the app is showing the controller without a PC.
///
/// This exists because of a real problem found on a real device: the plan calls
/// for visual sign-off on the design *before* any transport work, but the
/// companion that shows a QR code is Phase 5. Gating every screen behind a
/// working connection made the design impossible to review - the reviewer could
/// not see Slides or Mouse at all.
///
/// In preview mode the controls are live and everything the user does is
/// recorded rather than sent, so a button can be judged on its size, colour and
/// placement without pretending anything is connected.
///
/// **Debug builds only.** [PreviewMode.isAllowed] is false in release, so this
/// can never appear in a build a user downloads. It is a development aid, not a
/// feature, and faking a connection to a real user would break the one rule the
/// design system cares most about: never look connected when you are not.
class PreviewMode extends ChangeNotifier {
  PreviewMode({bool? allowed}) : _allowed = allowed ?? isAvailable;

  /// Whether this build may enter preview. False in release, so the feature
  /// can never reach a user.
  static bool get isAvailable => kDebugMode;

  final bool _allowed;
  bool _active = false;

  bool get allowed => _allowed;
  bool get isActive => _active && _allowed;

  /// Turn preview on, if this build permits it. Returns false otherwise, so
  /// callers can treat it as a no-op rather than silently showing a dead
  /// button.
  bool enter() {
    if (!_allowed || _active) return false;
    _active = true;
    notifyListeners();
    return true;
  }

  void exit() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}
