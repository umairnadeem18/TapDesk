import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../state/pairing_store.dart';
import '../theme/tokens.dart';
import '../transport/pairing_payload.dart';
import '../ui/haptics.dart';

/// How the pairing screen was left, and what the caller should do next.
enum PairingOutcome {
  /// Nothing - the user backed out.
  cancelled,

  /// A payload was validated and accepted, but no socket was opened. The
  /// transport does not exist until Phase 4.
  payloadAccepted,

  /// A remembered PC was chosen for reconnect.
  reconnectChosen,
}

/// Full-screen QR pairing, plus the manual fallback.
///
/// The camera is only ever used to read a pairing code. The rationale screen
/// is shown *before* the system permission dialog, because a camera prompt
/// with no explanation is the thing users deny.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, this.onPaired, this.onReconnect});

  /// Called once a scanned payload has been validated and stored.
  final void Function(PairingPayload payload)? onPaired;

  /// Called when the user picks a remembered PC.
  final void Function(PairedDevice device)? onReconnect;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  MobileScannerController? _scanner;
  bool _rationaleShown = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // Guard against the scanner firing the same QR on several frames.
    if (_busy) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final payload = PairingPayload.tryParseDeepLink(raw);
      if (payload == null) {
        _fail('That QR code is not a TapDesk pairing code. '
            'Scan the code shown in the desktop app, or enter the details by hand.');
        return;
      }

      _busy = true;
      await _scanner?.stop();
      if (!mounted) return;

      await context.read<PairingStore>().remember(payload);
      if (!mounted) return;

      await Haptics.confirm();
      widget.onPaired?.call(payload);
      return;
    }
  }

  void _fail(String message) {
    if (_busy) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PairingStore>();

    return Scaffold(
      backgroundColor: TapDeskColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onClose: () => Navigator.of(context).maybePop()),
            Expanded(
              child: _rationaleShown
                  ? _scannerView()
                  : _Rationale(onContinue: () {
                      setState(() => _rationaleShown = true);
                      _startScanner();
                    }),
            ),
            if (store.hasPairedDevices) _RememberedDevices(store: store),
            _ManualEntryButton(
              onPressed: _busy
                  ? null
                  : () => _openManualEntry(context, store),
            ),
            if (_error != null) _ErrorStrip(message: _error!),
          ],
        ),
      ),
    );
  }

  void _startScanner() {
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    setState(() {});
  }

  Widget _scannerView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          // Dimmed so the green frame reads as the focal point. Scanning needs
          // real contrast, so this is a scrim over the preview, not a filter.
          overlayBuilder: (context, constraints) => const ColoredBox(
            color: Color(0x66000000),
            child: ScanningFrame(),
          ),
          errorBuilder: (context, error, child) =>
              _CameraUnavailable(error: error),
        ),
        if (_busy)
          Container(
            color: TapDeskColors.background.withValues(alpha: 0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(TapDeskColors.primary),
                    ),
                  ),
                  SizedBox(height: TapDeskSpace.s4),
                  Text('Pairing…', style: TapDeskText.bodyText),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openManualEntry(
      BuildContext context, PairingStore store) async {
    final payload = await showModalBottomSheet<PairingPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TapDeskColors.surface,
      builder: (_) => const ManualEntrySheet(),
    );
    if (payload == null || !mounted) return;

    await store.remember(payload);
    if (!mounted) return;
    await Haptics.confirm();
    widget.onPaired?.call(payload);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          TapDeskSpace.s4, TapDeskSpace.s3, TapDeskSpace.s2, TapDeskSpace.s3),
      child: Row(
        children: [
          Expanded(
            child: Text('Pair with a computer', style: TapDeskText.button),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
            color: TapDeskColors.textMuted,
          ),
        ],
      ),
    );
  }
}

