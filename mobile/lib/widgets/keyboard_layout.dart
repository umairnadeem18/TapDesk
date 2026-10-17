import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../transport/tapdesk_event.dart';

/// The on-screen keyboard.
///
/// Plan tasks 3.4.1 to 3.4.4. Printable characters go out as `text`, never as
/// `key`: one Unicode code point per character means Urdu, emoji and accents
/// all work without a character table on the PC side, which is the whole
/// reason the protocol has a text message at all.
class KeyboardLayout {
  const KeyboardLayout._();

  /// Number row.
  ///
  /// Every entry is a key ID, never a glyph. An earlier version ended this row
  /// with the '⌫' glyph, which is not a protocol key id and not a printable
  /// character either, so Backspace silently typed a backspace symbol instead
  /// of deleting.
  static const List<String> numberRow = [
    '`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 'backspace',
  ];

  /// QWERTY. Space is handled separately - it spans the width.
  static const List<String> topRow = [
    'tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\',
  ];

  static const List<String> homeRow = [
    'caps', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", 'enter',
  ];

  static const List<String> bottomRow = [
    'shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 'shift',
  ];

  static const List<String> spaceRow = ['ctrl', 'alt', 'win', 'space', 'fn'];

  /// What each non-character key is called on screen. Keys not in this map are
  /// rendered as themselves, which covers every printable character.
  static const Map<String, String> labels = {
    'backspace': '⌫',
    'tab': 'Tab',
    'caps': 'Caps',
    'enter': '↵',
    'shift': 'Shift',
    'ctrl': 'Ctrl',
    'alt': 'Alt',
    'win': 'Win',
    'space': ' ',
    'fn': 'Fn',
  };

  /// Keys that are modifiers rather than characters.
  static const Set<String> modifiers = {
    ProtocolKey.shift,
    ProtocolKey.ctrl,
    ProtocolKey.alt,
    ProtocolKey.win,
  };

  /// Shortcuts offered on their own row, so the common ones are one tap.
  static const List<({String label, List<String> combo})> shortcuts = [
    (label: 'Copy', combo: ['ctrl', 'c']),
    (label: 'Paste', combo: ['ctrl', 'v']),
    (label: 'Undo', combo: ['ctrl', 'z']),
    (label: 'Save', combo: ['ctrl', 's']),
    (label: 'Alt+Tab', combo: ['alt', 'tab']),
    (label: 'Show desktop', combo: ['win', 'd']),
  ];

  static const List<String> arrows = ['left', 'up', 'down', 'right'];

  static List<String> get functionKeys => ProtocolKey.functionKeys;

  /// The visible label for a key id.
  static String label(String key) => labels[key] ?? key.toUpperCase();

  /// Map a physical key id to the protocol id for a character.
  ///
  /// Punctuation has protocol ids of its own, so `,` is `comma` rather than
  /// the literal character. Getting this wrong means the companion drops the
  /// key with E_BAD_FIELD and the key silently does nothing.
  static String? characterToKeyId(String character) {
    const punctuation = {
      '-': ProtocolKey.minus,
      '=': ProtocolKey.equal,
      '[': ProtocolKey.lbracket,
      ']': ProtocolKey.rbracket,
      '\\': ProtocolKey.backslash,
      ';': ProtocolKey.semicolon,
      "'": ProtocolKey.apostrophe,
      ',': ProtocolKey.comma,
      '.': ProtocolKey.period,
      '/': ProtocolKey.slash,
      '`': ProtocolKey.grave,
    };
    if (punctuation.containsKey(character)) return punctuation[character];

    final lower = character.toLowerCase();
    if (lower.length == 1 && lower.codeUnitAt(0) >= 97 && lower.codeUnitAt(0) <= 122) {
      return lower;
    }
    if (character.length == 1 && character.codeUnitAt(0) >= 48 && character.codeUnitAt(0) <= 57) {
      return character;
    }
    return null;
  }
}

/// The letters currently latched by a sticky modifier.
///
/// A separate object from the widget so its behaviour can be tested without a
/// finger: tapping Ctrl then C must send Ctrl+C, which is plan task 3.4.4 and
/// the single most error-prone thing in this screen.
class StickyModifiers {
  final Set<String> _latched = {};

  Set<String> get latched => Set.unmodifiable(_latched);
  bool isLatched(String key) => _latched.contains(key);
  bool get isEmpty => _latched.isEmpty;

  /// Toggle one. Returns true if it is now latched.
  bool toggle(String key) {
    if (!KeyboardLayout.modifiers.contains(key)) {
      throw ArgumentError('$key is not a modifier');
    }
    final added = _latched.remove(key);
    if (!added) _latched.add(key);
    return _latched.contains(key);
  }

  /// Consume the latch: take the held modifiers and clear them.
  ///
  /// Cleared after use so Ctrl, C, Ctrl, V means copy then paste, rather than
  /// leaving Ctrl stuck down for the rest of the session.
  List<String> consume() {
    if (_latched.isEmpty) return const [];
    final held = _latched.toList();
    _latched.clear();
    return held;
  }

  void clear() => _latched.clear();
}

/// One key on the grid.
class KeyCap extends StatelessWidget {
  const KeyCap({
    super.key,
    required this.label,
    required this.onPressed,
    this.widthFactor = 1,
    this.active = false,
    this.dense = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback onPressed;

  /// Relative width within its row, so Backspace and Enter can be wider.
  final double widthFactor;

  /// Modifier currently latched. Latched keys are filled, not just outlined -
  /// the only way to see a sticky modifier is to see it lit.
  final bool active;

  /// Smaller type for the rows that pack more keys in.
  final bool dense;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: Material(
        color: active ? TapDeskColors.primary : TapDeskColors.surfaceElevated,
        borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
        child: InkWell(
          borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
          onTap: onPressed,
          child: Container(
            height: TapDeskSpace.minTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
              border: Border.all(
                color: active ? TapDeskColors.primary : TapDeskColors.divider,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TapDeskSpace.s1),
                child: Text(
                  label,
                  style: (dense ? TapDeskText.label : TapDeskText.keyLabel)
                      .copyWith(
                    color: active
                        ? TapDeskColors.text
                        : TapDeskColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
