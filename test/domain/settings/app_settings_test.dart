// ignore_for_file: prefer_const_constructors
// Const constructors require the generated freezed code to exist; at the RED
// phase the generated part file is absent, so const is intentionally deferred.
//
// Key-constant naming assumption (for the implementer):
//   AppSettings exposes six static const String fields using the `k` prefix +
//   camelCase field name:
//     AppSettings.kUseMonospaceFont       == "use-monospace-font"
//     AppSettings.kShowLineNumbers        == "show-line-numbers"
//     AppSettings.kSpellingEnabled        == "check-spelling"
//     AppSettings.kEmergencyRecoveryEnabled == "save-emergency-files"
//     AppSettings.kEmergencyRecoveryFiles == "emergency-recovery-files"
//     AppSettings.kLineLength             == "line-length"
//
// <!-- VERIFY: OQ-B1 — confirm each key string against the upstream GNOME
//   Buffer gschema before TASK-13 (SharedPreferencesSettingsRepository) is
//   committed. A mismatch means stored values are never found on-device. -->

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Integer-proxy mapping — FR-12
  // ---------------------------------------------------------------------------
  group('AppSettings integer-proxy mapping (FR-12)', () {
    test(
      'given_emergencyRecoveryEnabled_true_when_constructed_then_emergencyRecoveryFiles_equals_10',
      () {
        final settings = AppSettings(emergencyRecoveryEnabled: true);

        expect(settings.emergencyRecoveryFiles, equals(10));
      },
    );

    test(
      'given_emergencyRecoveryEnabled_false_when_constructed_then_emergencyRecoveryFiles_equals_0',
      () {
        final settings = AppSettings(emergencyRecoveryEnabled: false);

        expect(settings.emergencyRecoveryFiles, equals(0));
      },
    );

    test(
      'given_lineLength_enabled_true_when_constructed_then_lineLength_equals_800',
      () {
        // lineLength is the vestigial integer proxy; "enabled" maps to the
        // upstream GNOME on-value 800.
        // The impl derives this from a `lineLengthEnabled` boolean (default
        // true). We construct with the default (enabled) here.
        final settings = AppSettings(lineLengthEnabled: true);

        expect(settings.lineLength, equals(800));
      },
    );

    test(
      'given_lineLength_enabled_false_when_constructed_then_lineLength_equals_100000',
      () {
        final settings = AppSettings(lineLengthEnabled: false);

        expect(settings.lineLength, equals(100000));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // copyWith single-mutation-point — EC-06
  // ---------------------------------------------------------------------------
  group('AppSettings copyWith single-mutation-point (EC-06)', () {
    test(
      'given_emergencyRecoveryEnabled_true_when_copyWith_false_then_flag_is_false_and_proxy_updates_to_0',
      () {
        final original = AppSettings(emergencyRecoveryEnabled: true);

        final updated = original.copyWith(emergencyRecoveryEnabled: false);

        expect(updated.emergencyRecoveryEnabled, isFalse);
        expect(updated.emergencyRecoveryFiles, equals(0));
      },
    );

    test(
      'given_emergencyRecoveryEnabled_false_when_copyWith_true_then_flag_is_true_and_proxy_updates_to_10',
      () {
        final original = AppSettings(emergencyRecoveryEnabled: false);

        final updated = original.copyWith(emergencyRecoveryEnabled: true);

        expect(updated.emergencyRecoveryEnabled, isTrue);
        expect(updated.emergencyRecoveryFiles, equals(10));
      },
    );

    test(
      'given_any_settings_when_copyWith_applied_then_original_is_unchanged',
      () {
        final original = AppSettings(emergencyRecoveryEnabled: true);

        final copy = original.copyWith(emergencyRecoveryEnabled: false);

        expect(copy.emergencyRecoveryEnabled, isFalse);
        expect(original.emergencyRecoveryEnabled, isTrue);
        expect(original.emergencyRecoveryFiles, equals(10));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Key-string fidelity — FR-12 / §5.2
  //
  // The impl exposes static const String fields on AppSettings using the
  // `k` prefix + camelCase field name (see file-level comment for the
  // assumed naming convention).
  // ---------------------------------------------------------------------------
  group('AppSettings key-string fidelity (FR-12/§5.2)', () {
    test(
      'given_key_constant_kUseMonospaceFont_when_read_then_equals_upstream_gschema_key',
      () {
        expect(AppSettings.kUseMonospaceFont, equals('use-monospace-font'));
      },
    );

    test(
      'given_key_constant_kShowLineNumbers_when_read_then_equals_upstream_gschema_key',
      () {
        expect(AppSettings.kShowLineNumbers, equals('show-line-numbers'));
      },
    );

    test(
      'given_key_constant_kSpellingEnabled_when_read_then_equals_upstream_gschema_key',
      () {
        expect(AppSettings.kSpellingEnabled, equals('check-spelling'));
      },
    );

    test(
      'given_key_constant_kEmergencyRecoveryEnabled_when_read_then_equals_upstream_gschema_key',
      () {
        expect(
          AppSettings.kEmergencyRecoveryEnabled,
          equals('save-emergency-files'),
        );
      },
    );

    test(
      'given_key_constant_kEmergencyRecoveryFiles_when_read_then_equals_upstream_gschema_key',
      () {
        expect(
          AppSettings.kEmergencyRecoveryFiles,
          equals('emergency-recovery-files'),
        );
      },
    );

    test(
      'given_key_constant_kLineLength_when_read_then_equals_upstream_gschema_key',
      () {
        expect(AppSettings.kLineLength, equals('line-length'));
      },
    );
  });
}
