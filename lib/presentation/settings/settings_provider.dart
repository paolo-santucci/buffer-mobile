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
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
