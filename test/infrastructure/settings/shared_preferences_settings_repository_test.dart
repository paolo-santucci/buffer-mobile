// TASK-13: SharedPreferencesSettingsRepository test — RED phase.
//
// This file will not compile until the implementation at
// lib/infrastructure/settings/shared_preferences_settings_repository.dart
// exists. That is the expected state: tests first, implementation next.
//
// ---------------------------------------------------------------------------
// Constructor shape assumed by these tests
// ---------------------------------------------------------------------------
//
// The implementation must accept a SharedPreferences instance via constructor
// injection:
//
//   class SharedPreferencesSettingsRepository implements SettingsRepository {
//     SharedPreferencesSettingsRepository(this._prefs);
//
//     final SharedPreferences _prefs;
//
//     @override
//     Future<AppSettings> load() async { ... }
//
//     @override
//     Future<void> save(AppSettings settings) async { ... }
//   }
//
// Tests use SharedPreferences.setMockInitialValues({...}) to seed the store,
// then obtain the instance via SharedPreferences.getInstance() and inject it
// directly — no platform channel is invoked during the test.
//
// ---------------------------------------------------------------------------
// Resolved OQ-B1 persistence contract (authoritative)
// ---------------------------------------------------------------------------
//
// save() writes EXACTLY seven upstream gschema keys:
//
//   setBool("use-monospace-font",   s.useMonospaceFont)          // bool
//   setBool("check-spelling",       s.spellingEnabled)            // bool
//   setBool("save-emergency-files", s.emergencyRecoveryEnabled)   // bool
//   setInt("emergency-recovery-files", s.emergencyRecoveryFiles)  // 0 or 10
//   setInt("line-length",           s.lineLength)                 // 800 or 100000
//   setString("color-scheme",       s.colorScheme.name)          // follow|light|dark
//   setInt("font-size",             s.fontSizeIndex)              // 0–20
//
// There is NO "line-length-enabled" key.
//
// load() derives lineLengthEnabled from the stored int "line-length":
//   enabled iff (storedLineLength ?? 800) <= 800
//   i.e. 800 → true, 100000 → false, absent → default true
//
// load() derives emergencyRecoveryEnabled directly from the bool key
//   "save-emergency-files".
//
// load() reads fontSizeIndex from int "font-size":
//   absent/corrupt → 8 (default); stored value → clamped to [0, 20].
//
// ---------------------------------------------------------------------------
// Spec refs: FR-13, EC-04, FR-12, OQ-B1, FR-M7-03, NFR-M7-04
// ---------------------------------------------------------------------------

