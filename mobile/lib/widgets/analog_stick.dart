import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The analog stick.
///
/// Behaviour comes from `docs/protocol.md` section 4.2:
///  - values are -1..1, **+y is up**
///  - a value is streamed at ~60 Hz while the stick is off-centre
///  - a zero is sent on release, so a stream that stops mid-deflection cannot
///    leave the cursor sliding across the screen forever
///
/// The knob deliberately follows the thumb with **no easing**. Any smoothing
/// makes the cursor feel like it is lagging, which is the single most common
/// complaint about remote-control apps.
class AnalogStick extends StatefulWidget {
  const AnalogStick({
    super.key,
    required this.onValue,
    this.size = 180,
    this.deadZone = 0.08,
    this.enabled = true,
  });

  /// Called at 60 Hz with the current deflection, -1..1 on each axis.
  final void Function(double x, double y) onValue;

  final double size;

  /// Below this magnitude nothing is sent. Stops a resting thumb from
  /// producing a slow drift across the screen.
  final double deadZone;

  final bool enabled;

  @override
  State<AnalogStick> createState() => _AnalogStickState();
}

class _AnalogStickState extends State<AnalogStick>
    with SingleTickerProviderStateMixin {
  /// Current deflection, -1..1. Zero means centred.
  double _x = 0;
  double _y = 0;

  bool _active = false;
  Timer? _stream;

  /// Set once a non-zero value has gone out, so release knows to send the
  /// zero that stops the cursor.
  bool _sentNonZero = false;

  double get _radius => widget.size / 2;

  /// How far the knob can travel from centre.
  double get _knobTravel => _radius - 38;

  @override
  void didUpdateWidget(covariant AnalogStick oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Losing the connection mid-drag must not leave the stick stuck over.
    if (oldWidget.enabled && !widget.enabled && _active) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }

  void _onStart(DragStartDetails details) {
    if (!widget.enabled) return;
    setState(() => _active = true);
    _startStreaming();
    _update(details.localPosition);
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    _update(details.localPosition);
  }

  void _onEnd() {
    if (!widget.enabled) return;
    _stop();
  }

  void _update(Offset localPosition) {
    final centre = Offset(_radius, _radius);
    final delta = localPosition - centre;

    // Normalise by the travel distance, not the full radius: otherwise the
    // value could never reach ±1 because the knob stops short of the edge.
    var nx = delta.dx / _knobTravel;
    var ny = -delta.dy / _knobTravel;

    final magnitude = math.sqrt(nx * nx + ny * ny);
    if (magnitude > 1) {
      // Clamp radially so a diagonal drag does not distort speed.
      nx /= magnitude;
      ny /= magnitude;
    }

    if (magnitude < widget.deadZone) {
      nx = 0;
      ny = 0;
    }

    setState(() {
      _x = nx;
      _y = ny;
    });
  }

  void _startStreaming() {
    _stream?.cancel();
    // 60 Hz per the protocol. A Timer rather than a frame callback because the
    // rate is part of the contract with the PC, not a rendering concern.
    _stream = Timer.periodic(TapDeskDuration.stickTick, (_) {
      if (!mounted || !_active) return;
      // The protocol says stick values are "sent only while the stick is
      // off-centre". Emitting a stream of zeros from a resting thumb wastes
      // frames and tells the PC nothing.
      if (_x == 0 && _y == 0) return;
      widget.onValue(_x, _y);
      _sentNonZero = true;
    });
  }

  void _stop() {
    _stream?.cancel();
    _stream = null;

    if (_sentNonZero) {
      // The zero that tells the PC to stop moving the cursor.
      widget.onValue(0, 0);
    }
    _sentNonZero = false;

    if (mounted) {
      setState(() {
        _active = false;
        _x = 0;
        _y = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final knobOffset = Offset(_x, -_y) * _knobTravel;
    final resting = _x == 0 && _y == 0;

    return Semantics(
      label: 'Analog stick',
      hint: 'Drag to move the mouse cursor',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: widget.enabled ? _onStart : null,
        onPanUpdate: widget.enabled ? _onUpdate : null,
        onPanEnd: widget.enabled ? (_) => _onEnd() : null,
        onPanCancel: widget.enabled ? _onEnd : null,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Base
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: TapDeskColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.enabled
                        ? TapDeskColors.primary
                        : TapDeskColors.divider,
                    width: TapDeskSpace.borderWidth,
                  ),
                ),
              ),
              // Faint orientation guides, so the user knows where centre is.
              if (!resting) ...[
                Container(
                  width: widget.size - 20,
                  height: 1,
                  color: TapDeskColors.textMuted.withValues(alpha: 0.12),
                ),
                Container(
                  width: 1,
                  height: widget.size - 20,
                  color: TapDeskColors.textMuted.withValues(alpha: 0.12),
                ),
              ],
              // Knob
              Positioned(
                left: _radius + knobOffset.dx - 38,
                top: _radius + knobOffset.dy - 38,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? TapDeskColors.primary
                        : TapDeskColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: TapDeskColors.highlight, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
