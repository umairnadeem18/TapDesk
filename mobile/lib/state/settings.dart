import 'package:flutter/foundation.dart';

/// What the computer is actually doing, as last reported by it.
///
/// These are not the user's settings. They are the companion's, and the phone
/// is told them rather than assuming its own request landed - a slider showing
/// "2.0" on a computer using 1.0 is a lie the user has no way to detect.
///
/// [known] is what stops that lie existing before the first report arrives.
/// Every field here has a perfectly plausible default, so showing one without
/// saying so would look exactly like a correct answer.
@immutable
class RemoteSettings {
  const RemoteSettings({
    this.cursorSpeed = 1.0,
    this.accel = 1.6,
    this.safeMode = false,
    this.known = false,
  });

  final double cursorSpeed;
  final double accel;
  final bool safeMode;

  /// Whether the computer has actually said.
  final bool known;

  RemoteSettings copyWith({
    double? cursorSpeed,
    double? accel,
    bool? safeMode,
    bool? known,
  }) {
    return RemoteSettings(
      cursorSpeed: cursorSpeed ?? this.cursorSpeed,
      accel: accel ?? this.accel,
      safeMode: safeMode ?? this.safeMode,
      known: known ?? this.known,
    );
  }

  /// Read a `settings` frame, ignoring anything the wrong shape.
  ///
  /// Defensive on purpose. The phone and the computer are deployed separately,
  /// and a phone that throws on a malformed frame crashes on connect instead
  /// of carrying on with the input controls it already has working.
  static RemoteSettings fromMessage(Map<Object?, Object?> message) {
    final speed = message['cursorSpeed'];
    final accel = message['accel'];
    final safe = message['safeMode'];
    return RemoteSettings(
      cursorSpeed: speed is num ? speed.toDouble() : 1.0,
      accel: accel is num ? accel.toDouble() : 1.6,
      safeMode: safe is bool ? safe : false,
      known: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteSettings &&
      other.cursorSpeed == cursorSpeed &&
      other.accel == accel &&
      other.safeMode == safeMode &&
      other.known == known;

  @override
  int get hashCode => Object.hash(cursorSpeed, accel, safeMode, known);
}

/// Where settings are kept between runs.
///
/// Abstracted so the settings screen can be driven in tests without a platform
/// channel, which is the same reason [RecordingEventSink] exists for input.
abstract class SettingsStorage {
  Future<bool?> readBool(String key);
  Future<double?> readDouble(String key);
  Future<void> writeBool(String key, bool value);
  Future<void> writeDouble(String key, double value);
}

/// An in-memory [SettingsStorage] for tests and for the moment before the
/// real one has loaded.
class MemorySettingsStorage implements SettingsStorage {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  Future<bool?> readBool(String key) async => _values[key] as bool?;

  @override
  Future<double?> readDouble(String key) async => _values[key] as double?;

  @override
  Future<void> writeBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> writeDouble(String key, double value) async => _values[key] = value;
}

/// What the phone can do to the computer, as a partial update.
///
/// Partial is the point. `docs/protocol.md` section 4.5: a screen that sent
/// all three fields every time would reset a Safe Mode change made on the
/// computer the moment the phone reconnected.
@immutable
class SettingsChange {
  const SettingsChange({this.cursorSpeed, this.accel, this.safeMode});

  final double? cursorSpeed;
  final double? accel;
  final bool? safeMode;

  bool get isEmpty =>
      cursorSpeed == null && accel == null && safeMode == null;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'t': 'set'};
    if (cursorSpeed != null) json['cursorSpeed'] = cursorSpeed;
    if (accel != null) json['accel'] = accel;
    if (safeMode != null) json['safeMode'] = safeMode;
    return json;
  }
}

/// The settings screen's whole state, in one notifier.
///
/// A [ChangeNotifier] because the screen is opened from the app bar and needs
/// to rebuild when a value changes without being recreated - the same
/// requirement that made [EventSink] one.
class AppSettings extends ChangeNotifier {
  AppSettings({SettingsStorage? storage}) : _storage = storage ?? MemorySettingsStorage();

  final SettingsStorage _storage;

  /// Ranges the companion accepts, mirrored from `protocol.py`.
  ///
  /// Duplicated rather than fetched, because the companion cannot be asked
  /// before the phone has connected - which is exactly when these are needed to
  /// draw the sliders. The limits here are the same ones validation enforces,
  /// so a slider cannot be dragged somewhere that would be refused.
  static const double minCursorSpeed = 0.25;
  static const double maxCursorSpeed = 4.0;
  static const double minAccel = 1.0;
  static const double maxAccel = 3.0;

  /// The user's last choice, so a slider is in the right place before the
  /// computer has answered.
  double _wantedCursorSpeed = 1.0;
  double _wantedAccel = 1.6;
  bool _wantedSafeMode = false;

  RemoteSettings _remote = const RemoteSettings();

