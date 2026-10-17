/// Storing the device key.
///
/// The key is a permanent credential for one computer: anyone holding it can
/// take control of that machine without asking anyone. It is therefore kept in
/// the Android Keystore-backed secure storage, never in `SharedPreferences`
/// with the harmless-looking PC names, and never written to a log.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The device key for one paired computer, or null.
abstract class KeyStore {
  Future<String?> read(String pcId);

  Future<void> write(String pcId, String deviceKey);

  Future<void> forget(String pcId);
}

/// `flutter_secure_storage` implementation.
///
/// The key is namespaced by `pcId` so revoking one computer leaves the others
/// paired. Backed by the Android Keystore, which means it is also lost if the
/// user changes screen lock - the correct outcome, since the key is then
/// unreadable and the user simply scans the QR code again.
class SecureKeyStore implements KeyStore {
  const SecureKeyStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String pcId) => _storage.read(key: _keyFor(pcId));

  @override
  Future<void> write(String pcId, String deviceKey) =>
      _storage.write(key: _keyFor(pcId), value: deviceKey);

  @override
  Future<void> forget(String pcId) => _storage.delete(key: _keyFor(pcId));

  static String _keyFor(String pcId) => 'tapdesk.deviceKey.$pcId';
}

/// An in-memory key store.
///
/// For tests, and for the case where secure storage is unavailable - some
/// devices have no usable Keystore. Pairing still works for the session; the
/// user scans again next time, which is a far better outcome than refusing to
/// connect at all.
class MemoryKeyStore implements KeyStore {
  final Map<String, String> _keys = {};

  @override
  Future<String?> read(String pcId) async => _keys[pcId];

  @override
  Future<void> write(String pcId, String deviceKey) async {
    _keys[pcId] = deviceKey;
  }

  @override
  Future<void> forget(String pcId) async {
    _keys.remove(pcId);
  }
}