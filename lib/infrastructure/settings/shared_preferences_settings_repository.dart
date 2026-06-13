import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/domain/settings/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SettingsRepository] implementation backed by [SharedPreferences].
///
/// Key contract (OQ-B1):
/// - Writes exactly six upstream gschema keys on [save]: four bools and two
///   derived ints. No "line-length-enabled" bool key. No "font-size" key.
/// - [load] derives [AppSettings.lineLengthEnabled] from the stored
///   "line-length" int: enabled iff (stored ?? 800) <= 800.
/// - [load] never throws on absent or corrupt (wrong-type) keys; falls back to
///   [AppSettings] canon defaults (EC-04).
class SharedPreferencesSettingsRepository implements SettingsRepository {
  SharedPreferencesSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<AppSettings> load() async {
    final useMonospaceFont = _safeBool(AppSettings.kUseMonospaceFont) ?? true;
    final showLineNumbers = _safeBool(AppSettings.kShowLineNumbers) ?? false;
    final spellingEnabled = _safeBool(AppSettings.kSpellingEnabled) ?? true;
    final emergencyRecoveryEnabled =
        _safeBool(AppSettings.kEmergencyRecoveryEnabled) ?? true;

    // lineLengthEnabled is derived from the stored int, not stored directly.
    final ll = _safeInt(AppSettings.kLineLength) ?? 800;
    final lineLengthEnabled = ll <= 800;

    return AppSettings(
      useMonospaceFont: useMonospaceFont,
      showLineNumbers: showLineNumbers,
      spellingEnabled: spellingEnabled,
      emergencyRecoveryEnabled: emergencyRecoveryEnabled,
      lineLengthEnabled: lineLengthEnabled,
    );
  }

  @override
  Future<void> save(AppSettings s) async {
    await _prefs.setBool(AppSettings.kUseMonospaceFont, s.useMonospaceFont);
    await _prefs.setBool(AppSettings.kShowLineNumbers, s.showLineNumbers);
    await _prefs.setBool(AppSettings.kSpellingEnabled, s.spellingEnabled);
    await _prefs.setBool(
      AppSettings.kEmergencyRecoveryEnabled,
      s.emergencyRecoveryEnabled,
    );
    await _prefs.setInt(
      AppSettings.kEmergencyRecoveryFiles,
      s.emergencyRecoveryFiles,
    );
    await _prefs.setInt(AppSettings.kLineLength, s.lineLength);
  }

  /// Returns null if the key is absent or the stored type is not a bool (EC-04).
  bool? _safeBool(String key) {
    try {
      return _prefs.getBool(key);
    } catch (_) {
      return null;
    }
  }

  /// Returns null if the key is absent or the stored type is not an int (EC-04).
  int? _safeInt(String key) {
    try {
      return _prefs.getInt(key);
    } catch (_) {
      return null;
    }
  }
}
