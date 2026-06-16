// VERIFY: OQ-B1 — confirm each key string against the upstream GNOME Buffer
// gschema before TASK-13 (SharedPreferencesSettingsRepository) is committed.
// A mismatch means stored values are never found on-device.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';

/// Theme-mode preference (FR-M6-01 / EC-01).
///
/// - [follow]: honour the OS dark/light setting (default).
/// - [light]: always Light theme.
/// - [dark]: always Dark theme.
enum AppColorScheme { follow, light, dark }

@freezed
class AppSettings with _$AppSettings {
  // Private constructor required for custom getters on freezed classes.
  const AppSettings._();

  const factory AppSettings({
    @Default(true) bool useMonospaceFont,
    @Default(true) bool spellingEnabled,
    @Default(true) bool emergencyRecoveryEnabled,
    @Default(true) bool lineLengthEnabled,
    @Default(AppColorScheme.follow) AppColorScheme colorScheme,
    // FR-M7-01: default index 8 → 14pt (slotList[8] == 14).
    @Default(8) int fontSizeIndex,
  }) = _AppSettings;

  // ---------------------------------------------------------------------------
  // 21-slot font-size table — FR-M7-01
  // Index 8 (default) → 14pt.  Strictly ascending; no duplicates.
  // ---------------------------------------------------------------------------
  static const List<int> slotList = [
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    20,
    22,
    24,
    26,
    28,
    30,
    34,
    38,
  ];

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
  // Typography derived getter — FR-M7-01
  // ---------------------------------------------------------------------------

  /// Current font size in points derived from [fontSizeIndex].
  double get fontSizePt => slotList[fontSizeIndex].toDouble();

  // ---------------------------------------------------------------------------
  // Pure clampable verbs — FR-M7-03, FR-M7-04
  // Each verb short-circuits (returns `this`) when the value is unchanged,
  // because freezed's copyWith always produces a new instance even for equal
  // values, breaking `identical(this)` no-op assertions.
  // ---------------------------------------------------------------------------

  /// Sets [fontSizeIndex] to [index], clamped to [0, slotList.length-1].
  /// Returns `this` when the clamped value equals the current index (no-op).
  AppSettings setFontSizeIndex(int index) {
    final clamped = index.clamp(0, slotList.length - 1);
    if (clamped == fontSizeIndex) return this;
    return copyWith(fontSizeIndex: clamped);
  }

  /// Sets [useMonospaceFont] to [value].
  /// Returns `this` when the value is already [value] (idempotent, NOT a toggle).
  AppSettings setUseMonospaceFont(bool value) {
    if (useMonospaceFont == value) return this;
    return copyWith(useMonospaceFont: value);
  }

  // ---------------------------------------------------------------------------
  // Key strings — must match the upstream GNOME Buffer gschema verbatim.
  // See VERIFY: OQ-B1 above.
  // ---------------------------------------------------------------------------

  static const String kUseMonospaceFont = 'use-monospace-font';
  static const String kSpellingEnabled = 'check-spelling';
  static const String kEmergencyRecoveryEnabled = 'save-emergency-files';
  static const String kEmergencyRecoveryFiles = 'emergency-recovery-files';
  static const String kLineLength = 'line-length';

  /// Key for the [colorScheme] setting.
  /// Pinned as 'color-scheme' per OQ-M6-05 (NOT 'style-variant').
  static const String kColorScheme = 'color-scheme';

  /// Key for the [fontSizeIndex] setting — FR-M7-01 / OQ-M7-03.
  static const String kFontSize = 'font-size';
}
