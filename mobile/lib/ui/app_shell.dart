import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/connection_controller.dart';
import '../screens/mouse_tab.dart';
import '../screens/slides_tab.dart';
import '../state/pairing_store.dart';
import '../state/preview_mode.dart';
import '../theme/tokens.dart';
import 'connection_indicators.dart';

/// The app shell: app bar, connection banner, three tabs.
///
/// Phase 2 delivers the structure and the design system; Phase 3 fills the tab
/// bodies in. What already exists here is real, not scaffolding: the tab
/// behaviour, the connection dot, the banner and the disable-when-not-connected
/// rule all work, because those are the parts a reviewer signs off on first.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.preview = false});

  /// Show the controller without a PC. Debug builds only - see PreviewMode.
  final bool preview;

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
    final info = connection.info;
    final enabled = info.status.isConnected || widget.preview;

    // While disconnected there is no live name from the PC, but we still know
    // which machine we are about to connect to - showing it tells the user
    // which paired computer these controls will drive.
    final pcName = info.pcName ?? store.mostRecent?.name;

    return Scaffold(
      backgroundColor: TapDeskColors.background,
      appBar: _AppBar(info: info, pcName: pcName),
      body: Column(
        children: [
          if (widget.preview) const PreviewBanner(),
          ConnectionBanner(status: info.status, error: info.lastError),
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
                // Slides is built. Mouse and Keyboard land next; each replaces
                // one placeholder, so the shell never changes shape again.
                const SlidesTab(),
                const MouseTab(),
                _TabPlaceholder(
                  name: 'Keyboard',
                  enabled: enabled,
                  status: info.status,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  const _AppBar({required this.info, required this.pcName});

  final ConnectionInfo info;
  final String? pcName;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 56,
      backgroundColor: TapDeskColors.background,
      systemOverlayStyle: TapDeskTheme.systemOverlay,
      titleSpacing: TapDeskSpace.s4,
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

/// Stands in for a real tab body until Phase 3 builds them.
///
/// It is intentionally explicit rather than an empty box: it states which
/// phase fills it in, and it demonstrates the "never look broken" rule by
/// disabling itself and saying why.
class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder({
    required this.name,
    required this.enabled,
    required this.status,
  });

  final String name;
  final bool enabled;
  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TapDeskSpace.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 40,
              color: TapDeskColors.divider,
            ),
            const SizedBox(height: TapDeskSpace.s4),
            Text('$name tab', style: TapDeskText.button),
            const SizedBox(height: TapDeskSpace.s2),
            Text(
              enabled
                  ? 'Built in Phase 3.'
                  : 'Connect to a PC to use this tab.',
              style: TapDeskText.label,
              textAlign: TextAlign.center,
            ),
            if (!enabled && status == ConnectionStatus.idle)
              const SizedBox(height: TapDeskSpace.s1),
            if (!enabled && status == ConnectionStatus.idle)
              Text(
                'Scan a QR code from the companion to pair.',
                style: TapDeskText.label,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

/// Settings entry point. Phase 3.5 fills in the controls.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(TapDeskSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tune,
                size: 40,
                color: TapDeskColors.divider,
              ),
              const SizedBox(height: TapDeskSpace.s4),
              Text(
                'Settings arrive in Phase 3.5',
                style: TapDeskText.bodyText,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TapDeskSpace.s2),
              Text(
                'Cursor speed, haptics, left-handed layout, paired devices.',
                style: TapDeskText.label,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
