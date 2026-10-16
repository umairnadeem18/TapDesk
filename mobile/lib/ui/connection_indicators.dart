import 'package:flutter/material.dart';

import '../state/connection_controller.dart';
import '../theme/tokens.dart';

/// The connection indicator in the app bar.
///
/// Green means connected and nothing else, per the design system. The dot
/// pulses at 1 Hz while reconnecting, and the whole widget sits inside a
/// Semantics label so TalkBack announces the state instead of leaving the user
/// to interpret a coloured circle.
class ConnectionDot extends StatelessWidget {
  const ConnectionDot({super.key, required this.status, this.size = 10});

  final ConnectionStatus status;
  final double size;

  Color get _color => switch (status) {
        ConnectionStatus.connected => TapDeskColors.primary,
        ConnectionStatus.connecting ||
        ConnectionStatus.handshaking ||
        ConnectionStatus.awaitingApproval ||
        ConnectionStatus.reconnecting =>
          TapDeskColors.warning,
        ConnectionStatus.idle => TapDeskColors.textMuted,
        ConnectionStatus.revoked ||
        ConnectionStatus.denied ||
        ConnectionStatus.failed =>
          TapDeskColors.error,
      };

  bool get _pulses =>
      status == ConnectionStatus.reconnecting ||
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.handshaking;

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return Semantics(
      label: 'Connection status',
      value: status.label,
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pulses)
            _PulsingDot(size: size, color: color)
          else
            _Dot(size: size, color: color),
          const SizedBox(width: TapDeskSpace.s2),
          Text(
            status.label,
            style: TapDeskText.label.copyWith(
              color: status == ConnectionStatus.connected
                  ? TapDeskColors.text
                  : TapDeskColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        // Only a connected dot glows. Glow on a failed state would suggest
        // activity when there is none.
        boxShadow: color == TapDeskColors.primary
            ? [
                BoxShadow(
                  color: TapDeskColors.highlight.withValues(alpha: 0.55),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// A dot that fades in and out, used while connecting.
///
/// Animation is skipped entirely when the user has asked for reduced motion,
/// so it degrades to a static dot rather than a distracting pulse.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TapDeskDuration.pulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (reduceMotion) {
      return _Dot(size: widget.size, color: widget.color);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.35 + (0.65 * _controller.value),
          child: child,
        );
      },
      child: _Dot(size: widget.size, color: widget.color),
    );
  }
}

/// The banner shown under the tab bar whenever the app is not connected.
///
/// Its whole job is the design system's rule "never look broken": controls
/// behind it are disabled, and this explains why. It appears for every state
/// except `connected` and `idle`.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.status, this.error});

  final ConnectionStatus status;
  final String? error;

  bool get _isError =>
      status == ConnectionStatus.revoked ||
      status == ConnectionStatus.denied ||
      status == ConnectionStatus.failed;

  @override
  Widget build(BuildContext context) {
    final text = status.bannerText;
    if (text == null) return const SizedBox.shrink();

    final accent = _isError ? TapDeskColors.error : TapDeskColors.warning;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: TapDeskSpace.s4,
          vertical: TapDeskSpace.s3,
        ),
        decoration: BoxDecoration(
          color: TapDeskColors.surfaceElevated,
          border: Border(
            left: BorderSide(color: accent, width: TapDeskSpace.borderWidth + 1),
            bottom: BorderSide(color: TapDeskColors.divider, width: 1),
          ),
        ),
        child: Row(
          children: [
            if (!_isError)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              )
            else
              Icon(Icons.error_outline, size: 18, color: accent),
            const SizedBox(width: TapDeskSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: TapDeskText.bodyText),
                  if (error != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      error!,
                      style: TapDeskText.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
