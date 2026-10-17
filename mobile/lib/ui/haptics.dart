import 'package:flutter/services.dart';

/// Haptic feedback, in one place.
///
/// `docs/design-system.md` requires haptics on every Slides and Mouse press,
/// and requires the user to be able to switch them off. Centralising it here
/// means every screen calls the same two functions, so "haptics off" is
/// honoured everywhere without each widget remembering to check.
///
/// This uses Flutter's built-in [HapticFeedback] rather than a plugin. The
/// `vibration` package hard-codes `compileSdkVersion 33` and applies AGP 7.4.0,
/// which cannot build inside a project on AGP 9.1.0 — it failed with 15 AAR
/// metadata errors. The built-in API covers light, medium and heavy impact,
/// which is everything the design system asks for.
///
/// Swapping this file for a plugin later is a one-file change.
class Haptics {
  const Haptics._();

  /// User preference, mirrored from Settings in Phase 3.5. Defaults to on,
  /// because a miss on a slide button is worse than a buzz.
  static bool enabled = true;

  /// A tap on a control: previous/next slide, a mouse button, a key.
  static Future<void> tap() async {
    if (!enabled) return;
    await HapticFeedback.lightImpact();
  }

  /// A press that changes something bigger: entering pairing, allowing a
  /// device, latching a sticky modifier.
  static Future<void> confirm() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// A refusal: an invalid action, or Safe Mode blocking a shortcut.
  ///
  /// A double heavy impact reads as "no" without adding a visual alert that
  /// would compete with the banner.
  static Future<void> reject() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
    await HapticFeedback.heavyImpact();
  }
}
