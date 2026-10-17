import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/pairing_payload.dart';

/// A PC this phone has paired with before.
///
/// The device key is deliberately absent from this class. It lives in the
/// Android Keystore via `flutter_secure_storage`, keyed by [id], and must
/// never be written to `shared_preferences` — protocol section 7.5 says the PC
/// stores only a hash of the key, and holding the plain key in plain prefs on
/// the phone would undo that protection entirely.
@immutable
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    this.lastUsed,
  });

  /// Stable identifier, so the Keystore entry can be found again.
  final String id;

  final String name;
  final String host;
  final int port;

  /// The pinned certificate fingerprint. Connecting to this device after a
  /// successful pairing means trusting exactly this value.
  final String fingerprint;

  final DateTime? lastUsed;

  PairedDevice copyWith({
    String? name,
    String? host,
    int? port,
    String? fingerprint,
    DateTime? lastUsed,
  }) {
    return PairedDevice(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      fingerprint: fingerprint ?? this.fingerprint,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  /// Identity of the PC, independent of which IP it currently has.
  ///
  /// Derived from the fingerprint and port so that a DHCP address change does
  /// not make the phone forget the pairing — protocol D10 says the companion
  /// auto-detects IP changes, so the phone has to cope with them too.
  static String idFor(String fingerprint, int port) =>
      '${fingerprint.substring(0, 16)}-$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'fp': fingerprint,
        'lastUsed': lastUsed?.millisecondsSinceEpoch,
      };

  static PairedDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final host = json['host'];
    final port = json['port'];
    final fp = json['fp'];
    if (id is! String || name is! String || host is! String || fp is! String) {
      return null;
    }
    if (port is! int) return null;

    final lastUsed = json['lastUsed'];
    return PairedDevice(
      id: id,
      name: name,
      host: host,
      port: port,
      fingerprint: fp,
      lastUsed: lastUsed is int
          ? DateTime.fromMillisecondsSinceEpoch(lastUsed)
          : null,
    );
  }

  @override
  bool operator ==(Object other) => other is PairedDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Remembers which PCs this phone has paired with.
///
/// Only non-sensitive metadata is stored here. The device key is not, and
/// never will be — see [PairedDevice].
class PairingStore extends ChangeNotifier {
  PairingStore({SharedPreferences? preferences}) : _prefs = preferences;

  static const String _prefsKey = 'tapdesk.pairedDevices';

  SharedPreferences? _prefs;
  final List<PairedDevice> _devices = [];

  List<PairedDevice> get devices => List.unmodifiable(_devices);

  bool get hasPairedDevices => _devices.isNotEmpty;

  /// Most recently used first.
  PairedDevice? get mostRecent => _devices.isEmpty ? null : _devices.first;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs?.getStringList(_prefsKey) ?? const [];
    _devices
      ..clear()
      ..addAll(raw
          .map((e) {
            try {
              return PairedDevice.fromJson(jsonDecode(e) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<PairedDevice>());
    _sort();
    notifyListeners();
  }

  /// Remember a successfully paired PC, replacing any earlier entry for the
  /// same PC (a re-scan of the same machine must not create a duplicate).
  Future<void> remember(PairingPayload payload) async {
    final id = PairedDevice.idFor(payload.fingerprint, payload.port);
    _devices.removeWhere((d) => d.id == id);
    _devices.insert(
      0,
      PairedDevice(
        id: id,
        name: payload.name,
        host: payload.ips.first,
        port: payload.port,
        fingerprint: payload.fingerprint,
        lastUsed: DateTime.now(),
      ),
    );
    _sort();
    notifyListeners();
    await _persist();
  }

  /// Record a successful connection without changing the pairing.
  Future<void> touch(PairedDevice device) async {
    _devices
      ..removeWhere((d) => d.id == device.id)
      ..insert(0, device.copyWith(lastUsed: DateTime.now()));
    _sort();
    notifyListeners();
    await _persist();
  }

  /// Forget a device, or revoke it on the companion first.
  ///
  /// Phase 3 forgets it locally. Telling the companion to revoke is task 5.6
  /// and belongs with the transport, so the local entry is what goes away
  /// here and the server-side revocation follows in Phase 4/5.
  Future<void> forget(String id) async {
    _devices.removeWhere((d) => d.id == id);
    notifyListeners();
    await _persist();
  }

  void _sort() {
    _devices.sort((a, b) {
      final at = a.lastUsed;
      final bt = b.lastUsed;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  }

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _devices.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }
}