// ignore_for_file: prefer_const_constructors

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/infrastructure/settings/shared_preferences_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // -------------------------------------------------------------------------
  // FR-13 / EC-01 — load() with no stored keys returns AppSettings defaults
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.load — empty store', () {
    test(
      'given_no_stored_keys_when_load_called_then_returns_AppSettings_defaults',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        // FR-13: default values as per AppSettings factory defaults.
        expect(settings.emergencyRecoveryEnabled, isTrue);
        expect(settings.spellingEnabled, isTrue);
        expect(settings.useMonospaceFont, isTrue);
        expect(settings.lineLengthEnabled, isTrue);

        // Derived integer getters must reflect defaults.
        expect(settings.emergencyRecoveryFiles, equals(10));
        expect(settings.lineLength, equals(800));
      },
    );
  });

  // -------------------------------------------------------------------------
  // EC-04 — corrupt / wrong-type value returns field's canonical default,
  //          no throw.
  //
  // SharedPreferences.getBool returns null when the stored type does not
  // match (e.g. a String stored under a bool key). The repository must treat
  // null as "absent" and fall back to the field default — no throw.
  //
  // We seed kEmergencyRecoveryEnabled with a String value; getBool returns null
  // on type mismatch, triggering the default-fallback path.
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.load — corrupt value', () {
    test(
      'given_emergency_recovery_key_stores_corrupt_string_when_load_called_then_field_returns_default_and_does_not_throw',
      () async {
        SharedPreferences.setMockInitialValues({
          AppSettings.kEmergencyRecoveryEnabled: 'CORRUPT',
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        // Must not throw regardless of the corrupt stored type.
        final AppSettings settings;
        try {
          settings = await repo.load();
        } catch (_) {
          fail(
            'load() must not throw when a stored value is of the wrong type',
          );
        }

        // Field must fall back to its canonical default (true).
        expect(
          settings.emergencyRecoveryEnabled,
          isTrue,
          reason:
              'EC-04: corrupt value must yield the field default, not throw',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // FR-12 — save() then load() round-trips boolean toggles correctly.
  //
  // Tests that toggled values survive a save→load cycle. lineLengthEnabled
  // is NOT stored directly — it is derived from the int "line-length" value:
  //   lineLengthEnabled=false → lineLength=100000 stored → load() derives false
  //   lineLengthEnabled=true  → lineLength=800   stored → load() derives true
  //
  // emergencyRecoveryEnabled is stored directly as bool "save-emergency-files".
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.save then load — round-trip', () {
    test(
      'given_settings_with_emergency_recovery_and_line_length_disabled_when_save_then_load_then_both_are_false',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        const saved = AppSettings(
          emergencyRecoveryEnabled: false,
          lineLengthEnabled: false,
        );

        await repo.save(saved);
        final loaded = await repo.load();

        expect(
          loaded.emergencyRecoveryEnabled,
          isFalse,
          reason: 'FR-12: emergencyRecoveryEnabled round-trip false→false',
        );
        expect(
          loaded.lineLengthEnabled,
          isFalse,
          reason:
              'FR-12: lineLengthEnabled derived from int 100000 must be false',
        );
      },
    );

    test(
      'given_settings_with_emergency_recovery_and_line_length_enabled_when_save_then_load_then_both_are_true',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        const saved = AppSettings(
          emergencyRecoveryEnabled: true,
          lineLengthEnabled: true,
        );

        await repo.save(saved);
        final loaded = await repo.load();

        expect(
          loaded.emergencyRecoveryEnabled,
          isTrue,
          reason: 'FR-12: emergencyRecoveryEnabled round-trip true→true',
        );
        expect(
          loaded.lineLengthEnabled,
          isTrue,
          reason: 'FR-12: lineLengthEnabled derived from int 800 must be true',
        );
      },
    );

    test(
      'given_settings_with_all_booleans_toggled_when_save_then_load_then_values_match',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        // Flip every field away from its default.
        const saved = AppSettings(
          useMonospaceFont: false,
          spellingEnabled: false,
          emergencyRecoveryEnabled: false,
          lineLengthEnabled: false,
        );

        await repo.save(saved);
        final loaded = await repo.load();

        expect(loaded.useMonospaceFont, isFalse);
        expect(loaded.spellingEnabled, isFalse);
        expect(loaded.emergencyRecoveryEnabled, isFalse);
        expect(loaded.lineLengthEnabled, isFalse);

        // Derived integer getters must reflect the toggled booleans (EC-06).
        expect(
          loaded.emergencyRecoveryFiles,
          equals(0),
          reason:
              'emergencyRecoveryEnabled=false → emergencyRecoveryFiles must be 0',
        );
        expect(
          loaded.lineLength,
          equals(100000),
          reason: 'lineLengthEnabled=false → lineLength must be 100000',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // FR-12 / §5.2 / OQ-B1 — key-string fidelity.
  //
  // After save(), the raw SharedPreferences backing store must contain EXACTLY
  // six entries keyed on the verbatim upstream gschema strings. No extra keys
  // ("line-length-enabled", "font-size", etc.) must appear.
  //
  // The int key "line-length" holds 800 when lineLengthEnabled, 100000 when
  // not. "emergency-recovery-files" holds 10 when enabled, 0 when not.
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.save — key-string fidelity (OQ-B1)', () {
    test(
      'given_default_settings_when_save_called_then_prefs_contains_exactly_seven_verbatim_upstream_keys',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings());

        final keys = prefs.getKeys();

        // The seven required upstream gschema keys must be present.
        expect(
          keys,
          containsAll(<String>{
            AppSettings.kUseMonospaceFont,
            AppSettings.kSpellingEnabled,
            AppSettings.kEmergencyRecoveryEnabled,
            AppSettings.kEmergencyRecoveryFiles,
            AppSettings.kLineLength,
            AppSettings.kColorScheme,
            AppSettings.kFontSize,
          }),
          reason:
              'OQ-B1: all seven upstream gschema keys must be written (6 M6 keys + font-size)',
        );

        // Exactly seven keys — no extras.
        expect(
          keys,
          hasLength(7),
          reason:
              'OQ-B1: save() must write exactly seven keys after line-number removal',
        );

        // Forbidden keys — must not appear.
        expect(
          keys,
          isNot(contains('line-length-enabled')),
          reason:
              "OQ-B1: 'line-length-enabled' is not an upstream gschema key and must never be written",
        );
      },
    );

    test(
      'given_line_length_enabled_true_when_save_called_then_int_key_line_length_holds_800',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(lineLengthEnabled: true));

        expect(
          prefs.getInt(AppSettings.kLineLength),
          equals(800),
          reason: 'lineLengthEnabled=true → line-length int key must be 800',
        );
      },
    );

    test(
      'given_line_length_enabled_false_when_save_called_then_int_key_line_length_holds_100000',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(lineLengthEnabled: false));

        expect(
          prefs.getInt(AppSettings.kLineLength),
          equals(100000),
          reason:
              'lineLengthEnabled=false → line-length int key must be 100000',
        );
      },
    );

    test(
      'given_emergency_recovery_enabled_true_when_save_called_then_int_key_emergency_recovery_files_holds_10',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(emergencyRecoveryEnabled: true));

        expect(
          prefs.getInt(AppSettings.kEmergencyRecoveryFiles),
          equals(10),
          reason:
              'emergencyRecoveryEnabled=true → emergency-recovery-files int key must be 10',
        );
      },
    );

    test(
      'given_emergency_recovery_enabled_false_when_save_called_then_int_key_emergency_recovery_files_holds_0',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(emergencyRecoveryEnabled: false));

        expect(
          prefs.getInt(AppSettings.kEmergencyRecoveryFiles),
          equals(0),
          reason:
              'emergencyRecoveryEnabled=false → emergency-recovery-files int key must be 0',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // TASK-03 / FR-M6-01 / EC-01 — load() with stored 'color-scheme' strings.
  //
  // Tests that known values parse to the correct enum case, absent key falls
  // back to follow (no throw), and a garbage value falls back to follow (no
  // throw). Safe switch-fallback — never unguarded AppColorScheme.values.byName.
  // -------------------------------------------------------------------------

  group(
    'SharedPreferencesSettingsRepository.load — color-scheme happy paths (FR-M6-01)',
    () {
      test(
        'given_color_scheme_key_holds_dark_when_load_called_then_colorScheme_is_dark',
        () async {
          SharedPreferences.setMockInitialValues({
            AppSettings.kColorScheme: 'dark',
          });
          final prefs = await SharedPreferences.getInstance();
          final repo = SharedPreferencesSettingsRepository(prefs);

          final settings = await repo.load();

          expect(
            settings.colorScheme,
            AppColorScheme.dark,
            reason: "FR-M6-01: 'dark' string must parse to AppColorScheme.dark",
          );
        },
      );

      test(
        'given_color_scheme_key_holds_light_when_load_called_then_colorScheme_is_light',
        () async {
          SharedPreferences.setMockInitialValues({
            AppSettings.kColorScheme: 'light',
          });
          final prefs = await SharedPreferences.getInstance();
          final repo = SharedPreferencesSettingsRepository(prefs);

          final settings = await repo.load();

          expect(
            settings.colorScheme,
            AppColorScheme.light,
            reason:
                "FR-M6-01: 'light' string must parse to AppColorScheme.light",
          );
        },
      );

      test(
        'given_color_scheme_key_holds_follow_when_load_called_then_colorScheme_is_follow',
        () async {
          SharedPreferences.setMockInitialValues({
            AppSettings.kColorScheme: 'follow',
          });
          final prefs = await SharedPreferences.getInstance();
          final repo = SharedPreferencesSettingsRepository(prefs);

          final settings = await repo.load();

          expect(
            settings.colorScheme,
            AppColorScheme.follow,
            reason:
                "FR-M6-01: 'follow' string must parse to AppColorScheme.follow",
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // TASK-03 / EC-01 — safe fallback on absent/garbage color-scheme.
  //
  // Absent key → follow (default). Garbage value ('foo') → follow (no throw).
  // The parse MUST use a safe switch/map fallback, NOT byName (which throws on
  // unknown values).
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.load — color-scheme EC-01 fallback', () {
    test(
      'given_color_scheme_key_absent_when_load_called_then_colorScheme_defaults_to_follow',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.colorScheme,
          AppColorScheme.follow,
          reason:
              'EC-01: absent color-scheme key must yield follow (default), not throw',
        );
      },
    );

    test(
      'given_color_scheme_key_holds_garbage_when_load_called_then_colorScheme_defaults_to_follow_and_does_not_throw',
      () async {
        SharedPreferences.setMockInitialValues({
          AppSettings.kColorScheme: 'foo',
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final AppSettings settings;
        try {
          settings = await repo.load();
        } catch (_) {
          fail(
            'EC-01: load() must not throw on garbage color-scheme value — '
            'safe switch/map fallback required, NOT unguarded byName',
          );
        }

        expect(
          settings.colorScheme,
          AppColorScheme.follow,
          reason:
              "EC-01: garbage value 'foo' must fall back to follow, not throw",
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // TASK-03 / FR-M6-12 — save() writes 'color-scheme' string key.
  //
  // After save(AppSettings(colorScheme: dark)), the raw prefs store must hold
  // 'dark' under 'color-scheme'. Existing six keys are also written atomically
  // in the same call. Total key count is now 7 (6 original + color-scheme).
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.save — color-scheme (FR-M6-12)', () {
    test(
      'given_settings_with_colorScheme_dark_when_save_called_then_color_scheme_key_holds_dark',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(colorScheme: AppColorScheme.dark));

        expect(
          prefs.getString(AppSettings.kColorScheme),
          equals('dark'),
          reason:
              "FR-M6-12: colorScheme=dark must write 'dark' under 'color-scheme' key",
        );
      },
    );

    test(
      'given_settings_with_colorScheme_dark_when_save_called_then_all_seven_keys_are_written_atomically',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(colorScheme: AppColorScheme.dark));

        final keys = prefs.getKeys();

        // All seven keys written in the same save() call.
        expect(
          keys,
          containsAll(<String>{
            AppSettings.kUseMonospaceFont,
            AppSettings.kSpellingEnabled,
            AppSettings.kEmergencyRecoveryEnabled,
            AppSettings.kEmergencyRecoveryFiles,
            AppSettings.kLineLength,
            AppSettings.kColorScheme,
            AppSettings.kFontSize,
          }),
          reason:
              'FR-M6-12/§5.2/FR-M7-03: all seven keys must be written in the same save() call',
        );

        // Exactly seven keys — no extras.
        expect(
          keys,
          hasLength(7),
          reason:
              'save() must write exactly seven keys after line-number removal',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // TASK-03 / EC-02 — save() propagates setString failure; repo does not
  // mutate in-memory state.
  //
  // SharedPreferences mock does not support simulating setString failure
  // directly. This test verifies the structural guarantee: the repository
  // holds no mutable in-memory state (all state lives in the injected prefs
  // and the domain AppSettings value passed to save()). The next load() will
  // read the state from prefs — which is exactly what the caller controls.
  // Structural regression guard: save() must not swallow exceptions.
  // -------------------------------------------------------------------------
  //
  // NOTE: The mock SharedPreferences cannot simulate a disk-full throw from
  // setString in the current test harness. The EC-02 structural invariant is
  // instead verified through the implementation review (save() has no try/catch
  // swallowing exceptions — it lets platform exceptions propagate). This is
  // documented as a known limitation of the mock-based test approach.
  //
  // The absence of in-memory state mutation is structural: the repository has
  // no fields other than `_prefs` (the injected SharedPreferences instance);
  // there is no `_cachedSettings` or similar field to corrupt.

  // -------------------------------------------------------------------------
  // TASK-03 / FR-M6-13 / D8 — line-length round-trips; no new setter exposed.
  //
  // The line-length key is vestigial: load() reads it for lineLengthEnabled
  // derivation; save() writes it as derived int. No new public method for it.
  // Verified by the existing round-trip tests above, plus this regression guard.
  // -------------------------------------------------------------------------

  group(
    'SharedPreferencesSettingsRepository — line-length vestigial round-trip (FR-M6-13/D8)',
    () {
      test(
        'given_line_length_100000_in_prefs_when_save_then_load_then_round_trips_without_color_scheme_interference',
        () async {
          SharedPreferences.setMockInitialValues({
            AppSettings.kLineLength: 100000,
          });
          final prefs = await SharedPreferences.getInstance();
          final repo = SharedPreferencesSettingsRepository(prefs);

          // Save with a non-default colorScheme to confirm the two fields
          // are independent and do not interfere with each other.
          await repo.save(
            AppSettings(
              lineLengthEnabled: false,
              colorScheme: AppColorScheme.dark,
            ),
          );
          final loaded = await repo.load();

          expect(
            loaded.lineLengthEnabled,
            isFalse,
            reason:
                'FR-M6-13: line-length round-trip must not be broken by color-scheme addition',
          );
          expect(
            loaded.colorScheme,
            AppColorScheme.dark,
            reason:
                'FR-M6-12: color-scheme must round-trip independently of line-length',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // line-length derivation — load() derives lineLengthEnabled from stored int.
  //
  // Seeding the mock prefs directly (bypassing save()) exercises the load()
  // read path in isolation, confirming the derivation logic:
  //   (storedLineLength ?? 800) <= 800  →  lineLengthEnabled
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository.load — lineLengthEnabled derivation', () {
    test(
      'given_line_length_int_key_holds_100000_when_load_called_then_lineLengthEnabled_is_false',
      () async {
        SharedPreferences.setMockInitialValues({
          AppSettings.kLineLength: 100000,
        });
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.lineLengthEnabled,
          isFalse,
          reason: 'Stored int 100000 > 800 → lineLengthEnabled must be false',
        );
      },
    );

    test(
      'given_line_length_int_key_holds_800_when_load_called_then_lineLengthEnabled_is_true',
      () async {
        SharedPreferences.setMockInitialValues({AppSettings.kLineLength: 800});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.lineLengthEnabled,
          isTrue,
          reason: 'Stored int 800 <= 800 → lineLengthEnabled must be true',
        );
      },
    );

    test(
      'given_line_length_int_key_absent_when_load_called_then_lineLengthEnabled_defaults_to_true',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.lineLengthEnabled,
          isTrue,
          reason:
              'Absent line-length key → null ?? 800 = 800 <= 800 → lineLengthEnabled must default to true',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // TASK-02 / FR-M7-03 / NFR-M7-04 — font-size key: persist, load, clamp.
  //
  // save() writes 'font-size' as the 8th key (setInt).
  // load() reads it: absent/corrupt → 8 (default); stored → clamped [0, 20].
  // -------------------------------------------------------------------------

  group('SharedPreferencesSettingsRepository — font-size round-trip (FR-M7-03)', () {
    test(
      'given_fontSizeIndex_5_when_save_then_load_then_fontSizeIndex_is_5_and_key_count_is_7',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(fontSizeIndex: 5));
        final loaded = await repo.load();

        expect(
          loaded.fontSizeIndex,
          equals(5),
          reason:
              'FR-M7-03: fontSizeIndex must round-trip through save/load unchanged',
        );

        final keys = prefs.getKeys();
        expect(
          keys,
          hasLength(7),
          reason:
              'FR-M7-03: save() must write exactly 7 keys (6 prior + font-size)',
        );
        expect(
          keys,
          contains(AppSettings.kFontSize),
          reason: "FR-M7-03: 'font-size' key must be present in the store",
        );
      },
    );

    test(
      'given_fontSizeIndex_0_boundary_when_save_then_load_then_fontSizeIndex_is_0',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(fontSizeIndex: 0));
        final loaded = await repo.load();

        expect(
          loaded.fontSizeIndex,
          equals(0),
          reason: 'FR-M7-03: boundary 0 must round-trip as 0',
        );
      },
    );

    test(
      'given_fontSizeIndex_20_boundary_when_save_then_load_then_fontSizeIndex_is_20',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings(fontSizeIndex: 20));
        final loaded = await repo.load();

        expect(
          loaded.fontSizeIndex,
          equals(20),
          reason: 'FR-M7-03: boundary 20 must round-trip as 20',
        );
      },
    );
  });

  group(
    'SharedPreferencesSettingsRepository.load — font-size absent/corrupt (NFR-M7-04)',
    () {
      test(
        'given_font_size_key_absent_when_load_called_then_fontSizeIndex_defaults_to_8',
        () async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final repo = SharedPreferencesSettingsRepository(prefs);

          final settings = await repo.load();

          expect(
            settings.fontSizeIndex,
            equals(8),
            reason:
                'NFR-M7-04: absent font-size key must yield default index 8',
          );
        },
      );

      test(
        'given_font_size_key_holds_corrupt_string_when_load_called_then_fontSizeIndex_defaults_to_8_and_does_not_throw',
        () async {
          SharedPreferences.setMockInitialValues({
            AppSettings.kFontSize: 'not-an-int',
          });
          final prefs = await SharedPreferences.getInstance();
          final repo = SharedPreferencesSettingsRepository(prefs);

          final AppSettings settings;
          try {
            settings = await repo.load();
          } catch (_) {
            fail(
              'NFR-M7-04: load() must not throw when font-size key holds a corrupt (non-int) value',
            );
          }

          expect(
            settings.fontSizeIndex,
            equals(8),
            reason:
                'NFR-M7-04: corrupt font-size value must yield default index 8',
          );
        },
      );
    },
  );

  group('SharedPreferencesSettingsRepository.load — font-size clamp (NFR-M7-04)', () {
    test(
      'given_font_size_key_holds_minus1_when_load_called_then_fontSizeIndex_is_clamped_to_0',
      () async {
        SharedPreferences.setMockInitialValues({AppSettings.kFontSize: -1});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.fontSizeIndex,
          equals(0),
          reason: 'NFR-M7-04: out-of-range low (-1) must clamp to 0',
        );
      },
    );

    test(
      'given_font_size_key_holds_99_when_load_called_then_fontSizeIndex_is_clamped_to_20',
      () async {
        SharedPreferences.setMockInitialValues({AppSettings.kFontSize: 99});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.fontSizeIndex,
          equals(20),
          reason:
              'NFR-M7-04: out-of-range high (99) must clamp to 20 (slotList.length-1)',
        );
      },
    );

    test(
      'given_font_size_key_holds_21_when_load_called_then_fontSizeIndex_is_clamped_to_20',
      () async {
        SharedPreferences.setMockInitialValues({AppSettings.kFontSize: 21});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        final settings = await repo.load();

        expect(
          settings.fontSizeIndex,
          equals(20),
          reason: 'NFR-M7-04: index 21 (one past max) must clamp to 20',
        );
      },
    );
  });
}
