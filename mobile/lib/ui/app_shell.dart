import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state/connection_controller.dart';
import '../transport/event_sink.dart';
import '../screens/keyboard_tab.dart';
import '../screens/mouse_tab.dart';
import '../screens/settings_screen.dart';
import '../screens/slides_tab.dart';
import '../state/pairing_store.dart';
import '../state/preview_mode.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import 'connection_indicators.dart';
import 'diagnostics_strip.dart';

/// The app shell: app bar, connection banner, three tabs.
///
/// Phase 2 delivers the structure and the design system; Phase 3 fills in the
/// tab bodies. What already exists here is real, not scaffolding: the tab
/// behaviour, the connection dot, the banner and the disable-when-not-connected
/// rule all work, because those are the parts a reviewer signs off on first.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.preview = false, this.onDisconnect});

  /// Show the controller without a PC. Debug builds only - see PreviewMode.
  final bool preview;

  /// Called when the user chooses to disconnect and leave.
  ///
  /// Owning this in the shell rather than reaching for the sink keeps the
  /// "are you sure?" decision next to the button that raised it.
  final Future<void> Function()? onDisconnect;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Which tab is showing. Held here rather than derived, so switching tabs
  /// does not rebuild into a different tab just because the connection
  /// changed while the user was on it.
  int _index = 0;

  static const List<String> _tabs = ['Slides', 'Mouse', 'Keyboard'];

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    final store = context.watch<PairingStore>();
    final sink = context.watch<EventSink>();
    final info = connection.info;
    final enabled = info.status.isConnected || widget.preview || sink.isReady;

    // While disconnected there is no live name from the PC, but we still know
    // which machine we are about to connect to - showing it tells the user
    // which paired computer these controls will drive.
    final pcName = info.pcName ?? store.mostRecent?.name;

    // Wake lock while connected: a sleeping screen drops the session, and a
    // presenter who has to unlock the phone to advance a slide has discovered
    // the product's core job is inconvenient.
    //
    // The user's choice in Settings as well as the connection: somebody using
    // the phone at a desk may well want it to time out like anything else, and
    // an app that overrides the system setting on their behalf is the kind of
    // thing that ends up reported as a battery complaint.
    final settings = context.watch<AppSettings>();
    final connected = (sink.isReady || widget.preview) && settings.keepAwake;

    return _KeepScreenAwake(
      enabled: connected,
      child: PopScope(
        // Back means "stop controlling this computer", not "leave the app" -
        // so it is confirmed rather than acted on immediately. Disconnecting
        // by accident mid-lecture is worse than one extra tap.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDisconnect();
        },
        child: Scaffold(
          backgroundColor: TapDeskColors.background,
          appBar: _AppBar(
            info: info,
            pcName: pcName,
            onDisconnect: _confirmDisconnect,
          ),
          body: Column(
            children: [
              if (widget.preview) const PreviewBanner(),
              ConnectionBanner(status: info.status, error: info.lastError),
              const DiagnosticsStrip(),
              _TabBar(
                tabs: _tabs,
                index: _index,
                enabled: enabled,
                onChanged: (i) => setState(() => _index = i),
              ),
              // Expanded so the tab body owns the remaining height and the
              // keyboard can shrink it correctly with adjustResize.
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    // Deliberately not `const`. An identical widget instance
                    // makes Flutter skip the subtree entirely, so a rebuild
                    // driven by the connection would leave the already-built
                    // tabs untouched - stale controls the user cannot use, with
                    // no indication why.
                    SlidesTab(),
                    MouseTab(leftHanded: settings.leftHanded),
                    KeyboardTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TapDeskColors.surfaceElevated,
        title: const Text('Disconnect?', style: TapDeskText.button),
        content: const Text(
          'TapDesk will stop controlling this computer. You can connect again '
          'at any time.',
          style: TapDeskText.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay connected', style: TapDeskText.button),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: TapDeskColors.primary),
            child: const Text('Disconnect', style: TapDeskText.button),
          ),
        ],
      ),
    );

    if (leave != true) return;
    await widget.onDisconnect?.call();
  }
}

