import 'package:flutter/material.dart' hide KeyEvent;
import 'package:provider/provider.dart';

import '../theme/tokens.dart';
import '../transport/event_sink.dart';
import '../transport/tapdesk_event.dart';
import '../ui/haptics.dart';
import '../widgets/keyboard_layout.dart';

/// The Keyboard tab.
///
/// The one screen where a mistake is most annoying: a wrong key id is dropped
/// silently by the companion, so the key appears dead and the user blames the
/// app rather than the code. Every printable key therefore goes out as `text`,
/// which needs no table on the PC side, and only named keys use `key`.
class KeyboardTab extends StatefulWidget {
  const KeyboardTab({super.key});

  @override
  State<KeyboardTab> createState() => _KeyboardTabState();
}

class _KeyboardTabState extends State<KeyboardTab> {
  final StickyModifiers _modifiers = StickyModifiers();

  /// Caps Lock as a local latch. Deliberately NOT sent to the PC: printable
  /// keys go out as `text`, which the PC inserts literally, so a caps state on
  /// the PC would have nothing to act on and would desynchronise from ours.
  bool _caps = false;

  bool _showFunctionKeys = false;

  /// Letters or symbols. Digits and punctuation live behind the `123` key so
  /// no letter row ever has to hold more than eleven keys.
  bool _symbols = false;

  /// The last thing sent, shown so the user can tell the keyboard is working.
  ///
  /// Without this the custom keys look inert: pressing one changes nothing on
  /// screen, because the PC is what receives it. On a device, with no PC
  /// attached, that reads as a broken app.
  String? _lastSent;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  EventSink get _sink => context.read<EventSink>();

  bool get _enabled => _sink.isReady;

  /// Shift applies to the next character only, then releases itself, because
  /// shift is held in the same sticky set as Ctrl/Alt/Win.
  bool get _shiftOn => _modifiers.isLatched(ProtocolKey.shift) != _caps;

  void _pressCharacter(String character) {
    if (!_enabled) return;
    Haptics.tap();

    final shiftOn = _shiftOn;
    // Shift changes the character we send rather than being sent as a chord
    // member: {"keys":["shift","a"]} is not a thing, "A" is.
    final held = _modifiers.consume().where((k) => k != ProtocolKey.shift);
    final output = shiftOn ? character.toUpperCase() : character;

    if (held.isNotEmpty) {
      _sink.send(ComboEvent([...held, output.toLowerCase()]));
      setState(() => _lastSent = 'Ctrl/Alt + ${output.toUpperCase()}');
    } else {
      _sink.send(TextEvent(output));
      setState(() => _lastSent = output);
    }
  }

  void _pressNamedKey(String key) {
    if (!_enabled) return;
    Haptics.tap();
    final held = _modifiers.consume();

    if (held.isNotEmpty) {
      _sink.send(ComboEvent([...held, key]));
    } else {
      _sink.send(KeyEvent(key, 'tap'));
    }
    setState(() => _lastSent = KeyboardLayout.label(key));
  }

  void _toggleModifier(String key) {
    if (!_enabled) return;
    Haptics.tap();
    _modifiers.toggle(key);
    setState(() {});
  }

  /// Keys that change local state and must never be sent to the PC.
  ///
  /// Both were originally sent as key events, which would have produced
  /// `{"t":"key","k":"caps"}` and `{"t":"key","k":"fn"}`. Neither is in the
  /// protocol's key list, so the companion would drop them with E_BAD_FIELD and
  /// the key would look dead while appearing perfectly normal on screen.
  void _onLocalKey(String key) {
    if (!_enabled) return;
    Haptics.tap();
    setState(() {
      if (key == 'caps') {
        _caps = !_caps;
      } else if (key == '123') {
        _symbols = true;
      } else if (key == 'abc') {
        _symbols = false;
      } else if (key == 'fn') {
        _showFunctionKeys = !_showFunctionKeys;
      }
    });
  }

