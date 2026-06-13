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
// save() writes EXACTLY six upstream gschema keys:
//
//   setBool("use-monospace-font",   s.useMonospaceFont)          // bool
//   setBool("show-line-numbers",    s.showLineNumbers)            // bool
//   setBool("check-spelling",       s.spellingEnabled)            // bool
//   setBool("save-emergency-files", s.emergencyRecoveryEnabled)   // bool
//   setInt("emergency-recovery-files", s.emergencyRecoveryFiles)  // 0 or 10
//   setInt("line-length",           s.lineLength)                 // 800 or 100000
//
// There is NO "line-length-enabled" key.
// There is NO "font-size" key.
//
// load() derives lineLengthEnabled from the stored int "line-length":
//   enabled iff (storedLineLength ?? 800) <= 800
//   i.e. 800 → true, 100000 → false, absent → default true
//
// load() derives emergencyRecoveryEnabled directly from the bool key
//   "save-emergency-files".
//
// ---------------------------------------------------------------------------
// Spec refs: FR-13, EC-04, FR-12, OQ-B1
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
        expect(settings.showLineNumbers, isFalse);
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
          showLineNumbers: true,
          spellingEnabled: false,
          emergencyRecoveryEnabled: false,
          lineLengthEnabled: false,
        );

        await repo.save(saved);
        final loaded = await repo.load();

        expect(loaded.useMonospaceFont, isFalse);
        expect(loaded.showLineNumbers, isTrue);
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
      'given_default_settings_when_save_called_then_prefs_contains_exactly_six_verbatim_upstream_keys',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SharedPreferencesSettingsRepository(prefs);

        await repo.save(AppSettings());

        final keys = prefs.getKeys();

        // The six required upstream gschema keys must be present.
        expect(
          keys,
          containsAll(<String>{
            AppSettings.kUseMonospaceFont,
            AppSettings.kShowLineNumbers,
            AppSettings.kSpellingEnabled,
            AppSettings.kEmergencyRecoveryEnabled,
            AppSettings.kEmergencyRecoveryFiles,
            AppSettings.kLineLength,
          }),
          reason: 'OQ-B1: all six upstream gschema keys must be written',
        );

        // Exactly six keys — no extras.
        expect(
          keys,
          hasLength(6),
          reason: 'OQ-B1: save() must write exactly six keys, no more, no less',
        );

        // Forbidden keys — must not appear.
        expect(
          keys,
          isNot(contains('line-length-enabled')),
          reason:
              "OQ-B1: 'line-length-enabled' is not an upstream gschema key and must never be written",
        );
        expect(
          keys,
          isNot(contains('font-size')),
          reason:
              "OQ-B1: 'font-size' is deferred to a later milestone and must not be written here",
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
}