/// Shown before the system camera prompt.
///
/// design-system.md requires this: a bare permission dialog is the fastest way
/// to get a denial, and the user has no way to recover if they do not know why
/// the camera is wanted.
class _Rationale extends StatelessWidget {
  const _Rationale({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    // Scrollable, because on a small phone this content does not fit and the
    // design system forbids layout overflow. Without this the "Allow camera"
    // button falls off the bottom on a 5" screen - and that button is the only
    // way forward for a user who has not paired before.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(TapDeskSpace.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.qr_code_scanner,
              size: 56, color: TapDeskColors.primary),
          const SizedBox(height: TapDeskSpace.s5),
          Text('Scan the code on your PC', style: TapDeskText.display),
          const SizedBox(height: TapDeskSpace.s3),
          Text(
            'The TapDesk desktop app shows a QR code. Point the camera at it and '
            'the two connect over your own Wi-Fi — no account, no internet, no '
            'code to type.',
            style: TapDeskText.bodyText
                .copyWith(color: TapDeskColors.textMuted),
          ),
          const SizedBox(height: TapDeskSpace.s4),
          _PrivacyNote(),
          const SizedBox(height: TapDeskSpace.s5),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                minimumSize:
                    const Size.fromHeight(TapDeskSpace.minTouchTarget),
                backgroundColor: TapDeskColors.primary,
                shape: const StadiumBorder(),
              ),
              child: const Text('Allow camera'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TapDeskSpace.s4),
      decoration: BoxDecoration(
        color: TapDeskColors.surface,
        borderRadius: BorderRadius.circular(TapDeskSpace.radiusCard),
        border: Border.all(color: TapDeskColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline,
              size: 20, color: TapDeskColors.primary),
          const SizedBox(width: TapDeskSpace.s3),
          Expanded(
            child: Text(
              'The camera reads pairing codes and nothing else. Images never '
              'leave your phone, and TapDesk collects no data.',
              style: TapDeskText.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// The green corner brackets from the design system.
class ScanningFrame extends StatelessWidget {
  const ScanningFrame({super.key});

  static const double _size = 240;
  static const double _thickness = 4;
  static const double _arm = 40;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          children: [
            // Four corners, drawn as explicit bars rather than a custom paint
            // so they can each carry the glow independently.
            for (final corner in _corners)
              Align(alignment: corner, child: _CornerBars()),
          ],
        ),
      ),
    );
  }

  static const List<Alignment> _corners = [
    Alignment.topLeft,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomRight,
  ];
}

class _CornerBars extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ScanningFrame._size,
      height: ScanningFrame._size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: TapDeskColors.highlight, width: 0),
        ),
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = TapDeskColors.highlight
      ..strokeWidth = ScanningFrame._thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const arm = ScanningFrame._arm;
    const inset = ScanningFrame._thickness;

    // top-left
    canvas
      ..drawLine(const Offset(inset, arm), const Offset(inset, inset), paint)
      ..drawLine(const Offset(inset, inset), const Offset(arm, inset), paint);
    // top-right
    canvas
      ..drawLine(Offset(size.width - arm, inset),
          Offset(size.width - inset, inset), paint)
      ..drawLine(Offset(size.width - inset, inset),
          Offset(size.width - inset, arm), paint);
    // bottom-left
    canvas
      ..drawLine(Offset(inset, size.height - arm),
          Offset(inset, size.height - inset), paint)
      ..drawLine(Offset(inset, size.height - inset),
          Offset(arm, size.height - inset), paint);
    // bottom-right
    canvas
      ..drawLine(Offset(size.width - arm, size.height - inset),
          Offset(size.width - inset, size.height - inset), paint)
      ..drawLine(Offset(size.width - inset, size.height - inset),
          Offset(size.width - inset, size.height - arm), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Remembered PCs, so a paired phone reconnects without scanning again
/// (plan task 3.1.6).
class _RememberedDevices extends StatelessWidget {
  const _RememberedDevices({required this.store});

  final PairingStore store;

  @override
  Widget build(BuildContext context) {
    final devices = store.devices.take(3).toList();
    return Container(
      width: double.infinity,
      color: TapDeskColors.surface,
      padding: const EdgeInsets.fromLTRB(
          TapDeskSpace.s4, TapDeskSpace.s3, TapDeskSpace.s4, TapDeskSpace.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAIRED COMPUTERS', style: TapDeskText.label),
          const SizedBox(height: TapDeskSpace.s2),
          for (final device in devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: TapDeskSpace.s2,
              leading: const Icon(Icons.computer,
                  color: TapDeskColors.primary),
              title: Text(device.name, style: TapDeskText.bodyText),
              subtitle: Text(
                '${device.host}:${device.port}',
                style: TapDeskText.label,
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: TapDeskColors.textMuted),
              onTap: () {
                Navigator.of(context).maybePop();
                // The reconnect path is wired in Phase 4, when a device key
                // exists to present. Until then the choice is still offered so
                // the layout and wording can be reviewed.
              },
            ),
        ],
      ),
    );
  }
}