  /// Send whatever is in the text field using the phone's own keyboard.
  ///
  /// Plan task 3.4.5: this is how voice typing and Urdu work, because the
  /// phone's input methods handle them and we do not have to.
  void _injectText() {
    final text = _textController.text.trim();
    if (text.isEmpty || !_enabled) return;
    Haptics.confirm();
    _sink.send(TextEvent(text));
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final sink = context.watch<EventSink>();
    final enabled = sink.isReady;

    return Column(
      children: [
        if (_showFunctionKeys)
          _FunctionKeyRow(
            enabled: enabled,
            onKey: (k) => _sendFunction(k, sink, enabled),
          ),
        _ShortcutsRow(
          enabled: enabled,
          onCombo: (keys) {
            Haptics.tap();
            sink.send(ComboEvent(keys));
          },
        ),
        _TextInjectionRow(
          controller: _textController,
          focusNode: _textFocus,
          enabled: enabled,
          onSend: _injectText,
        ),
        Expanded(
          // Scrollable rather than merely laid out: the shortcut strip, the
          // injection field, the function row and four rows of keys do not fit
          // on a short screen, and an overflow is a hard error that renders red
          // stripes over the keys. Scrolling degrades honestly.
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TapDeskSpace.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showFunctionKeys)
                    _FunctionKeyRow(
                      enabled: enabled,
                      onKey: (k) {
                        Haptics.tap();
                        final held = _modifiers.consume();
                        sink.send(ComboEvent([...held, k]));
                        setState(() => _lastSent = k.toUpperCase());
                      },
                    ),
                  for (final row in _rows)
                    _KeyRow(
                      keys: row,
                      enabled: enabled,
                      caps: _caps,
                      latched: _modifiers,
                      onCharacter: _pressCharacter,
                      onNamed: _pressNamedKey,
                      onModifier: _toggleModifier,
                      onLocalKey: _onLocalKey,
                    ),
                  const SizedBox(height: TapDeskSpace.s2),
                  _BottomRow(
                    enabled: enabled,
                    showFunctionKeys: _showFunctionKeys,
                    latched: _modifiers,
                    onToggleFunctions: () =>
                        setState(() => _showFunctionKeys = !_showFunctionKeys),
                    onNamed: _pressNamedKey,
                    onModifier: _toggleModifier,
                  ),
                  const SizedBox(height: TapDeskSpace.s2),
                  _SentStrip(lastSent: _lastSent),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The rows for the current layer. Digits and punctuation sit behind the
  /// `123` key so no row ever exceeds eleven keys.
  List<List<String>> get _rows => _symbols
      ? [
          KeyboardLayout.symbolsTop,
          KeyboardLayout.symbolsHome,
          KeyboardLayout.symbolsBottom,
          KeyboardLayout.lettersSpace,
        ]
      : [
          KeyboardLayout.lettersTop,
          KeyboardLayout.lettersHome,
          KeyboardLayout.lettersBottom,
          KeyboardLayout.lettersSpace,
        ];
  void _sendFunction(String key, EventSink sink, bool enabled) {
    if (!enabled) return;
    Haptics.tap();
    final held = _modifiers.consume();
    sink.send(ComboEvent([...held, key]));
  }
}

/// One row of keys, each sized by how wide it should be.
class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.keys,
    required this.enabled,
    required this.caps,
    required this.onCharacter,
    required this.onNamed,
    this.onModifier,
    this.onLocalKey,
    this.latched,
  });

  final List<String> keys;
  final bool enabled;
  final bool caps;
  final void Function(String character) onCharacter;
  final void Function(String key) onNamed;
  final void Function(String key)? onModifier;
  final void Function(String key)? onLocalKey;
  final StickyModifiers? latched;

  /// Keys that act on this app only and are never sent to the PC.
  static Set<String> get localOnlyKeys => KeyboardLayout.localOnly;

