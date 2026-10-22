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

  /// The kept lines, oldest first, most recent last.
  List<String> get lines => List.unmodifiable(_lines);

  /// Record [line] with a timestamp, keeping only the newest [_maxLines].
  ///
  /// [debugPrint] keeps the same story for whoever runs `flutter run`; the
  /// strip on screen is the one that reaches the user with no terminal.
  void add(String line) {
    final stamp = DateTime.now().toIso8601String();
    _lines.add('${stamp.substring(11, 23)}  $line');
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
    notifyListeners();
  }
}
