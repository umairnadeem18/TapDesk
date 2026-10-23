/// A connection-diagnosis strip the phone shows on its own screen.
///
/// This exists because debugging this app remotely has taught us the cost of
/// silence: the PC can log every refusal it sees, but a phone that dials and
/// then stalls has no log anyone can read - there is no adb on the user's
/// desk. Three nights of "my phone says not connected" without a single
/// milestone visible anywhere made each fix a guess.
///
/// The trace records the connection milestones in memory (e.g. "dialing",
/// "socket open", "hello sent", "status changed") and the screens render its
/// last few lines in a small strip. It is deliberately blunt and lives on
/// screen in release builds as well: the price of a debug-only reporter is
/// that findings never arrive where they are needed.
///
/// In-memory only and capped, so it holds nothing sensitive once the app is
/// gone and cannot leak the pairing token (milestones say whether a token was
/// used, never its value).
library;

import 'package:flutter/foundation.dart';

/// Appends a milestone: [trace] ('socket open'), [trace] ('status: Connected').
final DiagnosticsTrace trace = DiagnosticsTrace._();

class DiagnosticsTrace extends ChangeNotifier {
  DiagnosticsTrace._();

  static const int _maxLines = 12;

  final List<String> _lines = <String>[];

  String? _lastRaw;
  int _repeat = 0;

  /// The kept lines, oldest first, most recent last.
  List<String> get lines => List.unmodifiable(_lines);

  /// Record [line] with a timestamp, keeping only the newest [_maxLines].
  ///
  /// A failing platform channel can throw faster than any list can hold, and
  /// the same stack repeated forty times tells nobody anything new. Identical
  /// consecutive lines collapse into one entry that counts its repeats.
  ///
  /// [debugPrint] keeps the same story for whoever runs `flutter run`; the
  /// strip on screen is the one that reaches the user with no terminal.
  void add(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    if (_lines.isNotEmpty && _lastRaw == line) {
      _repeat++;
      _lines[_lines.length - 1] = '$stamp  $line (×$_repeat)';
      notifyListeners();
      if (kDebugMode) debugPrint('[tapdesk] $line');
      return;
    }
    _lastRaw = line;
    _repeat = 1;
    _lines.add('$stamp  $line');
    while (_lines.length > _maxLines) {
      _lines.removeAt(0);
    }
    if (kDebugMode) debugPrint('[tapdesk] $line');
    notifyListeners();
  }

  /// Drop everything - used when a whole new pairing attempt starts, so the
  /// strip shows the current attempt rather than an archaeology dig.
  void reset() {
    _lines.clear();
    _lastRaw = null;
    _repeat = 0;
    notifyListeners();
  }
}
