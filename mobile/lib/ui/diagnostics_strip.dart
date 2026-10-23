/// The on-screen tail of the connection trace.
///
/// A small monospace box listing the newest milestones of the connection
/// attempt. The point of [lib/state/diagnostics.dart]: the phone can stall
/// somewhere neither the PC's log nor the status texts can name, and the
/// person holding the phone is the only one who can read what it shows.
///
/// It ships with a minimise control because its debugging job is done: the
/// pairing failure it was built for is fixed, and a permanent strip on a
/// finished product screen is clutter unless the user wants it. Collapsed is
/// a one-line sliver that keeps the choice visible and reversible, and the
/// choice is remembered between runs - a user who minimised it should never
/// see it come back uninvited.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/diagnostics.dart';
import '../theme/tokens.dart';

class DiagnosticsStrip extends StatefulWidget {
  const DiagnosticsStrip({super.key});

  @override
  State<DiagnosticsStrip> createState() => _DiagnosticsStripState();
}

class _DiagnosticsStripState extends State<DiagnosticsStrip> {
  /// The most the strip may ever take when open. A capped strip is exactly
  /// what makes these screens unusable: the scanner and controls share the
  /// same column, so an uncapped strip of thrown stack traces can push
  /// everything a user needs to tap off-screen with no way to scroll.
  static const double _maxHeight = 132;

  static const String _collapseKey = 'trace_minimised';

  bool _minimised = false;

  @override
  void initState() {
    super.initState();
    _restoreCollapsed();
  }

  /// Read back the user's last choice, defaulting to open.
  ///
  /// Failure-proof the same way the settings loader is: a phone whose
  /// preferences channel is broken gets the open strip, its default, rather
  /// than a widget that never builds.
  Future<void> _restoreCollapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = prefs.getBool(_collapseKey);
      if (state != null && mounted && state != _minimised) {
        setState(() => _minimised = state);
      }
    } catch (_) {
      // Default to open; the strip itself still narrates any real failure.
    }
  }

  Future<void> _toggleMinimised() async {
    final next = !_minimised;
    setState(() => _minimised = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_collapseKey, next);
    } catch (_) {
      // Preferences lost is not worth a trace line; the choice is honoured
      // for this session the same either way.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: trace,
      builder: (context, _) {
        final hasContent = trace.lines.isNotEmpty;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: TapDeskColors.surface,
            border: Border.all(color: TapDeskColors.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The one row that is always there: the toggle. A strip a user
              // can minimise but never open again is a trap, and the affordance
              // must survive even when the content is hidden from view.
              InkWell(
                onTap: _toggleMinimised,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: Row(
                    children: [
                      Icon(
                        _minimised ? Icons.expand_more : Icons.expand_less,
                        size: 18,
                        color: TapDeskColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _minimised
                            ? (hasContent ? 'connection trace hidden' : 'connection trace')
                            : 'connection trace',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: TapDeskText.mono,
                          color: TapDeskColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_minimised)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                  child: _TraceBody(maxHeight: _maxHeight),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TraceBody extends StatelessWidget {
  const _TraceBody({required this.maxHeight});

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final lines = trace.lines;
    final shown = lines.length > 6 ? lines.sublist(lines.length - 6) : lines;
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(color: TapDeskColors.background),
      child: SingleChildScrollView(
        // Newest lines at the bottom, and the view pinned to them: a flood of
        // exceptions scrolls the ones that matter off-screen unless the box
        // itself follows.
        reverse: true,
        child: Text(
          shown.isEmpty ? 'no connection activity yet' : shown.join('\n'),
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            fontFamily: TapDeskText.mono,
            color: TapDeskColors.textMuted,
          ),
        ),
      ),
    );
  }
}
