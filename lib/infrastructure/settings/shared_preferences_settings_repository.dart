import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/domain/settings/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SettingsRepository] implementation backed by [SharedPreferences].
///
/// Key contract (OQ-B1 + M6 + M7):
/// - Writes exactly seven upstream gschema keys on [save]: three bools, two
///   derived ints, one string, and one int. No "line-length-enabled" bool key.
///   Keys in write order:
///     1. "use-monospace-font"       (bool)
///     2. "check-spelling"           (bool)
///     3. "save-emergency-files"     (bool)
///     4. "emergency-recovery-files" (int: 0 or 10)
///     5. "line-length"              (int: 800 or 100000)
///     6. "color-scheme"             (string: follow|light|dark)
///     7. "font-size"                (int: 0–20, the fontSizeIndex slot)
/// - [load] derives [AppSettings.lineLengthEnabled] from the stored
///   "line-length" int: enabled iff (stored ?? 800) <= 800.
/// - [load] parses "color-scheme" via a safe switch with a follow fallback —
///   NEVER [AppColorScheme.values.byName] which throws on unknown values (EC-01).
/// - [load] reads "font-size" as int: absent or corrupt (wrong type) → default
///   index 8; stored value → clamped to [0, AppSettings.slotList.length-1] so
///   the index is always valid and never causes a bounds error (NFR-M7-04).
/// - [load] never throws on absent or corrupt (wrong-type) keys; falls back to
///   [AppSettings] canon defaults (EC-04).
class SharedPreferencesSettingsRepository implements SettingsRepository {
  SharedPreferencesSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<AppSettings> load() async {
    final useMonospaceFont = _safeBool(AppSettings.kUseMonospaceFont) ?? true;
    final spellingEnabled = _safeBool(AppSettings.kSpellingEnabled) ?? true;
    final emergencyRecoveryEnabled =
        _safeBool(AppSettings.kEmergencyRecoveryEnabled) ?? true;

    // lineLengthEnabled is derived from the stored int, not stored directly.
    final ll = _safeInt(AppSettings.kLineLength) ?? 800;
    final lineLengthEnabled = ll <= 800;

    // color-scheme: safe parse — absent or unknown value → follow (EC-01).
    final colorScheme = _parseColorScheme(
      _prefs.getString(AppSettings.kColorScheme),
    );

    // font-size: absent or corrupt → default 8; stored → clamped [0, 20] (NFR-M7-04).
    final fontSizeIndex = (_safeInt(AppSettings.kFontSize) ?? 8).clamp(
      0,
      AppSettings.slotList.length - 1,
    );

    return AppSettings(
      useMonospaceFont: useMonospaceFont,
      spellingEnabled: spellingEnabled,
      emergencyRecoveryEnabled: emergencyRecoveryEnabled,
      lineLengthEnabled: lineLengthEnabled,
      colorScheme: colorScheme,
      fontSizeIndex: fontSizeIndex,
    );
  }

  @override
  Future<void> save(AppSettings s) async {
    await _prefs.setBool(AppSettings.kUseMonospaceFont, s.useMonospaceFont);
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
    // Single mutation point for color-scheme (FR-M6-12 / NFR-M6-07).
    await _prefs.setString(AppSettings.kColorScheme, s.colorScheme.name);
    // Font-size index — 8th key, FR-M7-03.
    await _prefs.setInt(AppSettings.kFontSize, s.fontSizeIndex);
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

  /// Parses the stored [value] string to [AppColorScheme].
  ///
  /// Returns [AppColorScheme.follow] for null, absent, or unrecognised values
  /// (EC-01). Uses an explicit switch — never [AppColorScheme.values.byName]
  /// which throws on unknown input.
  AppColorScheme _parseColorScheme(String? value) {
    switch (value) {
      case 'light':
        return AppColorScheme.light;
      case 'dark':
        return AppColorScheme.dark;
      default:
        // 'follow', null, absent, or any garbage value → canonical default.
        return AppColorScheme.follow;
    }
  }
}
