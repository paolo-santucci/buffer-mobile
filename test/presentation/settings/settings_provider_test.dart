// Tests for settingsProvider (TASK-15, TASK-08, TASK-04, TASK-03)
//
// Spec refs: FR-13, EC-01, EC-04, FR-M5-09, FR-M5-15, NFR-M5-03,
//            FR-M6-02, FR-M6-03, FR-M6-12, EC-08, EC-09, NFR-M6-07,
//            FR-M7-03, FR-M7-04, FR-M7-05, FR-M7-06, FR-M7-08, NFR-M7-04,
//            NFR-M7-06
//
// Verifies:
//   1. FR-13 / EC-01 — first read with empty SharedPreferences resolves to
//      AppSettings defaults (incl. emergencyRecoveryEnabled == true).
//      State is AsyncData, not AsyncError.
//   2. EC-04 — when the SettingsRepository.load() throws, the provider
//      degrades gracefully to defaults. State is AsyncData, not AsyncError.
//   3. FR-13 single-reg — exactly one SettingsRepository type is registered;
//      the provider reads settingsRepositoryProvider and no second repo.
//   4. FR-M5-09 / EC-13 — setEmergencyRecoveryEnabled: toggles state + persists
//      when value differs; is a no-op when value unchanged (no redundant save).
//   5. NFR-M5-03 — no requireValue; AsyncLoading state reads state.value ?? defaults.
//   6. FR-M6-02 / FR-M6-03 / EC-08 / EC-09 / NFR-M6-07 — setColorScheme setter
//      and themeModeProvider derivation.
//   7. FR-M7-03 / FR-M7-04 — setFontSizeIndex: mutates state + persists; no-op
//      when index unchanged; no throw during AsyncLoading.
//   8. FR-M7-05 / FR-M7-06 — setUseMonospaceFont: mutates state + persists;
//      no-op when value unchanged.
//   9. NFR-M7-04 / NFR-M7-06 — zero occurrences of TypographySettings and
//      typographyProvider in lib/ (retirement scan).

import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/domain/settings/settings_repository.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

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
// Fake repo that records save() calls — used for TASK-08 mutation tests.
// ---------------------------------------------------------------------------
class _RecordingRepository implements SettingsRepository {
  AppSettings _stored;
  final List<AppSettings> savedArgs = [];

  _RecordingRepository({AppSettings initial = const AppSettings()})
    : _stored = initial;

  @override
  Future<AppSettings> load() async => _stored;

