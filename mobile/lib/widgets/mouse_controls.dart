import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../transport/tapdesk_event.dart';

/// A mouse button with three distinct gestures.
///
/// Plan task 3.3.3 and 3.3.4:
///  - tap        -> a normal click
///  - hold+drag  -> press on touch-down, release on touch-up, i.e. a drag
///  - double tap -> a double-click
///
/// Flutter's own `onTap` and `onDoubleTap` cannot be used together: `onTap`
/// waits 250 ms to see whether a second tap arrives, which would make every
/// click feel laggy. So the timing is handled here explicitly, and the press
/// is sent the moment the finger goes down so a drag feels instant.
class MouseButtonWidget extends StatefulWidget {
  const MouseButtonWidget({
    super.key,
    required this.button,
    required this.onEvent,
    this.enabled = true,
    this.size = 96,
    this.label,
  });

  /// `left` or `right`.
  final String button;

  final void Function(ClickEvent event) onEvent;
  final bool enabled;
  final double size;

  /// Screen-reader label. Defaults to the button name.
  final String? label;

  /// A hold longer than this becomes a drag rather than a click.
  static const Duration dragThreshold = Duration(milliseconds: 250);

  /// Two taps closer together than this are a double-click.
  static const Duration doubleClickWindow = Duration(milliseconds: 250);

  @override
  State<MouseButtonWidget> createState() => _MouseButtonWidgetState();
}

class _MouseButtonWidgetState extends State<MouseButtonWidget> {
  bool _pressed = false;

  /// True once the button has been held past the threshold, so release knows
  /// to send `up` rather than a click.
  bool _dragging = false;

  Timer? _holdTimer;
  DateTime? _lastTap;

  @override
  void didUpdateWidget(covariant MouseButtonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disconnecting mid-drag must release the button, or the PC keeps
    // thinking the mouse button is held down.
    if (oldWidget.enabled && !widget.enabled) _reset();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onDown() {
    if (!widget.enabled) return;
    _holdTimer?.cancel();
    setState(() {
      _pressed = true;
      _dragging = false;
    });
    _holdTimer = Timer(MouseButtonWidget.dragThreshold, _becomeDrag);
  }

  void _becomeDrag() {
    if (!mounted) return;
    setState(() => _dragging = true);
    // Sent immediately on entering drag mode, so the PC registers the press
    // while the user is still deciding whether to move.
    widget.onEvent(ClickEvent(widget.button, ClickAction.down));
  }

  void _onUp() {
    if (!widget.enabled) return;
    _holdTimer?.cancel();

    if (_dragging) {
      widget.onEvent(ClickEvent(widget.button, ClickAction.up));
      _reset();
      return;
    }

    final now = DateTime.now();
    final last = _lastTap;
    final isDouble = last != null &&
        now.difference(last) <= MouseButtonWidget.doubleClickWindow;

    if (isDouble) {
      // Clear so a third tap starts a fresh pair rather than firing again.
      _lastTap = null;
      widget.onEvent(ClickEvent(widget.button, ClickAction.double));
    } else {
      _lastTap = now;
      widget.onEvent(ClickEvent(widget.button, ClickAction.click));
    }
    _reset();
  }

  void _onCancel() {
    _holdTimer?.cancel();
    // A cancelled gesture that had already pressed must release, or the button
    // stays down on the PC forever.
    if (_dragging) {
      widget.onEvent(ClickEvent(widget.button, ClickAction.up));
    }
    _reset();
  }

  void _reset() {
    _holdTimer?.cancel();
    if (mounted) setState(() { _pressed = false; _dragging = false; });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.label ?? widget.button;
    final active = _pressed && widget.enabled;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.enabled
          ? '$name mouse button'
          : '$name mouse button, unavailable while disconnected',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _onDown() : null,
        onTapUp: widget.enabled ? (_) => _onUp() : null,
        onTapCancel: widget.enabled ? _onCancel : null,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: active
                ? TapDeskColors.primary
                : TapDeskColors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.enabled
                  ? TapDeskColors.primary
                  : TapDeskColors.divider,
              width: TapDeskSpace.borderWidth,
            ),
          ),
          child: Icon(
            widget.button == MouseButton.left
                ? Icons.touch_app_outlined
                : Icons.arrow_back_ios_new,
            size: 32,
            color: active
                ? TapDeskColors.text
                : (widget.enabled
                    ? TapDeskColors.primary
                    : TapDeskColors.textMuted),
          ),
        ),
      ),
    );
  }
}

/// The vertical scroll strip (plan task 3.3.5).
///
/// Scrolling is continuous rather than stepped: a stepped scroll cannot move
/// a long document at a useful speed, and the notchiness is very obvious when
/// the cursor is already near the target.
class ScrollStrip extends StatefulWidget {
  const ScrollStrip({
    super.key,
    required this.onScroll,
    this.enabled = true,
    this.height = 220,
  });

  /// Ticks per pixel of drag. Positive scrolls up.
  final void Function(double ticks) onScroll;

  final bool enabled;
  final double height;

  @override
  State<ScrollStrip> createState() => _ScrollStripState();
}

class _ScrollStripState extends State<ScrollStrip> {
  double? _lastY;

  /// One tick per 8 dp of travel - fast enough to cross a page in a short
  /// drag, slow enough to land on a single line.
  static const double _ticksPerPixel = 1 / 8;

  void _onDown(DragStartDetails d) {
    if (widget.enabled) _lastY = d.localPosition.dy;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _lastY == null) return;
    final delta = (_lastY! - d.localPosition.dy) * _ticksPerPixel;
    _lastY = d.localPosition.dy;
    // Rounded so a 1 px jitter does not send a zero-tick message.
    final ticks = delta.round();
    if (ticks != 0) widget.onScroll(ticks.toDouble());
  }

  void _onEnd() => _lastY = null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Scroll strip',
      hint: 'Drag up or down to scroll',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: widget.enabled ? _onDown : null,
        onVerticalDragUpdate: widget.enabled ? _onUpdate : null,
        onVerticalDragEnd: widget.enabled ? (_) => _onEnd() : null,
        onVerticalDragCancel: widget.enabled ? _onEnd : null,
        child: Container(
          width: TapDeskSpace.minTouchTarget,
          height: widget.height,
          decoration: BoxDecoration(
            color: TapDeskColors.surface,
            borderRadius: BorderRadius.circular(TapDeskSpace.radiusCard),
            border: Border.all(color: TapDeskColors.divider),
          ),
          child: Center(
            child: Container(
              // The thumb, sized per the design system.
              width: 20,
              height: 48,
              decoration: BoxDecoration(
                color: widget.enabled
                    ? TapDeskColors.highlight
                    : TapDeskColors.surfaceElevated,
                borderRadius: BorderRadius.circular(TapDeskSpace.radiusPill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