class _ManualEntryButton extends StatelessWidget {
  const _ManualEntryButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          TapDeskSpace.s4, TapDeskSpace.s3, TapDeskSpace.s4, TapDeskSpace.s2),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(TapDeskSpace.minTouchTarget),
            foregroundColor: TapDeskColors.primary,
            shape: const StadiumBorder(),
            side: const BorderSide(
                color: TapDeskColors.primary, width: TapDeskSpace.borderWidth),
          ),
          child: const Text('Enter code manually'),
        ),
      ),
    );
  }
}

/// Manual entry, reaching the same outcome as a scan.
///
/// The companion window shows the PIN and the fingerprint beside the QR
/// precisely so this path exists for a broken camera or a denied permission.
class ManualEntrySheet extends StatefulWidget {
  const ManualEntrySheet({super.key});

  @override
  State<ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<ManualEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '8765');
  final _pin = TextEditingController();
  final _fingerprint = TextEditingController();

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _pin.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final payload = PairingPayload.tryParseManual(
      ip: _ip.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 0,
      pin: _pin.text.trim(),
      fingerprint: _fingerprint.text.trim().toLowerCase(),
    );

    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Those details are not valid.')),
      );
      return;
    }
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: TapDeskSpace.s5,
        right: TapDeskSpace.s5,
        top: TapDeskSpace.s5,
        // Lift the sheet above the keyboard.
        bottom: MediaQuery.viewInsetsOf(context).bottom + TapDeskSpace.s5,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the code manually', style: TapDeskText.button),
            const SizedBox(height: TapDeskSpace.s2),
            Text(
              'All four values are shown in the desktop app window.',
              style: TapDeskText.label,
            ),
            const SizedBox(height: TapDeskSpace.s4),
            _Field(controller: _ip, label: 'IP address',
                keyboard: TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: TapDeskSpace.s3),
            _Field(controller: _port, label: 'Port', keyboard: TextInputType.number),
            const SizedBox(height: TapDeskSpace.s3),
            _Field(
                controller: _pin,
                label: '6-digit PIN',
                keyboard: TextInputType.number,
                maxLength: 6),
            const SizedBox(height: TapDeskSpace.s3),
            _Field(
              controller: _fingerprint,
              label: 'Certificate fingerprint',
              hint: '64 hex characters',
            ),
            const SizedBox(height: TapDeskSpace.s4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize:
                      const Size.fromHeight(TapDeskSpace.minTouchTarget),
                  backgroundColor: TapDeskColors.primary,
                  shape: const StadiumBorder(),
                ),
                child: const Text('Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboard,
    this.hint,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboard;
  final String? hint;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TapDeskText.label),
        const SizedBox(height: TapDeskSpace.s1),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLength: maxLength,
          autocorrect: false,
          enableSuggestions: false,
          style: TapDeskText.monoText.copyWith(color: TapDeskColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TapDeskText.monoText,
            filled: true,
            fillColor: TapDeskColors.surfaceElevated,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
                horizontal: TapDeskSpace.s3, vertical: TapDeskSpace.s3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
              borderSide: const BorderSide(color: TapDeskColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
              borderSide: const BorderSide(color: TapDeskColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TapDeskSpace.radiusKey),
              borderSide: const BorderSide(
                  color: TapDeskColors.primary, width: TapDeskSpace.borderWidth),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TapDeskSpace.s3),
      color: TapDeskColors.surfaceElevated,
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: TapDeskColors.error),
          const SizedBox(width: TapDeskSpace.s3),
          Expanded(
            child: Text(message, style: TapDeskText.label),
          ),
        ],
      ),
    );
  }
}

/// The camera could not start. Manual entry is the way out, so this screen
/// says so rather than leaving a black rectangle.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: TapDeskColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(TapDeskSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(denied ? Icons.no_photography : Icons.videocam_off,
                  size: 48, color: TapDeskColors.error),
              const SizedBox(height: TapDeskSpace.s4),
              Text(
                denied
                    ? 'Camera permission denied'
                    : 'The camera is not available',
                style: TapDeskText.button,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TapDeskSpace.s2),
              Text(
                denied
                    ? 'You can still pair by typing the details from the '
                        'desktop app window.'
                    : 'Pair by typing the details from the desktop app window.',
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
