import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/domain/settings/settings_repository.dart';
import 'package:buffer/infrastructure/settings/shared_preferences_settings_repository.dart';

// ---------------------------------------------------------------------------
// 1. SharedPreferences seam — overridden at the ProviderScope root in main.dart
//    (TASK-16). Tests override it with a mock instance.
// ---------------------------------------------------------------------------
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart '
    'with the real SharedPreferences instance.',
  ),
);

// ---------------------------------------------------------------------------
// 2. Single SettingsRepository registration (FR-13).
//    Derives from sharedPreferencesProvider — one construction path only.
// ---------------------------------------------------------------------------
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) =>
      SharedPreferencesSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

// ---------------------------------------------------------------------------
// 3. SettingsNotifier + settingsProvider
//    AsyncNotifierProvider so callers can observe loading / error states.
//    EC-04: any exception from the repository is caught and degraded to the
//    AppSettings() defaults — the state is always AsyncData, never AsyncError.
// ---------------------------------------------------------------------------
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    try {
      return await ref.watch(settingsRepositoryProvider).load();
    } catch (_) {
      return const AppSettings();
    }
  }

  // FR-M5-09 / FR-M5-15 / NFR-M5-03 / EC-13
  //
  // Single mutation path for the emergency-recovery toggle. Reads
  // [state.value] with a `?? const AppSettings()` fallback so the method
  // never throws during AsyncLoading (no requireValue — NFR-M5-03).
  //
  // EC-13: equal-value calls are no-ops; [save] is never called redundantly.
  //
  // The integer-proxy [AppSettings.emergencyRecoveryFiles] is auto-derived
  // by [copyWith] — it is never written independently.
  Future<void> setEmergencyRecoveryEnabled(bool enabled) async {
    final current = state.value ?? const AppSettings();
    if (current.emergencyRecoveryEnabled == enabled) return;

    final next = current.copyWith(emergencyRecoveryEnabled: enabled);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }

  // FR-M6-09 / EC-08 / EC-09
  //
  // Single mutation path for the spell-check setting. Modelled verbatim on
  // [setEmergencyRecoveryEnabled]: reads [state.value] with a
  // `?? const AppSettings()` fallback (never requireValue — EC-08),
  // equal-value calls are no-ops (EC-09), and the optimistic [AsyncData]
  // update is applied BEFORE the [save] await.
  Future<void> setSpellingEnabled(bool enabled) async {
    final current = state.value ?? const AppSettings();
    if (current.spellingEnabled == enabled) return;

    final next = current.copyWith(spellingEnabled: enabled);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }

  // FR-M6-02 / FR-M6-03 / EC-08 / EC-09 / NFR-M6-07
  //
  // Single mutation path for the color-scheme setting. Modelled verbatim on
  // [setEmergencyRecoveryEnabled]: reads [state.value] with a
  // `?? const AppSettings()` fallback (never requireValue — EC-08),
  // equal-value calls are no-ops (EC-09), and the optimistic [AsyncData]
  // update is applied BEFORE the [save] await.
  Future<void> setColorScheme(AppColorScheme scheme) async {
    final current = state.value ?? const AppSettings();
    if (current.colorScheme == scheme) return;

    final next = current.copyWith(colorScheme: scheme);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }

  // FR-M7-03 / FR-M7-04 / FR-M7-08 / NFR-M7-06
  //
  // Single mutation path for the font-size-index setting. Modelled verbatim on
  // [setColorScheme]: reads [state.value] with a `?? const AppSettings()`
  // fallback (never requireValue — NFR-M7-06), delegates the clamp/no-op to
  // the pure [AppSettings.setFontSizeIndex] verb (which returns `this` when
  // the clamped value equals the current index), and applies the optimistic
  // [AsyncData] update BEFORE the [save] await.
  Future<void> setFontSizeIndex(int index) async {
    final current = state.value ?? const AppSettings();
    final next = current.setFontSizeIndex(index);
    if (identical(next, current)) return;

    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }

  // FR-M7-05 / FR-M7-06 / FR-M7-08 / NFR-M7-06
  //
  // Single mutation path for the monospace-font toggle. Modelled verbatim on
  // [setColorScheme]: reads [state.value] with a `?? const AppSettings()`
  // fallback (never requireValue — NFR-M7-06), delegates the no-op to the
  // pure [AppSettings.setUseMonospaceFont] verb (which returns `this` when
  // the value is already [value]), and applies the optimistic [AsyncData]
  // update BEFORE the [save] await.
  Future<void> setUseMonospaceFont(bool value) async {
    final current = state.value ?? const AppSettings();
    final next = current.setUseMonospaceFont(value);
    if (identical(next, current)) return;

    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// 4. themeModeProvider — FR-M6-03 / FR-M6-12 / NFR-M6-07
//
//    Pure derivation: AppColorScheme → ThemeMode. This is the SINGLE point
//    where ThemeMode is derived; no other provider or method writes it.
//
//    Reads [settingsProvider] via [state.value ?? const AppSettings()] to
//    guarantee ThemeMode.system under AsyncLoading (EC-08, never requireValue).
// ---------------------------------------------------------------------------
final themeModeProvider = Provider<ThemeMode>((ref) {
  final scheme =
      (ref.watch(settingsProvider).value ?? const AppSettings()).colorScheme;
  return switch (scheme) {
    AppColorScheme.follow => ThemeMode.system,
    AppColorScheme.light => ThemeMode.light,
    AppColorScheme.dark => ThemeMode.dark,
  };
});