/// Holds the screen awake while the phone is driving a computer.
///
/// A sleeping screen is a dropped session: Android suspends the socket, the
/// companion releases every held key and button, and the user returns to a
/// "connecting" banner. Worse, a presenter who has to unlock the phone to
/// advance a slide has discovered the product's core job is inconvenient.
///
/// Only while connected. On the pairing screen it would drain a battery for
/// nothing, and users find a screen that will not sleep alarming.
class _KeepScreenAwake extends StatefulWidget {
  const _KeepScreenAwake({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_KeepScreenAwake> createState() => _KeepScreenAwakeState();
}

class _KeepScreenAwakeState extends State<_KeepScreenAwake> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(covariant _KeepScreenAwake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _apply();
  }

  Future<void> _apply() async {
    if (_on == widget.enabled) return;
    _on = widget.enabled;
    try {
      if (_on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Not every device supports it. A screen that sleeps is a far better
      // outcome than an app that crashes because it could not prevent it.
    }
  }

  @override
  void dispose() {
    // Never leave the screen pinned on after the app is gone.
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Says, unmistakably, that nothing is connected.
///
/// Preview mode enables the controls so the design can be judged on a device,
/// which is the whole point. It must therefore be impossible to mistake for a
/// working connection - the design system's rule is that the user is never
/// left guessing whether their input is going anywhere.
class PreviewBanner extends StatelessWidget {
  const PreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
            TapDeskSpace.s4, TapDeskSpace.s2, TapDeskSpace.s2, TapDeskSpace.s2),
        color: TapDeskColors.surface,
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined,
                size: 18, color: TapDeskColors.warning),
            const SizedBox(width: TapDeskSpace.s3),
            Expanded(
              child: Text(
                'Preview — no computer connected. Buttons work, nothing is sent.',
                style: TapDeskText.label,
              ),
            ),
            TextButton(
              // No navigation here: _Root watches PreviewMode, so turning it
              // off rebuilds the tree back to the pairing screen on its own.
              // Pushing a route here left a blank screen instead.
              onPressed: () => context.read<PreviewMode>().exit(),
              style: TextButton.styleFrom(
                foregroundColor: TapDeskColors.primary,
                minimumSize: const Size(72, TapDeskSpace.minTouchTarget),
              ),
              child: const Text('Exit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({required this.info, required this.pcName, this.onDisconnect});

  final ConnectionInfo info;
  final String? pcName;
  final VoidCallback? onDisconnect;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: TapDeskColors.background,
      systemOverlayStyle: TapDeskTheme.systemOverlay,
      titleSpacing: TapDeskSpace.s4,
      // A visible back arrow, not just the system gesture. The user asked for a
      // way to disconnect that is always there; relying on Android's back
      // gesture or button means a presenter holding the phone in one hand has
      // to find it by feel.
      leading: onDisconnect == null
          ? null
          : IconButton(
              tooltip: 'Disconnect and go back',
              iconSize: 24,
              color: TapDeskColors.textMuted,
              onPressed: onDisconnect,
              icon: const Icon(Icons.arrow_back),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              pcName ?? 'TapDesk',
              // Truncated rather than wrapped: a long PC name must not push
              // the connection indicator off a narrow screen.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TapDeskText.bodyText.copyWith(
                color: pcName == null
                    ? TapDeskColors.textMuted
                    : TapDeskColors.text,
              ),
            ),
          ),
          const SizedBox(width: TapDeskSpace.s3),
          ConnectionDot(status: info.status),
          const SizedBox(width: TapDeskSpace.s2),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Settings',
          iconSize: 24,
          color: TapDeskColors.textMuted,
          onPressed: () => _openSettings(context),
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: TapDeskSpace.s2),
      ],
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
        settings: const RouteSettings(name: '/settings'),
      ),
    );
  }
}

/// The three-way tab bar.
///
/// The active tab is a filled green pill rather than an underline, because the
/// design system requires it to be readable from across a room.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.index,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> tabs;
  final int index;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: TapDeskSpace.s3),
      decoration: const BoxDecoration(
        color: TapDeskColors.surface,
        border: Border(
          bottom: BorderSide(color: TapDeskColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TapDeskSpace.s1),
                child: _TabButton(
                  label: tabs[i],
                  selected: i == index,
                  enabled: enabled,
                  animate: !reduceMotion,
                  onTap: () => onChanged(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.animate,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final bool animate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Tabs stay tappable when disconnected — a user must be able to switch and
    // see the "not connected" state on each tab. Only the controls *inside*
    // the tabs are disabled.
    final bg = selected ? TapDeskColors.primary : Colors.transparent;
    final fg = selected
        ? TapDeskColors.text
        : (enabled ? TapDeskColors.textMuted : TapDeskColors.textMuted);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(TapDeskSpace.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(TapDeskSpace.radiusPill),
          onTap: onTap,
          // No splash on a disabled tab: it would imply the control works.
          splashColor: Colors.transparent,
          child: Container(
            height: TapDeskSpace.minTouchTarget,
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: animate ? TapDeskDuration.tabChange : Duration.zero,
              style: TapDeskText.button.copyWith(color: fg),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