  bool _haptics = true;
  bool _leftHanded = false;
  bool _keepAwake = true;
  bool _loaded = false;

  /// Sent when a setting that lives on the computer changes.
  ///
  /// Null before the transport is attached, which is a supported state: the
  /// app can be run in preview mode with no computer at all, and the sliders
  /// still have to be usable.
  void Function(SettingsChange change)? onChange;

  /// Called when the user asks to be unpaired.
  void Function()? onForget;

  /// What the computer is doing. Not the user's business to guess.
  RemoteSettings get remote => _remote;

  double get cursorSpeed =>
      _remote.known ? _remote.cursorSpeed : _wantedCursorSpeed;

  double get accel => _remote.known ? _remote.accel : _wantedAccel;

  bool get safeMode => _remote.known ? _remote.safeMode : _wantedSafeMode;

  bool get haptics => _haptics;
  bool get leftHanded => _leftHanded;
  bool get keepAwake => _keepAwake;

  /// Whether stored preferences have been read yet.
  ///
  /// The screen shows nothing until this is true. Building the controls from
  /// defaults and then correcting them a frame later makes the app look like
  /// it forgets the user's settings on every launch.
  bool get isLoaded => _loaded;

  /// Whether the computer has been asked anything yet.
  bool get isConnectedToComputer => _remote.known;

  /// Load stored preferences. Safe to call more than once.
  Future<void> load() async {
    if (_loaded) return;
    _haptics = await _storage.readBool(_kHaptics) ?? true;
    _leftHanded = await _storage.readBool(_kLeftHanded) ?? false;
    _keepAwake = await _storage.readBool(_kKeepAwake) ?? true;
    _wantedCursorSpeed =
        await _storage.readDouble(_kCursorSpeed) ?? 1.0;
    _wantedAccel = await _storage.readDouble(_kAccel) ?? 1.6;
    _loaded = true;
    notifyListeners();
  }

  /// Take what the computer says.
  ///
  /// Only the first report clears the "have we heard?" gap, but every later
  /// one is applied - which is how a change made on the PC reaches a phone
  /// that is sitting in Settings with the screen open.
  void applyRemote(Map<Object?, Object?> message) {
    final next = RemoteSettings.fromMessage(message);
    if (next == _remote) return;
    _remote = next;
    notifyListeners();
  }

  /// Forget the computer's report, because there is no longer one.
  ///
  /// Called on disconnect. Without it the sliders keep showing the last
  /// computer's values, so someone who then scans a different PC sees settings
  /// that belong to a machine they are not driving.
  void clearRemote() {
    if (!_remote.known) return;
    _remote = const RemoteSettings();
    notifyListeners();
  }

  Future<void> setCursorSpeed(double value) async {
    final clamped = value.clamp(minCursorSpeed, maxCursorSpeed).toDouble();
    if (clamped == _wantedCursorSpeed) return;
    _wantedCursorSpeed = clamped;
    notifyListeners();
    await _storage.writeDouble(_kCursorSpeed, clamped);
    _push(SettingsChange(cursorSpeed: clamped));
  }

  Future<void> setAccel(double value) async {
    final clamped = value.clamp(minAccel, maxAccel).toDouble();
    if (clamped == _wantedAccel) return;
    _wantedAccel = clamped;
    notifyListeners();
    await _storage.writeDouble(_kAccel, clamped);
    _push(SettingsChange(accel: clamped));
  }

  Future<void> setSafeMode(bool value) async {
    if (value == _wantedSafeMode) return;
    _wantedSafeMode = value;
    notifyListeners();
    await _storage.writeBool(_kSafeMode, value);
    _push(SettingsChange(safeMode: value));
  }

  Future<void> setHaptics(bool value) async {
    if (value == _haptics) return;
    _haptics = value;
    notifyListeners();
    await _storage.writeBool(_kHaptics, value);
  }

  Future<void> setLeftHanded(bool value) async {
    if (value == _leftHanded) return;
    _leftHanded = value;
    notifyListeners();
    await _storage.writeBool(_kLeftHanded, value);
  }

  Future<void> setKeepAwake(bool value) async {
    if (value == _keepAwake) return;
    _keepAwake = value;
    notifyListeners();
    await _storage.writeBool(_kKeepAwake, value);
  }

  /// Ask to be unpaired.
  Future<void> forgetThisDevice() async {
    onForget?.call();
  }

  void _push(SettingsChange change) {
    if (change.isEmpty) return;
    onChange?.call(change);
  }

  static const String _kHaptics = 'settings.haptics';
  static const String _kLeftHanded = 'settings.leftHanded';
  static const String _kKeepAwake = 'settings.keepAwake';
  static const String _kCursorSpeed = 'settings.cursorSpeed';
  static const String _kAccel = 'settings.accel';
  static const String _kSafeMode = 'settings.safeMode';
}