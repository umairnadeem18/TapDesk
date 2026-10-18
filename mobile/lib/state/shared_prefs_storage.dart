import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// [SettingsStorage] backed by `shared_preferences`.
///
/// Kept out of `settings.dart` so that file stays pure Dart with no plugin
/// dependency. That is what lets the settings logic - which is where the
/// interesting rules live - be tested without a platform channel, in the same
/// way [RecordingEventSink] keeps the input UI testable without a network.
///
/// Every read returns null rather than throwing when the key is missing, which
/// is the ordinary case on a phone that has never opened Settings. Treating
/// that as an error would make a first launch fail at startup.
class SharedPrefsSettingsStorage implements SettingsStorage {
  const SharedPrefsSettingsStorage();

  @override
  Future<bool?> readBool(String key) async {
    return _prefs().then((prefs) => prefs.getBool(key));
  }

  @override
  Future<double?> readDouble(String key) async {
    // Written as a double, but a value that went in as an int - which is what
    // `1` rather than `1.0` becomes on some platforms - would make getDouble
    // throw rather than return. Losing a stored setting to a type mismatch is
    // a silent reset the user would blame on the app.
    final prefs = await _prefs();
    final double? asDouble = prefs.getDouble(key);
    if (asDouble != null) return asDouble;
    final int? asInt = prefs.getInt(key);
    return asInt?.toDouble();
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    (await _prefs()).setBool(key, value);
  }

  @override
  Future<void> writeDouble(String key, double value) async {
    (await _prefs()).setDouble(key, value);
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
}