import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../theme/tokens.dart';
import '../ui/haptics.dart';

/// The settings screen.
///
/// Two kinds of setting live here and they behave differently, which is the
/// single thing most likely to be got wrong:
///
///   * **This phone's** - haptics, left-handed layout, keeping the screen on.
///     Applied immediately, saved on the device, and they work with no
///     computer anywhere.
///
///   * **The computer's** - cursor speed, acceleration, Safe Mode. Applied by
///     the companion, so the values shown are the ones it reported rather than
///     the ones the phone asked for, and they say plainly when there is no
///     computer to ask.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Scaffold(
      backgroundColor: TapDeskColors.background,
      appBar: AppBar(
        backgroundColor: TapDeskColors.background,
        systemOverlayStyle: TapDeskTheme.systemOverlay,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: TapDeskColors.textMuted,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Settings', style: TapDeskText.button),
      ),
      // Until stored preferences are read, showing controls built from defaults
      // and correcting them a frame later makes the app look like it forgets
      // the user's settings on every launch.
      body: !settings.isLoaded
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                TapDeskSpace.s4,
                TapDeskSpace.s2,
                TapDeskSpace.s4,
                TapDeskSpace.s6,
              ),
              children: [
                _SectionLabel('This phone'),
                _Card(children: [
                  _ToggleRow(
                    title: 'Haptic feedback',
                    subtitle:
                        'A short buzz when you press a key or button. Useful for finding a control without looking.',
                    value: settings.haptics,
                    onChanged: (value) {
                      settings.setHaptics(value);
                      // Feedback that the haptic toggle works, on the one
                      // press where it is about to stop happening.
                      if (value) Haptics.confirm();
                    },
                  ),
                  const _RowDivider(),
                  _ToggleRow(
                    title: 'Left-handed layout',
                    subtitle:
                        'Puts the click buttons and scroll wheel under your left thumb instead of your right.',
                    value: settings.leftHanded,
                    onChanged: settings.setLeftHanded,
                  ),
                  const _RowDivider(),
                  _ToggleRow(
                    title: 'Keep the screen on',
                    subtitle:
                        'Stops the display sleeping while you are connected, so it cannot lock mid-lecture.',
                    value: settings.keepAwake,
                    onChanged: settings.setKeepAwake,
                  ),
                ]),
                const SizedBox(height: TapDeskSpace.s5),
                _SectionLabel('The computer'),
                _Card(children: [
                  _SliderRow(
                    title: 'Cursor speed',
                    subtitle: settings.isConnectedToComputer
                        ? 'How far the pointer travels when you push the stick all the way.'
                        : 'Connect to change this. The computer decides how fast it moves.',
                    value: settings.cursorSpeed,
                    min: AppSettings.minCursorSpeed,
                    max: AppSettings.maxCursorSpeed,
                    enabled: settings.isConnectedToComputer,
                    format: (v) => '${v.toStringAsFixed(2)}x',
                    onChanged: settings.setCursorSpeed,
                  ),
                  const _RowDivider(),
                  _SliderRow(
                    title: 'Acceleration',
                    subtitle: settings.isConnectedToComputer
                        ? 'How much of the travel is fine control near the centre. Higher is finer.'
                        : 'Connect to change this.',
                    value: settings.accel,
                    min: AppSettings.minAccel,
                    max: AppSettings.maxAccel,
                    enabled: settings.isConnectedToComputer,
                    format: (v) => v.toStringAsFixed(2),
                    onChanged: settings.setAccel,
                  ),
                  const _RowDivider(),
                  _ToggleRow(
                    title: 'Safe Mode',
                    subtitle: 'Blocks shortcuts that could lock you out or open a dangerous '
                        'window, such as Win+R. Turning it on also releases any key you are holding.',
                    value: settings.safeMode,
                    enabled: settings.isConnectedToComputer,
                    onChanged: settings.setSafeMode,
                  ),
                ]),
                const SizedBox(height: TapDeskSpace.s5),
                _SectionLabel('Pairing'),
                _Card(children: [
                  _ForgetRow(settings: settings),
                ]),
                const SizedBox(height: TapDeskSpace.s5),
                const _Diagnostics(),
              ],
            ),
    );
  }
}

