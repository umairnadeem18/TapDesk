import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/tokens.dart';
import '../transport/event_sink.dart';
import '../transport/tapdesk_event.dart';
import '../ui/haptics.dart';
import '../widgets/analog_stick.dart';
import '../widgets/mouse_controls.dart';

/// The Mouse tab: analog stick, left/right buttons, scroll strip.
///
/// Left-handed mode (plan task 3.3.7) swaps the two buttons. The setting
/// arrives with the rest of Settings in Phase 3.5; the layout already mirrors,
/// so wiring it is a one-line change rather than a redesign.
class MouseTab extends StatelessWidget {
  const MouseTab({super.key, this.leftHanded = false});

  final bool leftHanded;

  @override
  Widget build(BuildContext context) {
    final sink = context.watch<EventSink>();
    final enabled = sink.isReady;

    final left = MouseButtonWidget(
      button: MouseButton.left,
      enabled: enabled,
      onEvent: (e) {
        Haptics.tap();
        sink.send(e);
      },
    );

    final right = MouseButtonWidget(
      button: MouseButton.right,
      enabled: enabled,
      onEvent: (e) {
        Haptics.tap();
        sink.send(e);
      },
    );

    return Padding(
      padding: const EdgeInsets.all(TapDeskSpace.s4),
      child: Column(
        children: [
          // Stick and scroll strip share the upper area, scroll to the right
          // of the stick so it falls under a right thumb.
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnalogStick(
                  enabled: enabled,
                  onValue: (x, y) => sink.send(StickEvent(x, y)),
                ),
                const SizedBox(width: TapDeskSpace.s4),
                ScrollStrip(
                  enabled: enabled,
                  onScroll: (ticks) => sink.send(ScrollEvent(ticks.round())),
                ),
              ],
            ),
          ),
          const SizedBox(height: TapDeskSpace.s4),
          // Buttons at the bottom, where thumbs rest, and far apart so a
          // mis-tap cannot fire the wrong one.
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (leftHanded) ...[
                  right,
                  const SizedBox(width: TapDeskSpace.s4),
                  left,
                ] else ...[
                  left,
                  const SizedBox(width: TapDeskSpace.s4),
                  right,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
