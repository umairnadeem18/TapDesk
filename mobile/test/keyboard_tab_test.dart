import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapdesk_mobile/main.dart';
import 'package:tapdesk_mobile/state/pairing_store.dart';
import 'package:tapdesk_mobile/transport/event_sink.dart';
import 'package:tapdesk_mobile/transport/pairing_payload.dart';
import 'package:tapdesk_mobile/widgets/keyboard_layout.dart';

/// Tests for the Keyboard tab.
///
/// Two things are worth guarding here. First, printable keys go out as `text`
/// rather than `key`, because a wrong key id is dropped silently by the
/// companion and the key just looks dead. Second, sticky modifiers must be
/// consumed after use, or Ctrl stays latched and every subsequent key becomes
/// a chord.
void main() {
  Future<RecordingEventSink> openKeyboard(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PairingStore();
    await store.remember(
      PairingPayload.tryParseManual(
        ip: '192.168.1.15',
        port: 8765,
        pin: '483920',
        fingerprint: 'a' * 64,
      )!,
    );

    final sink = RecordingEventSink(isReady: true);
    await tester.pumpWidget(TapDeskApp(sink: sink));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    return sink;
  }

  group('StickyModifiers', () {
    test('latches, reports and clears', () {
      final m = StickyModifiers();
      expect(m.isEmpty, isTrue);

      expect(m.toggle('ctrl'), isTrue);
      expect(m.isLatched('ctrl'), isTrue);

      expect(m.consume(), ['ctrl']);
      expect(
        m.isEmpty,
        isTrue,
        reason: 'a latched modifier must not survive its use',
      );
    });

    test('toggling twice releases', () {
      final m = StickyModifiers()..toggle('ctrl');
      expect(m.toggle('ctrl'), isFalse);
      expect(m.isLatched('ctrl'), isFalse);
    });

    test('rejects a non-modifier', () {
      expect(() => StickyModifiers().toggle('a'), throwsArgumentError);
    });

    test('consume on an empty set is harmless', () {
      expect(StickyModifiers().consume(), isEmpty);
    });
  });

  group('layout', () {
    test('every punctuation key maps to a protocol id', () {
      // A wrong id here means the companion drops the key with E_BAD_FIELD and
      // the user sees a key that does nothing.
      const pairs = {
        '-': 'minus',
        '=': 'equal',
        '[': 'lbracket',
        ']': 'rbracket',
        '\\': 'backslash',
        ';': 'semicolon',
        "'": 'apostrophe',
        ',': 'comma',
        '.': 'period',
        '/': 'slash',
        '`': 'grave',
      };
      for (final entry in pairs.entries) {
        expect(
          KeyboardLayout.characterToKeyId(entry.key),
          entry.value,
          reason: '${entry.key} maps wrong',
        );
      }
    });

    test('letters and digits map correctly', () {
      expect(KeyboardLayout.characterToKeyId('a'), 'a');
      expect(KeyboardLayout.characterToKeyId('Z'), 'z');
      expect(KeyboardLayout.characterToKeyId('5'), '5');
    });

    test('every grid key resolves to something the PC will accept', () {
      // The expensive failure is a key that renders normally but is not a
      // protocol id: the companion drops it with E_BAD_FIELD and the user
      // sees a dead key. So each key is checked against one of the three
      // categories it is actually allowed to be.
      final all = <String>{
        ...KeyboardLayout.lettersTop,
        ...KeyboardLayout.lettersHome,
        ...KeyboardLayout.lettersBottom,
        ...KeyboardLayout.lettersSpace,
        ...KeyboardLayout.symbolsTop,
        ...KeyboardLayout.symbolsHome,
        ...KeyboardLayout.symbolsBottom,
      };

      for (final key in all) {
        if (KeyboardLayout.localOnly.contains(key)) continue;
        if (KeyboardLayout.modifiers.contains(key)) {
          expect(ProtocolKeyShim.all, contains(key));
          continue;
        }
        if (KeyboardLayout.labels.containsKey(key)) {
          // A named key: its id must itself be a protocol key id.
          expect(
            ProtocolKeyShim.all,
            contains(key),
            reason: '$key is rendered as a key but is not a protocol id',
          );
          continue;
        }
        expect(
          KeyboardLayout.characterToKeyId(key),
          isNotNull,
          reason: '$key is a character with no mapping',
        );
      }
    });

    test('every rendered key is either a protocol id or local-only', () {
      // If a key is rendered but has no protocol id and is not local-only, it
      // is a dead key waiting to be found in a lecture hall.
      final all = {
        ...KeyboardLayout.lettersTop,
        ...KeyboardLayout.lettersHome,
        ...KeyboardLayout.lettersBottom,
        ...KeyboardLayout.lettersSpace,
        ...KeyboardLayout.symbolsTop,
        ...KeyboardLayout.symbolsHome,
        ...KeyboardLayout.symbolsBottom,
      };
      for (final key in all) {
        if (KeyboardLayout.localOnly.contains(key)) continue;
        if (ProtocolKeyShim.all.contains(key)) continue;
        final mapped = KeyboardLayout.characterToKeyId(key);
        expect(mapped, isNotNull, reason: '$key is dead on the wire');
        expect(ProtocolKeyShim.all, contains(mapped!));
      }
    });

    test('function keys are f1 to f12', () {
      expect(KeyboardLayout.functionKeys.first, 'f1');
      expect(KeyboardLayout.functionKeys.length, 12);
    });

    test('every shortcut uses real modifier ids', () {
      for (final s in KeyboardLayout.shortcuts) {
        expect(s.combo, isNotEmpty);
        expect(s.combo.first, isIn(ProtocolKeyShim.modifiers));
      }
    });
  });

  group('typing', () {
    testWidgets('a letter is sent as text, not as a key event', (tester) async {
      final sink = await openKeyboard(tester);

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(sink.frames, [
        '{"t":"text","s":"a"}',
      ], reason: 'printable keys must use text so Unicode works');
    });

    testWidgets('shift upper-cases exactly one character', (tester) async {
      final sink = await openKeyboard(tester);

      await tester.tap(find.widgetWithText(KeyCap, 'Shift').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(sink.frames, [
        '{"t":"text","s":"A"}',
        '{"t":"text","s":"b"}',
      ], reason: 'shift must release after exactly one character');
    });

    testWidgets('a latched Ctrl then C sends the chord', (tester) async {
      final sink = await openKeyboard(tester);

      await tester.tap(find.widgetWithText(KeyCap, 'Ctrl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();

      expect(sink.frames, ['{"t":"combo","keys":["ctrl","c"]}']);
    });

    testWidgets('the latch is consumed, so the next key is plain', (
      tester,
    ) async {
      final sink = await openKeyboard(tester);

      await tester.tap(find.widgetWithText(KeyCap, 'Ctrl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('V'));
      await tester.pumpAndSettle();

      expect(sink.frames, [
        '{"t":"combo","keys":["ctrl","c"]}',
        '{"t":"text","s":"v"}',
      ]);
    });

    testWidgets('Enter and Backspace use protocol key ids', (tester) async {
      final sink = await openKeyboard(tester);

      await tester.tap(
        find.widgetWithText(KeyCap, KeyboardLayout.labels['enter']!),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(KeyCap, KeyboardLayout.labels['backspace']!),
      );
      await tester.pumpAndSettle();

      expect(sink.frames, [
        '{"t":"key","k":"enter","a":"tap"}',
        '{"t":"key","k":"backspace","a":"tap"}',
      ]);
    });

    testWidgets('the Copy shortcut sends the documented chord', (tester) async {
      final sink = await openKeyboard(tester);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(sink.frames, ['{"t":"combo","keys":["ctrl","c"]}']);
    });

    testWidgets('caps, 123 and fn are never sent as key events',
        (tester) async {
      final sink = await openKeyboard(tester);

      // Caps Lock moved to the symbols layer when the letter rows had to shed
      // a key, so the layer is switched first.
      await tester.tap(find.widgetWithText(KeyCap, '123').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(KeyCap, 'CAPS').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(KeyCap, 'Fn'));
      await tester.pumpAndSettle();

      // None of these is a protocol key id, so sending them would be silently
      // dropped by the companion and the key would look broken.
      expect(sink.frames, isEmpty);
    });
  });

  group('layout density', () {
    test('no row holds more than eleven keys', () {
      // Found on a device: fourteen keys across a 360 dp phone left ~26 dp per
      // key against a 56 dp requirement, and the keyboard looked cramped.
      // Digits and punctuation moved behind the 123 toggle to make room.
      final rows = <List<String>>[
        KeyboardLayout.lettersTop,
        KeyboardLayout.lettersHome,
        KeyboardLayout.lettersBottom,
        KeyboardLayout.lettersSpace,
        KeyboardLayout.symbolsTop,
        KeyboardLayout.symbolsHome,
        KeyboardLayout.symbolsBottom,
      ];
      for (final row in rows) {
        expect(
          row.length,
          lessThanOrEqualTo(11),
          reason: 'a row holds ${row.length} keys',
        );
      }
    });

    test('digits and punctuation live behind the 123 toggle', () {
      expect(KeyboardLayout.lettersTop.contains('1'), isFalse);
      expect(KeyboardLayout.lettersSpace, contains('123'));
      expect(KeyboardLayout.symbolsBottom, contains('abc'));
    });
  });
}

/// Mirrors ProtocolKey.modifiers without importing the transport layer into a
/// pure layout test.
class ProtocolKeyShim {
  static const Set<String> modifiers = {'shift', 'ctrl', 'alt', 'win'};

  static final Set<String> all = {
    ...'abcdefghijklmnopqrstuvwxyz'.split(''),
    ...'0123456789'.split(''),
    'f1',
    'f2',
    'f3',
    'f4',
    'f5',
    'f6',
    'f7',
    'f8',
    'f9',
    'f10',
    'f11',
    'f12',
    'up',
    'down',
    'left',
    'right',
    'enter',
    'tab',
    'backspace',
    'delete',
    'insert',
    'esc',
    'space',
    ...modifiers,
    'capslock',
    'numlock',
    'scrolllock',
    'home',
    'end',
    'pgup',
    'pgdn',
    'minus',
    'equal',
    'lbracket',
    'rbracket',
    'backslash',
    'semicolon',
    'apostrophe',
    'grave',
    'comma',
    'period',
    'slash',
    'printscreen',
    'pause',
    'menu',
  };
}