/// The paired-device list.
///
/// There is exactly one entry and it is this phone. Every paired device lives
/// on the computer, which owns the keys, so the only entry the phone can
/// truthfully show is its own - listing devices it does not have the keys for
/// would be a list of things that cannot be revoked from here.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: TapDeskSpace.s1,
        bottom: TapDeskSpace.s2,
        top: TapDeskSpace.s2,
      ),
      child: Text(
        text.toUpperCase(),
        style: TapDeskText.label.copyWith(
          color: TapDeskColors.textMuted,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TapDeskColors.surface,
        borderRadius: BorderRadius.circular(TapDeskSpace.radiusCard),
        border: Border.all(color: TapDeskColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: TapDeskColors.divider);
  }
}

/// A titled on/off row.
///
/// Disabled when [enabled] is false rather than hidden: a control that vanishes
/// when it is unavailable leaves the user wondering whether this version has
/// it, which is a worse answer than "greyed out until you connect".
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TapDeskSpace.s4,
        vertical: TapDeskSpace.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TapDeskText.bodyText.copyWith(
                    color: enabled
                        ? TapDeskColors.text
                        : TapDeskColors.textMuted,
                  ),
                ),
                const SizedBox(height: TapDeskSpace.s1),
                Text(subtitle, style: TapDeskText.label),
              ],
            ),
          ),
          const SizedBox(width: TapDeskSpace.s3),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: TapDeskColors.primary,
          ),
        ],
      ),
    );
    return Semantics(
      enabled: enabled,
      label: title,
      toggled: value,
      child: content,
    );
  }
}

/// A titled slider row.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.format,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TapDeskSpace.s4,
        TapDeskSpace.s3,
        TapDeskSpace.s4,
        TapDeskSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TapDeskText.bodyText.copyWith(
                    color: enabled
                        ? TapDeskColors.text
                        : TapDeskColors.textMuted,
                  ),
                ),
              ),
              Text(
                format(value),
                style: TapDeskText.monoText.copyWith(
                  color: enabled
                      ? TapDeskColors.highlight
                      : TapDeskColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: TapDeskSpace.s1),
          Text(subtitle, style: TapDeskText.label),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: TapDeskColors.primary,
              inactiveTrackColor: TapDeskColors.divider,
              thumbColor:
                  enabled ? TapDeskColors.highlight : TapDeskColors.textMuted,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              // The companion's step is finer than a finger can manage, and a
              // slider that snaps in visible jumps feels broken.
              divisions: 60,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Unpair this phone from the computer.
///
/// Behind a confirmation because it cannot be undone from here: the companion
/// destroys the device key, and getting it back means walking to the computer
/// and scanning its QR code again.
class _ForgetRow extends StatelessWidget {
  const _ForgetRow({required this.settings});

  final AppSettings settings;

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TapDeskColors.surfaceElevated,
        title: const Text('Unpair this phone?', style: TapDeskText.button),
        content: const Text(
          'The computer will forget this phone. To use it again you will have '
          'to go to the computer and scan its pairing code again.',
          style: TapDeskText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TapDeskText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Unpair',
              style: TextStyle(
                fontFamily: TapDeskText.body,
                color: TapDeskColors.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await settings.forgetThisDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _confirm(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TapDeskSpace.s4,
          vertical: TapDeskSpace.s4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This phone',
                    style: TextStyle(
                      fontFamily: TapDeskText.body,
                      fontSize: 15,
                      color: TapDeskColors.text,
                    ),
                  ),
                  const SizedBox(height: TapDeskSpace.s1),
                  Text(
                    settings.isConnectedToComputer
                        ? 'Paired. Tap to unpair.'
                        : 'Not paired to a computer right now.',
                    style: TapDeskText.label,
                  ),
                ],
              ),
            ),
            const Icon(Icons.logout, color: TapDeskColors.error, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Facts about the connection, for when something is not working.
///
/// Present because every other failure in this app is invisible: a dead socket
/// and a working one look identical until you notice the pointer is not moving.
class _Diagnostics extends StatelessWidget {
  const _Diagnostics();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          settings.isConnectedToComputer
              ? 'These are the settings the computer reported.'
              : 'Cursor speed, acceleration and Safe Mode live on the computer, '
                  'so they need a connection. The switches above work without one.',
          style: TapDeskText.label,
        ),
      ],
    );
  }
}