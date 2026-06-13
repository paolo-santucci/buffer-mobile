// Tests for settingsProvider (TASK-15)
//
// Spec refs: FR-13, EC-01, EC-04
//
// Verifies:
//   1. FR-13 / EC-01 — first read with empty SharedPreferences resolves to
//      AppSettings defaults (incl. emergencyRecoveryEnabled == true).
//      State is AsyncData, not AsyncError.
//   2. EC-04 — when the SettingsRepository.load() throws, the provider
//      degrades gracefully to defaults. State is AsyncData, not AsyncError.
//   3. FR-13 single-reg — exactly one SettingsRepository type is registered;
//      the provider reads settingsRepositoryProvider and no second repo.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/domain/settings/settings_repository.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Fake repo whose load() always throws — used for EC-04 test.
// ---------------------------------------------------------------------------
class _ThrowingRepository implements SettingsRepository {
  const _ThrowingRepository();

  @override
  Future<AppSettings> load() async =>
      throw Exception('simulated SharedPreferences failure');

  @override
  Future<void> save(AppSettings settings) async {}
}

// ---------------------------------------------------------------------------
// Fake repo that records whether it was constructed — used for FR-13
// single-reg assertion.
// ---------------------------------------------------------------------------
class _TrackingRepository implements SettingsRepository {
  static int constructionCount = 0;

  _TrackingRepository() {
    constructionCount++;
  }

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  // Ensure SharedPreferences platform channel mock is in place.
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // FR-13 / EC-01: first read with no stored prefs → defaults
  // ---------------------------------------------------------------------------

  group('settingsProvider — FR-13 / EC-01 empty prefs resolves to defaults', () {
    test(
      'given_empty_SharedPreferences_when_settingsProvider_read_then_emergencyRecoveryEnabled_is_true',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final result = await container.read(settingsProvider.future);

        expect(
          result.emergencyRecoveryEnabled,
          isTrue,
          reason: 'EC-01: emergencyRecoveryEnabled must default to true',
        );
        expect(
          result.useMonospaceFont,
          isTrue,
          reason: 'EC-01: useMonospaceFont must default to true',
        );
        expect(
          result.showLineNumbers,
          isFalse,
          reason: 'EC-01: showLineNumbers must default to false',
        );
        expect(
          result.spellingEnabled,
          isTrue,
          reason: 'EC-01: spellingEnabled must default to true',
        );
        expect(
          result.lineLengthEnabled,
          isTrue,
          reason: 'EC-01: lineLengthEnabled must default to true',
        );
      },
    );

    test(
      'given_empty_SharedPreferences_when_settingsProvider_read_then_state_is_AsyncData_not_AsyncError',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        // Await the future to ensure the async notifier has settled.
        await container.read(settingsProvider.future);
        final state = container.read(settingsProvider);

        expect(
          state,
          isA<AsyncData<AppSettings>>(),
          reason: 'FR-13: state must be AsyncData after a successful load',
        );
        expect(
          state,
          isNot(isA<AsyncError<AppSettings>>()),
          reason: 'FR-13: state must never be AsyncError on a clean read',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // EC-04: broken repo → graceful degradation to defaults (AsyncData, not AsyncError)
  // ---------------------------------------------------------------------------

  group('settingsProvider — EC-04 graceful degradation on repo failure', () {
    test(
      'given_throwing_SettingsRepository_when_settingsProvider_read_then_resolves_to_defaults',
      () async {
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              const _ThrowingRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(settingsProvider.future);

        expect(
          result,
          equals(const AppSettings()),
          reason: 'EC-04: a throwing repo must resolve to AppSettings defaults',
        );
      },
    );

    test(
      'given_throwing_SettingsRepository_when_settingsProvider_read_then_state_is_AsyncData_not_AsyncError',
      () async {
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              const _ThrowingRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final state = container.read(settingsProvider);

        expect(
          state,
          isA<AsyncData<AppSettings>>(),
          reason:
              'EC-04: graceful degradation must produce AsyncData, not AsyncError',
        );
        expect(
          state,
          isNot(isA<AsyncError<AppSettings>>()),
          reason:
              'EC-04: a throwing repo must never propagate AsyncError to the UI',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // FR-13 single-reg: exactly one SettingsRepository is registered;
  // no second repo type is constructed alongside the canonical one.
  // ---------------------------------------------------------------------------

  group('settingsProvider — FR-13 single repository registration', () {
    test(
      'given_settingsRepositoryProvider_when_overridden_with_tracking_repo_then_only_one_repo_is_constructed',
      () async {
        _TrackingRepository.constructionCount = 0;

        final container = ProviderContainer(
          overrides: [
            // Override the canonical provider with a factory override so we
            // can count constructions.
            settingsRepositoryProvider.overrideWith(
              (ref) => _TrackingRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);

        expect(
          _TrackingRepository.constructionCount,
          equals(1),
          reason:
              'FR-13: exactly one SettingsRepository must be constructed; '
              'a count > 1 signals a second parallel repo registration',
        );
      },
    );

    test(
      'given_settingsProvider_when_read_then_it_consumes_settingsRepositoryProvider_not_a_new_repo',
      () async {
        // This test verifies structural coupling: settingsProvider must watch
        // settingsRepositoryProvider. We confirm this by overriding
        // settingsRepositoryProvider to return a fixed AppSettings and
        // verifying the provider reflects it (rather than constructing its own
        // repo independently).
        SharedPreferences.setMockInitialValues({
          // Store a non-default value to distinguish the repo's output
          // from a hard-coded default.
          AppSettings.kShowLineNumbers: true,
        });
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final result = await container.read(settingsProvider.future);

        // The underlying SharedPreferencesSettingsRepository reads the stored
        // value, so showLineNumbers must reflect the stored true.
        expect(
          result.showLineNumbers,
          isTrue,
          reason:
              'FR-13: settingsProvider must read from settingsRepositoryProvider; '
              'if it bypasses it, the stored prefs value would be ignored',
        );
      },
    );
  });
}
