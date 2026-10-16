import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The TapDesk design tokens.
///
/// Every colour, size and duration here comes from `docs/design-system.md`.
/// Nothing in the app may hard-code a colour or a magic number — if a value is
/// needed that is not here, the design system is missing it and must be
/// updated first. That rule is what keeps the Flutter app and the Python
/// companion looking like the same product.
class TapDeskColors {
  const TapDeskColors._();

  /// Screen background.
  static const Color background = Color(0xFF0A0A0A);

  /// Cards, tab bar, sheets.
  static const Color surface = Color(0xFF171717);

  /// Keys, pressed states, inputs.
  static const Color surfaceElevated = Color(0xFF1F1F1F);

  /// Buttons, button borders, active tab pill, focus rings.
  ///
  /// Green is reserved: an element is green when it is active, enabled or
  /// connected, and never merely decorative.
  static const Color primary = Color(0xFF16A34A);

  /// Pressed buttons.
  static const Color primaryPressed = Color(0xFF15803D);

  /// Active accents, connection-dot glow, slider fill.
  static const Color highlight = Color(0xFF86EFAC);

  /// Labels and headings.
  static const Color text = Color(0xFFFAFAFA);

  /// Secondary labels, hints, disabled labels.
  static const Color textMuted = Color(0xFF9CA3AF);

  /// Disconnected state, validation errors.
  static const Color error = Color(0xFFDC2626);

  /// Safe Mode notices, warnings.
  static const Color warning = Color(0xFFF59E0B);

  /// 1 px separators.
  static const Color divider = Color(0xFF262626);
}

/// Spacing, radius and sizing tokens, from the same document.
class TapDeskSpace {
  const TapDeskSpace._();

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;

  static const double radiusCard = 16;
  static const double radiusKey = 10;

  /// Buttons are fully rounded pills.
  static const double radiusPill = 999;

  static const double borderWidth = 2;

  /// The minimum hit area for anything tappable. Binding, not a guideline —
  /// see the accessibility section of the design system.
  static const double minTouchTarget = 56;
}

/// Motion durations, from the design system.
class TapDeskDuration {
  const TapDeskDuration._();

  static const Duration tabChange = Duration(milliseconds: 150);
  static const Duration press = Duration(milliseconds: 80);
  static const Duration banner = Duration(milliseconds: 200);

  /// The connection dot pulses at 1 Hz while reconnecting.
  static const Duration pulse = Duration(milliseconds: 1000);

  /// Stick events are sent at 60 Hz, so the UI never eases the knob.
  static const Duration stickTick = Duration(milliseconds: 16);
}

/// Typography roles, from the design system.
///
/// Fonts are bundled assets rather than fetched, because the app is often
/// used on a network with no internet access.
class TapDeskText {
  const TapDeskText._();

  static const String heading = 'Poppins';
  static const String body = 'Inter';
  static const String mono = 'JetBrainsMono';

  static const TextStyle display = TextStyle(
    fontFamily: heading,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: TapDeskColors.text,
  );

  static const TextStyle keyLabel = TextStyle(
    fontFamily: body,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: TapDeskColors.text,
  );

  static const TextStyle button = TextStyle(
    fontFamily: body,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: TapDeskColors.text,
  );

  static const TextStyle bodyText = TextStyle(
    fontFamily: body,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: TapDeskColors.text,
  );

  static const TextStyle label = TextStyle(
    fontFamily: body,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: TapDeskColors.textMuted,
  );

  static const TextStyle monoText = TextStyle(
    fontFamily: mono,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: TapDeskColors.textMuted,
  );
}

/// The app's single dark theme.
///
/// Dark only, on purpose: the app is used in lecture halls where a white screen
/// is blinding from the back rows. There is no light theme and no toggle.
class TapDeskTheme {
  const TapDeskTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: TapDeskColors.background,
      canvasColor: TapDeskColors.background,
      colorScheme: const ColorScheme.dark(
        primary: TapDeskColors.primary,
        onPrimary: TapDeskColors.text,
        secondary: TapDeskColors.highlight,
        onSecondary: TapDeskColors.background,
        surface: TapDeskColors.surface,
        onSurface: TapDeskColors.text,
        error: TapDeskColors.error,
        onError: TapDeskColors.text,
        outline: TapDeskColors.divider,
      ),
      dividerColor: TapDeskColors.divider,
      splashColor: TapDeskColors.primary.withValues(alpha: 0.12),
      highlightColor: TapDeskColors.primary.withValues(alpha: 0.08),

      textTheme: base.textTheme.apply(
        fontFamily: TapDeskText.body,
        bodyColor: TapDeskColors.text,
        displayColor: TapDeskColors.text,
      ),

      // Focus rings must be visible: the app is used in the dark, often one
      // handed, and a keyboard user must be able to see where they are.
      focusColor: TapDeskColors.primary.withValues(alpha: 0.35),

      iconTheme: const IconThemeData(color: TapDeskColors.textMuted, size: 24),

      // Nothing should ever be the default Material blue.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TapDeskColors.text
              : TapDeskColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TapDeskColors.primary
              : TapDeskColors.surfaceElevated,
        ),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(TapDeskColors.primary),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: TapDeskColors.highlight,
        inactiveTrackColor: TapDeskColors.divider,
        thumbColor: TapDeskColors.highlight,
        overlayColor: Color(0x3316A34A),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: TapDeskColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: TapDeskColors.surfaceElevated,
        contentTextStyle: TextStyle(
          fontFamily: TapDeskText.body,
          color: TapDeskColors.text,
        ),
        behavior: SnackBarBehavior.floating,
      ),

      dialogTheme: const DialogThemeData(
        backgroundColor: TapDeskColors.surface,
        surfaceTintColor: Colors.transparent,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TapDeskColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  /// System chrome to match: light icons on the dark background.
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: TapDeskColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