  bool _isActive(String key) {
    if (KeyboardLayout.modifiers.contains(key)) {
      if (key == ProtocolKey.shift) return latched?.isLatched(key) ?? false;
      return latched?.isLatched(key) ?? false;
    }
    return key == 'caps' && caps;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          for (final key in keys)
            Expanded(
              flex: key == 'space' ? 4 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _buildKey(key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKey(String key) {
    final active = _isActive(key);
    final isModifier = KeyboardLayout.modifiers.contains(key);

    // Caps and Fn change our own state and are NEVER sent. Neither is a
    // protocol key id, so sending them produced
    // {"t":"key","k":"caps"} and {"t":"key","k":"fn"}, which the companion
    // drops with E_BAD_FIELD - a key that looks entirely normal and does
    // nothing at all.
    final isLocalOnly = localOnlyKeys.contains(key);

    final VoidCallback? press = !enabled
        ? null
        : isModifier
        ? () => onModifier!(key)
        : isLocalOnly
        ? () => onLocalKey!(key)
        : (KeyboardLayout.labels.containsKey(key)
              ? () => onNamed(key)
              : () => onCharacter(key));

    return Opacity(
      // Disabled keys are dimmed AND lose their border, per the design system.
      opacity: enabled ? 1 : 0.45,
      child: KeyCap(
        label: KeyboardLayout.label(key),
        active: active,
        onPressed: press ?? () {},
        semanticLabel: _semanticFor(key),
      ),
    );
  }

  String _semanticFor(String key) {
    switch (key) {
      case 'backspace':
        return 'Backspace';
      case 'enter':
        return 'Enter';
      case 'tab':
        return 'Tab';
      case 'caps':
        return 'Caps lock';
      case 'shift':
        return 'Shift';
      case 'ctrl':
        return 'Control';
      case 'alt':
        return 'Alt';
      case 'win':
        return 'Windows';
      case 'fn':
        return 'Function';
      default:
        return 'Type $key';
    }
  }
}

/// Shows the most recent thing sent to the computer.
///
/// The on-screen keyboard is the odd one out in this app: pressing a key
/// changes nothing on this screen, because the computer is what receives it.
/// Without a feedback line the keys look broken - especially with no PC
/// attached, where the app appears to do nothing at all.
class _SentStrip extends StatelessWidget {
  const _SentStrip({required this.lastSent});

  final String? lastSent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const Icon(
            Icons.keyboard_alt_outlined,
            size: 14,
            color: TapDeskColors.textMuted,
          ),
          const SizedBox(width: TapDeskSpace.s2),
          Expanded(
            child: Text(
              lastSent == null
                  ? 'Keys you press are sent to the computer'
                  : 'Sent: $lastSent',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TapDeskText.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// Arrows and the F-key toggle.
class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.enabled,
    required this.showFunctionKeys,
    required this.latched,
    required this.onToggleFunctions,
    required this.onNamed,
    required this.onModifier,
  });

  final bool enabled;
  final bool showFunctionKeys;
  final StickyModifiers latched;
  final VoidCallback onToggleFunctions;
  final void Function(String key) onNamed;
  final void Function(String key) onModifier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        children: [
          for (final key in KeyboardLayout.arrows)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Opacity(
                  opacity: enabled ? 1 : 0.45,
                  child: KeyCap(
                    label: _arrowGlyph(key),
                    dense: true,
                    onPressed: enabled ? () => onNamed(key) : () {},
                    semanticLabel: '$key arrow',
                  ),
                ),
              ),
            ),
          const SizedBox(width: TapDeskSpace.s2),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: KeyCap(
                  label: showFunctionKeys ? 'F ×' : 'F-keys',
                  dense: true,
                  // Active fill shows the row is open.
                  active: showFunctionKeys,
                  onPressed: enabled ? onToggleFunctions : () {},
                  semanticLabel: 'Toggle function keys',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _arrowGlyph(String key) => switch (key) {
    'left' => '←',
    'up' => '↑',
    'down' => '↓',
    _ => '→',
  };
}

class _FunctionKeyRow extends StatelessWidget {
  const _FunctionKeyRow({required this.enabled, required this.onKey});

  final bool enabled;
  final void Function(String key) onKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TapDeskSpace.s2,
        vertical: TapDeskSpace.s1,
      ),
      child: Row(
        children: [
          for (final key in KeyboardLayout.functionKeys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Opacity(
                  opacity: enabled ? 1 : 0.45,
                  child: KeyCap(
                    label: key.toUpperCase(),
                    dense: true,
                    onPressed: enabled ? () => onKey(key) : () {},
                    semanticLabel: key.toUpperCase(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One-tap shortcuts (plan task 3.4.6).
class _ShortcutsRow extends StatelessWidget {
  const _ShortcutsRow({required this.enabled, required this.onCombo});

  final bool enabled;
  final void Function(List<String> keys) onCombo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TapDeskSpace.s2),
        children: [
          for (final shortcut in KeyboardLayout.shortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: Material(
                  color: TapDeskColors.surface,
                  borderRadius: BorderRadius.circular(TapDeskSpace.radiusPill),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      TapDeskSpace.radiusPill,
                    ),
                    onTap: enabled ? () => onCombo(shortcut.combo) : null,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: TapDeskSpace.s4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          TapDeskSpace.radiusPill,
                        ),
                        border: Border.all(color: TapDeskColors.divider),
                      ),
                      child: Text(
                        shortcut.label,
                        style: TapDeskText.label.copyWith(
                          color: TapDeskColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Text injection using the phone's own keyboard.
class _TextInjectionRow extends StatelessWidget {
  const _TextInjectionRow({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TapDeskSpace.s2,
        TapDeskSpace.s2,
        TapDeskSpace.s2,
        TapDeskSpace.s1,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              // Suggestion-free: autocorrect would rewrite what the user
              // deliberately typed into the PC.
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: TapDeskText.bodyText,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Type or dictate text…',
                hintStyle: TapDeskText.label,
                filled: true,
                fillColor: TapDeskColors.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: TapDeskSpace.s3,
                  vertical: TapDeskSpace.s3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
                  borderSide: const BorderSide(color: TapDeskColors.divider),
                ),
              ),
            ),
          ),
          const SizedBox(width: TapDeskSpace.s2),
          SizedBox(
            width: 56,
            height: TapDeskSpace.minTouchTarget,
            child: Material(
              color: enabled
                  ? TapDeskColors.primary
                  : TapDeskColors.surfaceElevated,
              borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
              child: InkWell(
                borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
                onTap: enabled ? onSend : null,
                child: Icon(
                  Icons.send,
                  color: enabled ? TapDeskColors.text : TapDeskColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
