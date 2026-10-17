import 'dart:convert';

/// Canonical key ids from `docs/protocol.md` section 4.3.
///
/// This is the single naming table shared with the Python companion. If a key
/// is not in here it does not exist on the wire — inventing an id locally is
/// exactly how the two implementations drift apart.
class ProtocolKey {
  const ProtocolKey._();

  // Letters and digits are their own ids.
  static String letter(String l) => l.toLowerCase();
  static String digit(int d) => '$d';

  // Arrows
  static const String up = 'up';
  static const String down = 'down';
  static const String left = 'left';
  static const String right = 'right';

  // Editing
  static const String enter = 'enter';
  static const String tab = 'tab';
  static const String backspace = 'backspace';
  static const String delete = 'delete';
  static const String insert = 'insert';
  static const String esc = 'esc';
  static const String space = 'space';

  // Modifiers
  static const String shift = 'shift';
  static const String ctrl = 'ctrl';
  static const String alt = 'alt';
  static const String win = 'win';

  // Locks
  static const String capslock = 'capslock';
  static const String numlock = 'numlock';
  static const String scrolllock = 'scrolllock';

  // Navigation
  static const String home = 'home';
  static const String end = 'end';
  static const String pgup = 'pgup';
  static const String pgdn = 'pgdn';

  // Punctuation
  static const String minus = 'minus';
  static const String equal = 'equal';
  static const String lbracket = 'lbracket';
  static const String rbracket = 'rbracket';
  static const String backslash = 'backslash';
  static const String semicolon = 'semicolon';
  static const String apostrophe = 'apostrophe';
  static const String grave = 'grave';
  static const String comma = 'comma';
  static const String period = 'period';
  static const String slash = 'slash';

  // Function keys. Generated rather than twelve constants, so the keyboard
  // layout cannot end up with an F11 it never declared.
  static String functionKey(int n) {
    assert(n >= 1 && n <= 12, 'function keys run f1..f12');
    return 'f$n';
  }

  static List<String> get functionKeys =>
      List.generate(12, (i) => functionKey(i + 1), growable: false);

  // Other
  static const String printscreen = 'printscreen';
  static const String pause = 'pause';
  static const String menu = 'menu';

  /// Every valid id, for validating before sending. The companion drops
  /// anything outside this set with `E_BAD_FIELD`; checking here saves the
  /// round trip and lets the UI fail visibly in development.
  static final Set<String> all = {
    ...'abcdefghijklmnopqrstuvwxyz'.split(''),
    ...'0123456789'.split(''),
    'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
    up, down, left, right,
    enter, tab, backspace, delete, insert, esc, space,
    shift, ctrl, alt, win,
    capslock, numlock, scrolllock,
    home, end, pgup, pgdn,
    minus, equal, lbracket, rbracket, backslash, semicolon, apostrophe, grave,
    comma, period, slash,
    printscreen, pause, menu,
  };

  /// Modifiers, for sticky-key handling and the Safe Mode allow list.
  static const Set<String> modifiers = {shift, ctrl, alt, win};
}

/// One message to send to the PC.
///
/// Modelled as a sealed hierarchy so the set of things the app can send is
/// closed at compile time. Adding a case here is a deliberate act; adding a
/// field to the wrong case is a compile error.
sealed class TapDeskEvent {
  const TapDeskEvent();

  /// The wire representation: one JSON object per frame, no newline.
  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  /// `t` for each event, matching the protocol catalogue exactly.
  String get type;
}

class StickEvent extends TapDeskEvent {
  const StickEvent(this.x, this.y)
      : assert(x >= -1 && x <= 1, 'x must be in -1..1'),
        assert(y >= -1 && y <= 1, 'y must be in -1..1');

  /// -1..1, +y is up.
  final double x;
  final double y;

  @override
  String get type => 'stick';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'x': x, 'y': y};
}

class MoveEvent extends TapDeskEvent {
  const MoveEvent(this.dx, this.dy);

  /// Relative pixels, -y is up.
  final int dx;
  final int dy;

  @override
  String get type => 'move';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'dx': dx, 'dy': dy};
}

class ClickEvent extends TapDeskEvent {
  const ClickEvent(this.button, this.action);

  final String button; // left | right | middle
  final String action; // down | up | click | double

  @override
  String get type => 'click';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'b': button, 'a': action};
}

class ScrollEvent extends TapDeskEvent {
  const ScrollEvent(this.dy);

  /// Ticks. Positive scrolls up, away from the user.
  final int dy;

  @override
  String get type => 'scroll';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'dy': dy};
}

class KeyEvent extends TapDeskEvent {
  const KeyEvent(this.key, this.action);

  final String key; // must be in ProtocolKey.all
  final String action; // press | release | tap

  @override
  String get type => 'key';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'k': key, 'a': action};
}

/// A chord of 1 to 4 keys pressed together.
///
/// Deliberately **not** `const`: the bounds check below reads `keys.length`,
/// which a const constructor cannot do. Making it const would mean dropping the
/// check, and an over-long chord is silently ignored by the companion.
class ComboEvent extends TapDeskEvent {
  ComboEvent(this.keys)
      : assert(keys.isNotEmpty && keys.length <= 4, '1..4 keys per chord');

  final List<String> keys;

  @override
  String get type => 'combo';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'keys': keys};
}

class TextEvent extends TapDeskEvent {
  const TextEvent(this.text);

  /// Unicode text for injection. The companion caps the length at 500 chars.
  final String text;

  @override
  String get type => 'text';

  @override
  Map<String, dynamic> toJson() => {'t': type, 's': text};
}

class SlideEvent extends TapDeskEvent {
  const SlideEvent(this.action);

  /// next | prev | start | end | blank
  final String action;

  @override
  String get type => 'slide';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'a': action};
}

class PingEvent extends TapDeskEvent {
  const PingEvent(this.timestampMs);

  final int timestampMs;

  @override
  String get type => 'ping';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'ts': timestampMs};
}

/// Slide actions, named so a typo is a compile error rather than a silently
/// dropped message.
class SlideAction {
  const SlideAction._();

  static const String next = 'next';
  static const String prev = 'prev';
  static const String start = 'start';
  static const String end = 'end';
  static const String blank = 'blank';
}

/// Mouse buttons.
class MouseButton {
  const MouseButton._();

  static const String left = 'left';
  static const String right = 'right';
  static const String middle = 'middle';
}

/// Click actions. `down` then `up` gives a drag.
class ClickAction {
  const ClickAction._();

  static const String down = 'down';
  static const String up = 'up';
  static const String click = 'click';
  static const String double = 'double';
}
