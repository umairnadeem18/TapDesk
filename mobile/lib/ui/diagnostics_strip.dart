/// The on-screen tail of the connection trace.
///
/// A small monospace box listing the newest milestones of the connection
/// attempt. The point of [lib/state/diagnostics.dart]: the phone can stall
/// somewhere neither the PC's log nor the status texts can name, and the
/// person holding the phone is the only one who can read what it shows.
library;

import 'package:flutter/material.dart';

import '../state/diagnostics.dart';
import '../theme/tokens.dart';

class DiagnosticsStrip extends StatelessWidget {
  const DiagnosticsStrip({super.key});

  /// The most the strip may ever take. A capped strip is exactly what makes
  /// the pairing screen unusable: the scanner area above it shares the same
  /// column, so an uncapped strip of thrown stack traces can push the camera
  /// (and everything else a user needs to tap) clean off the screen - which
  /// is what one fresh install did before this cap existed.
  static const double _maxHeight = 132;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: trace,
      builder: (context, _) {
        final lines = trace.lines;
        final shown = lines.length > 6 ? lines.sublist(lines.length - 6) : lines;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(maxHeight: _maxHeight),
          decoration: BoxDecoration(
            color: TapDeskColors.surface,
            border: Border.all(color: TapDeskColors.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            // Newest lines at the bottom, and the view pinned to them: a
            // flood of exceptions scrolls the ones that matter off-screen
            // unless the box itself follows.
            reverse: true,
            child: Text(
              shown.isEmpty ? 'no connection activity yet' : shown.join('\n'),
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                fontFamily: TapDeskText.mono,
                color: TapDeskColors.textMuted,
              ),
            ),
          ),
        );
      },
    );
  }
}
