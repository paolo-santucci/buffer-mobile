// VERIFY: OQ-B1 — confirm each key string against the upstream GNOME Buffer
// gschema before TASK-13 (SharedPreferencesSettingsRepository) is committed.
// A mismatch means stored values are never found on-device.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';

@freezed
class AppSettings with _$AppSettings {
  // Private constructor required for custom getters on freezed classes.
  const AppSettings._();

  const factory AppSettings({
    @Default(true) bool useMonospaceFont,
    @Default(false) bool showLineNumbers,
    @Default(true) bool spellingEnabled,
    @Default(true) bool emergencyRecoveryEnabled,
    @Default(true) bool lineLengthEnabled,
  }) = _AppSettings;

  // ---------------------------------------------------------------------------
  // Integer-proxy getters — FR-12
  // The boolean toggle is the single mutation point (EC-06); the integer value
  // is always derived and never stored independently.
  // ---------------------------------------------------------------------------

  /// Number of emergency-recovery files to retain.
  /// Derives from [emergencyRecoveryEnabled]: true → 10, false → 0.
  int get emergencyRecoveryFiles => emergencyRecoveryEnabled ? 10 : 0;

  /// Maximum line length in characters.
  /// Derives from [lineLengthEnabled]: true → 800 (upstream on-value), false → 100000 (effectively unlimited).
  int get lineLength => lineLengthEnabled ? 800 : 100000;

  // ---------------------------------------------------------------------------
  // Key strings — must match the upstream GNOME Buffer gschema verbatim.
  // See VERIFY: OQ-B1 above.
  // ---------------------------------------------------------------------------

  static const String kUseMonospaceFont = 'use-monospace-font';
  static const String kShowLineNumbers = 'show-line-numbers';
  static const String kSpellingEnabled = 'check-spelling';
  static const String kEmergencyRecoveryEnabled = 'save-emergency-files';
  static const String kEmergencyRecoveryFiles = 'emergency-recovery-files';
  static const String kLineLength = 'line-length';
}