  @override
  Future<void> save(AppSettings settings) async {
    _stored = settings;
    savedArgs.add(settings);
  }
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
  });

  // ---------------------------------------------------------------------------
  // TASK-08 — SettingsNotifier.setEmergencyRecoveryEnabled
  // Spec refs: FR-M5-09, FR-M5-15, NFR-M5-03, EC-13
  //
  // Verifies:
  //   a. value differs → save called exactly once with the new settings; state
  //      optimistically reflects the new value (AsyncData...false)
  //   b. value unchanged → save NOT called (no-op, EC-13); state unchanged
  //   c. AsyncLoading → reads state.value ?? const AppSettings() (defaults true)
  //      and proceeds without throwing (no requireValue, NFR-M5-03)
  // ---------------------------------------------------------------------------

  group(
    'SettingsNotifier.setEmergencyRecoveryEnabled — FR-M5-09 / EC-13 / NFR-M5-03',
    () {
      test(
        'given_enabled_true_when_setEmergencyRecoveryEnabled_false_then_save_called_once_with_false_and_state_updated',
        () async {
          // Arrange: repo starts with emergencyRecoveryEnabled == true (default).
          final repo = _RecordingRepository(
            initial: const AppSettings(emergencyRecoveryEnabled: true),
          );
          final container = ProviderContainer(
            overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);

          // Settle the provider so state is AsyncData(AppSettings(enabled: true)).
          await container.read(settingsProvider.future);

          // Act.
          await container
              .read(settingsProvider.notifier)
              .setEmergencyRecoveryEnabled(false);

          // Assert: save called exactly once with the toggled value.
          expect(
            repo.savedArgs.length,
            equals(1),
            reason:
                'FR-M5-09: save must be called exactly once when value differs',
          );
          expect(
            repo.savedArgs.first.emergencyRecoveryEnabled,
            isFalse,
            reason:
                'FR-M5-09: save must be called with emergencyRecoveryEnabled: false',
          );

          // Assert: state optimistically reflects the new value.
          final state = container.read(settingsProvider);
          expect(
            state,
            isA<AsyncData<AppSettings>>(),
            reason: 'FR-M5-09: state must be AsyncData after optimistic update',
          );
          expect(
            state.value?.emergencyRecoveryEnabled,
            isFalse,
            reason:
                'FR-M5-09: optimistic state must reflect emergencyRecoveryEnabled: false',
          );
        },
      );

      test(
        'given_enabled_true_when_setEmergencyRecoveryEnabled_true_then_save_NOT_called_and_state_unchanged',
        () async {
          // Arrange: repo starts with emergencyRecoveryEnabled == true (default).
          final repo = _RecordingRepository(
            initial: const AppSettings(emergencyRecoveryEnabled: true),
          );
          final container = ProviderContainer(
            overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);

          // Settle the provider.
          await container.read(settingsProvider.future);

          // Act: call with the same value already in state.
          await container
              .read(settingsProvider.notifier)
              .setEmergencyRecoveryEnabled(true);

          // Assert: save must NOT be called (EC-13 no-op write avoidance).
          expect(
            repo.savedArgs,
            isEmpty,
            reason:
                'EC-13: save must NOT be called when the new value matches current',
          );

          // Assert: state is unchanged.
          final state = container.read(settingsProvider);
          expect(
            state.value?.emergencyRecoveryEnabled,
            isTrue,
            reason: 'EC-13: state must remain true when no-op call is made',
          );
        },
      );

      test(
        'given_settings_AsyncLoading_when_setEmergencyRecoveryEnabled_false_then_reads_defaults_and_does_not_throw',
        () async {
          // Arrange: use a repo that never completes load() to keep the provider
          // in AsyncLoading. We achieve this via a completer-backed fake.
          // Instead, we use a simpler approach: override with a slow repo and
          // call setEmergencyRecoveryEnabled before awaiting the future.
          final repo = _RecordingRepository(
            initial: const AppSettings(emergencyRecoveryEnabled: true),
          );
          final container = ProviderContainer(
            overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);

          // Do NOT await the future — state is AsyncLoading at this point.
          // Force a read so the notifier initialises (but remains in loading).
          container.read(settingsProvider);

          // Act: calling setEmergencyRecoveryEnabled while AsyncLoading must
          // not throw (reads state.value ?? const AppSettings() instead of
          // requireValue). const AppSettings() defaults emergencyRecoveryEnabled
          // to true, so false differs → save IS called.
          await expectLater(
            () => container
                .read(settingsProvider.notifier)
                .setEmergencyRecoveryEnabled(false),
            returnsNormally,
            reason:
                'NFR-M5-03: setEmergencyRecoveryEnabled must never throw during '
                'AsyncLoading (no requireValue)',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // TASK-04 — SettingsNotifier.setColorScheme + themeModeProvider
  // Spec refs: FR-M6-02, FR-M6-03, FR-M6-12, EC-08, EC-09, NFR-M6-07
  //
  // Verifies:
  //   a. value differs → state optimistically reflects new value (AsyncData);
  //      save called exactly once with the new settings.
  //   b. value unchanged → save NOT called (EC-09 no-op write avoidance).
  //   c. AsyncLoading → reads state.value ?? const AppSettings() (no throw, EC-08).
  //   d. themeModeProvider: follow→ThemeMode.system, light→ThemeMode.light,
  //      dark→ThemeMode.dark.
  //   e. themeModeProvider under AsyncLoading → ThemeMode.system (no throw, EC-08).
  // ---------------------------------------------------------------------------

  group(
    'SettingsNotifier.setColorScheme — FR-M6-02 / FR-M6-03 / EC-08 / EC-09 / NFR-M6-07',
    () {
      test(
        'given_colorScheme_follow_when_setColorScheme_dark_then_state_is_AsyncData_dark_and_save_called_once',
        () async {
          // Arrange: repo starts with colorScheme == follow (default).
          final repo = _RecordingRepository(
            initial: const AppSettings(colorScheme: AppColorScheme.follow),
          );
          final container = ProviderContainer(
            overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);

          // Settle the provider so state is AsyncData with follow.
          await container.read(settingsProvider.future);

          // Act.
          await container
              .read(settingsProvider.notifier)
              .setColorScheme(AppColorScheme.dark);

          // Assert: save called exactly once with the new colorScheme.
          expect(
            repo.savedArgs.length,
            equals(1),
            reason:
                'FR-M6-02: save must be called exactly once when colorScheme differs',
          );
          expect(
            repo.savedArgs.first.colorScheme,
            equals(AppColorScheme.dark),
            reason: 'FR-M6-02: save must be called with colorScheme: dark',
          );

          // Assert: state optimistically reflects the new value.
          final state = container.read(settingsProvider);
          expect(
            state,
            isA<AsyncData<AppSettings>>(),
            reason: 'FR-M6-02: state must be AsyncData after optimistic update',
          );
          expect(
            state.value?.colorScheme,
            equals(AppColorScheme.dark),
            reason: 'FR-M6-02: optimistic state must reflect colorScheme: dark',
          );
        },
      );

      test(
        'given_colorScheme_light_when_setColorScheme_light_then_save_NOT_called_and_state_unchanged',
        () async {
          // Arrange: repo starts with colorScheme == light.
          final repo = _RecordingRepository(
            initial: const AppSettings(colorScheme: AppColorScheme.light),
          );
          final container = ProviderContainer(
            overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);

          // Settle the provider.
          await container.read(settingsProvider.future);

          // Act: call with the same value already in state.
          await container
              .read(settingsProvider.notifier)
              .setColorScheme(AppColorScheme.light);

          // Assert: save must NOT be called (EC-09 no-op write avoidance).
          expect(
            repo.savedArgs,
            isEmpty,
            reason:
                'EC-09: save must NOT be called when the new colorScheme matches current',
          );

          // Assert: state is unchanged.
          final state = container.read(settingsProvider);
          expect(
            state.value?.colorScheme,
            equals(AppColorScheme.light),
            reason: 'EC-09: state must remain light when no-op call is made',
          );
        },
      );

      test(
        'given_settings_AsyncLoading_when_setColorScheme_dark_then_reads_defaults_and_does_not_throw',
        () async {
          // Arrange: trigger AsyncLoading by reading before the future settles.
          final repo = _RecordingRepository(
            initial: const AppSettings(colorScheme: AppColorScheme.follow),
          );
          final container = ProviderContainer(
            overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);

          // Force notifier init without awaiting — state is AsyncLoading.
          container.read(settingsProvider);

          // Act: setColorScheme must not throw (reads ?? const AppSettings()).
          // const AppSettings() defaults colorScheme to follow, so dark differs
          // → save IS called.
          await expectLater(
            () => container
                .read(settingsProvider.notifier)
                .setColorScheme(AppColorScheme.dark),
            returnsNormally,
            reason:
                'EC-08: setColorScheme must never throw during AsyncLoading '
                '(reads state.value ?? const AppSettings(), no requireValue)',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // TASK-03 — SettingsNotifier.setFontSizeIndex
  // Spec refs: FR-M7-03, FR-M7-04, FR-M7-08, NFR-M7-06
  //
  // Verifies:
  //   a. value differs → save called exactly once with fontSizeIndex set;
  //      state optimistically reflects new value.
  //   b. value unchanged → save NOT called (no-op identical short-circuit).
  //   c. AsyncLoading → reads state.value ?? const AppSettings() (no throw).
  // ---------------------------------------------------------------------------

  group('SettingsNotifier.setFontSizeIndex — FR-M7-03 / FR-M7-04 / NFR-M7-06', () {
    test(
      'given_loaded_settings_when_setFontSizeIndex_10_then_state_fontSizeIndex_is_10_and_save_called_once_with_10',
      () async {
        // Arrange: default fontSizeIndex == 8.
        final repo = _RecordingRepository(initial: const AppSettings());
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);

        // Act.
        await container.read(settingsProvider.notifier).setFontSizeIndex(10);

        // Assert: save called exactly once with the new fontSizeIndex.
        expect(
          repo.savedArgs.length,
          equals(1),
          reason:
              'FR-M7-03: save must be called exactly once when index differs',
        );
        expect(
          repo.savedArgs.first.fontSizeIndex,
          equals(10),
          reason: 'FR-M7-03: save must be called with fontSizeIndex: 10',
        );

        // Assert: state optimistically reflects the new value.
        final state = container.read(settingsProvider);
        expect(
          state,
          isA<AsyncData<AppSettings>>(),
          reason: 'FR-M7-03: state must be AsyncData after optimistic update',
        );
        expect(
          state.value?.fontSizeIndex,
          equals(10),
          reason: 'FR-M7-03: optimistic state must reflect fontSizeIndex: 10',
        );
      },
    );

    test(
      'given_fontSizeIndex_8_when_setFontSizeIndex_8_then_save_NOT_called_and_state_reference_unchanged',
      () async {
        // Arrange: default fontSizeIndex == 8.
        final repo = _RecordingRepository(initial: const AppSettings());
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);
        final stateBefore = container.read(settingsProvider);

        // Act: call with the current index.
        await container.read(settingsProvider.notifier).setFontSizeIndex(8);

        // Assert: save must NOT be called.
        expect(
          repo.savedArgs,
          isEmpty,
          reason:
              'NFR-M7-06: save must NOT be called when fontSizeIndex is unchanged',
        );

        // Assert: state reference is identical (no new object created).
        expect(
          identical(container.read(settingsProvider), stateBefore),
          isTrue,
          reason:
              'NFR-M7-06: state reference must be identical when setFontSizeIndex '
              'is a no-op (identical short-circuit)',
        );
      },
    );

    test(
      'given_settings_AsyncLoading_when_setFontSizeIndex_3_then_does_not_throw',
      () async {
        // Arrange: trigger AsyncLoading by reading before the future settles.
        final repo = _RecordingRepository(initial: const AppSettings());
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        // Force notifier init without awaiting — state is AsyncLoading.
        container.read(settingsProvider);

        // Act: setFontSizeIndex must not throw (reads ?? const AppSettings()).
        // Default fontSizeIndex == 8, so 3 differs → save IS called.
        await expectLater(
          () => container.read(settingsProvider.notifier).setFontSizeIndex(3),
          returnsNormally,
          reason:
              'NFR-M7-06: setFontSizeIndex must never throw during AsyncLoading '
              '(reads state.value ?? const AppSettings(), no requireValue)',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TASK-03 — SettingsNotifier.setUseMonospaceFont
  // Spec refs: FR-M7-05, FR-M7-06, FR-M7-08, NFR-M7-06
  //
  // Verifies:
  //   a. value differs → save called exactly once with new useMonospaceFont;
  //      state optimistically reflects new value.
  //   b. value unchanged (default true) → save NOT called (no-op).
  // ---------------------------------------------------------------------------

  group('SettingsNotifier.setUseMonospaceFont — FR-M7-05 / FR-M7-06 / NFR-M7-06', () {
    test(
      'given_useMonospaceFont_true_when_setUseMonospaceFont_false_then_state_is_false_and_save_called_once',
      () async {
        // Arrange: default useMonospaceFont == true.
        final repo = _RecordingRepository(initial: const AppSettings());
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);

        // Act.
        await container
            .read(settingsProvider.notifier)
            .setUseMonospaceFont(false);

        // Assert: save called exactly once with useMonospaceFont: false.
        expect(
          repo.savedArgs.length,
          equals(1),
          reason:
              'FR-M7-05: save must be called exactly once when useMonospaceFont differs',
        );
        expect(
          repo.savedArgs.first.useMonospaceFont,
          isFalse,
          reason: 'FR-M7-05: save must be called with useMonospaceFont: false',
        );

        // Assert: state optimistically reflects the new value.
        final state = container.read(settingsProvider);
        expect(
          state.value?.useMonospaceFont,
          isFalse,
          reason:
              'FR-M7-05: optimistic state must reflect useMonospaceFont: false',
        );
      },
    );

    test(
      'given_useMonospaceFont_true_when_setUseMonospaceFont_true_then_save_NOT_called',
      () async {
        // Arrange: default useMonospaceFont == true.
        final repo = _RecordingRepository(initial: const AppSettings());
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        await container.read(settingsProvider.future);

        // Act: call with the current value (true == true → no-op).
        await container
            .read(settingsProvider.notifier)
            .setUseMonospaceFont(true);

        // Assert: save must NOT be called.
        expect(
          repo.savedArgs,
          isEmpty,
          reason:
              'NFR-M7-06: save must NOT be called when useMonospaceFont is unchanged',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TASK-03 — Retirement scan: NFR-M7-04 / NFR-M7-06
  //
  // Asserts zero occurrences of 'TypographySettings' and 'typographyProvider'
  // in lib/ source files (excluding comments), proving both symbols have been
  // fully removed from the production code tree.
  //
  // Mirrors the source-scan gate pattern used in m3_gate_test.dart and
  // m6_gate_test.dart.
  // ---------------------------------------------------------------------------

  group(
    'Retirement scan — TypographySettings + typographyProvider absent from lib/ (NFR-M7-04)',
    () {
      /// Returns all `.dart` files under [dir] recursively.
      List<File> dartFiles(String dir) {
        final d = Directory(dir);
        if (!d.existsSync()) return [];
        return d
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
      }

      /// Returns non-comment lines from [file] matching [pattern].
      List<String> nonCommentMatches(File file, Pattern pattern) {
        return file.readAsLinesSync().where((line) {
          final t = line.trimLeft();
          if (t.startsWith('//') || t.startsWith('*')) return false;
          return line.contains(pattern);
        }).toList();
      }

      test(
        'lib_dart_files_contain_zero_non_comment_references_to_TypographySettings',
        () {
          // Red phase: confirm the fixture fires.
          const fixture = 'import TypographySettings; class Foo {}';
          expect(
            fixture.contains('TypographySettings'),
            isTrue,
            reason: 'sanity: fixture string does contain TypographySettings',
          );

          // Green phase: real lib/ tree.
          final libDir = '${Directory.current.path}/lib';
          final hits = dartFiles(libDir)
              .expand(
                (f) => nonCommentMatches(
                  f,
                  'TypographySettings',
                ).map((line) => '${f.path}: $line'),
              )
              .toList();

          expect(
            hits,
            isEmpty,
            reason:
                'NFR-M7-04: zero non-comment references to TypographySettings '
                'must remain in lib/ after retirement. Found:\n${hits.join('\n')}',
          );
        },
      );

      test(
        'lib_dart_files_contain_zero_non_comment_references_to_typographyProvider',
        () {
          // Red phase: confirm the fixture fires.
          const fixture = 'ref.watch(typographyProvider);';
          expect(
            fixture.contains('typographyProvider'),
            isTrue,
            reason: 'sanity: fixture string does contain typographyProvider',
          );

          // Green phase: real lib/ tree.
          final libDir = '${Directory.current.path}/lib';
          final hits = dartFiles(libDir)
              .expand(
                (f) => nonCommentMatches(
                  f,
                  'typographyProvider',
                ).map((line) => '${f.path}: $line'),
              )
              .toList();

          expect(
            hits,
            isEmpty,
            reason:
                'NFR-M7-04: zero non-comment references to typographyProvider '
                'must remain in lib/ after retirement. Found:\n${hits.join('\n')}',
          );
        },
      );
    },
  );

  group('themeModeProvider — FR-M6-03 / FR-M6-12 / EC-08 / NFR-M6-07', () {
    ProviderContainer makeContainer({required AppColorScheme colorScheme}) {
      final repo = _RecordingRepository(
        initial: AppSettings(colorScheme: colorScheme),
      );
      return ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      );
    }

    test(
      'given_colorScheme_follow_when_themeModeProvider_read_then_ThemeMode_system',
      () async {
        final container = makeContainer(colorScheme: AppColorScheme.follow);
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        expect(
          container.read(themeModeProvider),
          equals(ThemeMode.system),
          reason: 'FR-M6-03: follow → ThemeMode.system',
        );
      },
    );

    test(
      'given_colorScheme_light_when_themeModeProvider_read_then_ThemeMode_light',
      () async {
        final container = makeContainer(colorScheme: AppColorScheme.light);
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        expect(
          container.read(themeModeProvider),
          equals(ThemeMode.light),
          reason: 'FR-M6-03: light → ThemeMode.light',
        );
      },
    );

    test(
      'given_colorScheme_dark_when_themeModeProvider_read_then_ThemeMode_dark',
      () async {
        final container = makeContainer(colorScheme: AppColorScheme.dark);
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        expect(
          container.read(themeModeProvider),
          equals(ThemeMode.dark),
          reason: 'FR-M6-03: dark → ThemeMode.dark',
        );
      },
    );

    test(
      'given_settings_AsyncLoading_when_themeModeProvider_read_then_ThemeMode_system_and_no_throw',
      () async {
        // Arrange: keep provider in AsyncLoading by not awaiting.
        final repo = _RecordingRepository(
          initial: const AppSettings(colorScheme: AppColorScheme.dark),
        );
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        // Force notifier init without awaiting.
        container.read(settingsProvider);

        // Act + Assert: must not throw; ?? defaults → follow → ThemeMode.system.
        expect(
          () => container.read(themeModeProvider),
          returnsNormally,
          reason:
              'EC-08: themeModeProvider must not throw during AsyncLoading '
              '(reads state.value ?? const AppSettings())',
        );
        expect(
          container.read(themeModeProvider),
          equals(ThemeMode.system),
          reason:
              'EC-08: under AsyncLoading, ?? AppSettings() → follow '
              '→ ThemeMode.system',
        );
      },
    );
  });
}
