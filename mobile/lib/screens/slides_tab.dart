import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/tokens.dart';
import '../transport/event_sink.dart';
import '../transport/tapdesk_event.dart';
import '../ui/haptics.dart';

/// The Slides tab: Previous and Next, plus the three secondary actions.
///
/// This is the screen a teacher hits dozens of times an hour without looking,
/// so it is the one where "large, obvious, never surprising" matters most.
/// Every press fires a haptic — the phone is in a pocket-hand at that point
/// and the buzz is the only confirmation the user gets.
class SlidesTab extends StatefulWidget {
  const SlidesTab({super.key});

  @override
  State<SlidesTab> createState() => _SlidesTabState();
}

class _SlidesTabState extends State<SlidesTab> {
  /// Lecture pacing. Plan task 3.2.5.
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _timerRunning = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    setState(() {
      if (_timerRunning) {
        _timer?.cancel();
        _timer = null;
        _timerRunning = false;
        _elapsed = Duration.zero;
      } else {
        _timerRunning = true;
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _elapsed += const Duration(seconds: 1));
        });
      }
    });
    Haptics.tap();
  }

  @override
  Widget build(BuildContext context) {
    final sink = context.watch<EventSink>();
    final enabled = sink.isReady;

    return Padding(
      padding: const EdgeInsets.all(TapDeskSpace.s4),
      child: Column(
        children: [
          // Previous and Next get the space, in proportion, with no other
          // control competing for attention.
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: SlideButton(
                    enabled: enabled,
                    icon: Icons.chevron_left,
                    label: 'Previous',
                    // A very large target: this is the button pressed while
                    // walking, without looking down.
                    onPressed: () => _send(sink, SlideAction.prev),
                  ),
                ),
                const SizedBox(width: TapDeskSpace.s3),
                Expanded(
                  child: SlideButton(
                    enabled: enabled,
                    icon: Icons.chevron_right,
                    label: 'Next',
                    onPressed: () => _send(sink, SlideAction.next),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TapDeskSpace.s3),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(
                  child: SecondarySlideButton(
                    enabled: enabled,
                    label: 'Start',
                    icon: Icons.play_arrow,
                    onPressed: () => _send(sink, SlideAction.start),
                  ),
                ),
                const SizedBox(width: TapDeskSpace.s3),
                Expanded(
                  child: SecondarySlideButton(
                    enabled: enabled,
                    label: 'End',
                    icon: Icons.stop,
                    onPressed: () => _send(sink, SlideAction.end),
                  ),
                ),
                const SizedBox(width: TapDeskSpace.s3),
                Expanded(
                  child: SecondarySlideButton(
                    enabled: enabled,
                    label: 'Black',
                    icon: Icons.contrast,
                    onPressed: () => _send(sink, SlideAction.blank),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TapDeskSpace.s3),
          _TimerBar(
            running: _timerRunning,
            elapsed: _elapsed,
            enabled: enabled,
            onToggle: _toggleTimer,
          ),
        ],
      ),
    );
  }

  void _send(EventSink sink, String action) {
    Haptics.tap();
    sink.send(SlideEvent(action));
  }
}

/// A big Previous/Next button.
class SlideButton extends StatelessWidget {
  const SlideButton({
    super.key,
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      // TalkBack users get the action, not the glyph.
      label: enabled ? label : '$label, unavailable while disconnected',
      child: Material(
        color: enabled ? TapDeskColors.primary : TapDeskColors.surfaceElevated,
        borderRadius: BorderRadius.circular(TapDeskSpace.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(TapDeskSpace.radiusPill),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  // 40 dp per the design system, scaled to whatever height the
                  // layout gives us.
                  size: 56,
                  color: enabled
                      ? TapDeskColors.text
                      : TapDeskColors.textMuted,
                ),
                const SizedBox(height: TapDeskSpace.s2),
                Text(
                  label,
                  style: TapDeskText.button.copyWith(
                    color: enabled
                        ? TapDeskColors.text
                        : TapDeskColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three secondary actions: 56 dp, outlined, less prominent than
/// Previous/Next but never less tappable.
class SecondarySlideButton extends StatelessWidget {
  const SecondarySlideButton({
    super.key,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? TapDeskColors.surface : TapDeskColors.surfaceElevated,
        borderRadius: BorderRadius.circular(TapDeskSpace.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(TapDeskSpace.radiusCard),
          onTap: enabled ? onPressed : null,
          child: Container(
            height: TapDeskSpace.minTouchTarget,
            alignment: Alignment.center,
            // The green border is what makes these look actionable, so a
            // disabled button loses it rather than just fading.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TapDeskSpace.radiusCard),
              border: Border.all(
                color: enabled
                    ? TapDeskColors.primary
                    : TapDeskColors.divider,
                width: TapDeskSpace.borderWidth,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: enabled
                      ? TapDeskColors.primary
                      : TapDeskColors.textMuted,
                ),
                Text(
                  label,
                  style: TapDeskText.label.copyWith(
                    color: enabled
                        ? TapDeskColors.primary
                        : TapDeskColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The lecture timer (plan task 3.2.5).
///
/// Local only — it paces the speaker, it is not sent to the PC. It runs even
/// while disconnected, because pacing a lecture does not need a computer.
class _TimerBar extends StatelessWidget {
  const _TimerBar({
    required this.running,
    required this.elapsed,
    required this.enabled,
    required this.onToggle,
  });

  final bool running;
  final Duration elapsed;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final text = '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';

    return SizedBox(
      height: TapDeskSpace.minTouchTarget,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              // Monospace so the digits do not jitter as they change width.
              style: TapDeskText.monoText.copyWith(
                fontSize: 20,
                color: running
                    ? TapDeskColors.highlight
                    : TapDeskColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: TapDeskColors.primary,
              // A finite width, not Size.fromHeight - inside a Row that would
              // ask for infinite width and throw during layout.
              minimumSize: const Size(140, TapDeskSpace.minTouchTarget),
            ),
            child: Text(running ? 'Stop timer' : 'Start timer'),
          ),
        ],
      ),
    );
  }
}
