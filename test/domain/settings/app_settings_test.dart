// ignore_for_file: prefer_const_constructors
// Const constructors require the generated freezed code to exist; at the RED
// phase the generated part file is absent, so const is intentionally deferred.
//
// Key-constant naming assumption (for the implementer):
//   AppSettings exposes static const String fields using the `k` prefix +
//   camelCase field name:
//     AppSettings.kUseMonospaceFont         == "use-monospace-font"
//     AppSettings.kSpellingEnabled          == "check-spelling"
//     AppSettings.kEmergencyRecoveryEnabled == "save-emergency-files"
//     AppSettings.kEmergencyRecoveryFiles   == "emergency-recovery-files"
//     AppSettings.kLineLength               == "line-length"
//     AppSettings.kColorScheme              == "color-scheme"   (OQ-M6-05 pin)
//
// <!-- VERIFY: OQ-B1 — confirm each key string against the upstream GNOME
//   Buffer gschema before TASK-13 (SharedPreferencesSettingsRepository) is
//   committed. A mismatch means stored values are never found on-device. -->

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AppColorScheme enum shape — EC-01 / FR-M6-01
  // ---------------------------------------------------------------------------
  group('AppColorScheme enum (EC-01 / FR-M6-01)', () {
    test(
      'given_AppColorScheme_enum_when_values_listed_then_exactly_follow_light_dark',
      () {
        expect(
          AppColorScheme.values,
          equals([
            AppColorScheme.follow,
            AppColorScheme.light,
            AppColorScheme.dark,
          ]),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // colorScheme field — default, copyWith, equality (FR-M6-01, FR-M6-12, §5.1-a/b)
  // ---------------------------------------------------------------------------
  group('AppSettings.colorScheme field (FR-M6-01)', () {
    test(
      'given_default_AppSettings_when_colorScheme_read_then_equals_follow',
      () {
        final settings = AppSettings();

        expect(settings.colorScheme, equals(AppColorScheme.follow));
      },
    );

    test(
      'given_AppSettings_when_copyWith_colorScheme_dark_then_new_instance_has_dark',
      () {
        final original = AppSettings();

        final updated = original.copyWith(colorScheme: AppColorScheme.dark);

        expect(updated.colorScheme, equals(AppColorScheme.dark));
      },
    );

    test(
      'given_AppSettings_copyWith_colorScheme_dark_when_original_read_then_original_is_unchanged',
      () {
        final original = AppSettings();

        final copy = original.copyWith(colorScheme: AppColorScheme.dark);

        expect(copy.colorScheme, equals(AppColorScheme.dark));
        expect(original.colorScheme, equals(AppColorScheme.follow));
      },
    );

    test(
      'given_two_AppSettings_with_same_colorScheme_when_compared_then_equal',
      () {
        final a = AppSettings(colorScheme: AppColorScheme.light);
        final b = AppSettings(colorScheme: AppColorScheme.light);

        expect(a, equals(b));
      },
    );

    test(
      'given_two_AppSettings_with_different_colorScheme_when_compared_then_not_equal',
      () {
        final a = AppSettings(colorScheme: AppColorScheme.light);
        final b = AppSettings(colorScheme: AppColorScheme.dark);

        expect(a, isNot(equals(b)));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // kColorScheme key constant — OQ-M6-05 pin (NOT 'style-variant')
  // ---------------------------------------------------------------------------
  group('AppSettings.kColorScheme key constant (OQ-M6-05)', () {
    test(
      'given_key_constant_kColorScheme_when_read_then_equals_color_scheme_not_style_variant',
      () {
        expect(AppSettings.kColorScheme, equals('color-scheme'));
      },
    );
  });

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

  // ---------------------------------------------------------------------------
  // kFontSize key constant — FR-M7-01 / OQ-M7-03
  // ---------------------------------------------------------------------------
  group('AppSettings.kFontSize key constant (FR-M7-01)', () {
    test('given_key_constant_kFontSize_when_read_then_equals_font_size', () {
      expect(AppSettings.kFontSize, equals('font-size'));
    });
  });

  // ---------------------------------------------------------------------------
  // slotList invariants — FR-M7-01
  // ---------------------------------------------------------------------------
  group('AppSettings.slotList invariants (FR-M7-01)', () {
    test('given_slotList_when_length_checked_then_equals_21', () {
      expect(AppSettings.slotList.length, equals(21));
    });

    test('given_slotList_when_index_8_read_then_equals_14', () {
      expect(AppSettings.slotList[8], equals(14));
    });

    test('given_slotList_when_checked_then_strictly_ascending', () {
      final list = AppSettings.slotList;
      for (var i = 0; i < list.length - 1; i++) {
        expect(
          list[i] < list[i + 1],
          isTrue,
          reason:
              'slotList[$i]=${list[i]} is not less than slotList[${i + 1}]=${list[i + 1]}',
        );
      }
    });

    test('given_slotList_when_checked_then_no_duplicates', () {
      final list = AppSettings.slotList;
      expect(list.toSet().length, equals(list.length));
    });
  });

  // ---------------------------------------------------------------------------
  // fontSizePt derived getter — FR-M7-01
  // ---------------------------------------------------------------------------
  group('AppSettings.fontSizePt derived getter (FR-M7-01)', () {
    test('given_fontSizeIndex_0_when_fontSizePt_read_then_equals_6_0', () {
      final settings = AppSettings(fontSizeIndex: 0);
      expect(settings.fontSizePt, equals(6.0));
    });

    test('given_fontSizeIndex_20_when_fontSizePt_read_then_equals_38_0', () {
      final settings = AppSettings(fontSizeIndex: 20);
      expect(settings.fontSizePt, equals(38.0));
    });

    test('given_default_AppSettings_when_fontSizePt_read_then_equals_14_0', () {
      final settings = AppSettings();
      expect(settings.fontSizePt, equals(14.0));
    });
  });

  // ---------------------------------------------------------------------------
  // defaults — fontSizeIndex and existing fields
  // ---------------------------------------------------------------------------
  group('AppSettings defaults (FR-M7-01)', () {
    test('given_default_AppSettings_when_fontSizeIndex_read_then_equals_8', () {
      final settings = AppSettings();
      expect(settings.fontSizeIndex, equals(8));
    });

    test(
      'given_default_AppSettings_when_useMonospaceFont_read_then_equals_true',
      () {
        final settings = AppSettings();
        expect(settings.useMonospaceFont, isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // setFontSizeIndex — FR-M7-04
  // ---------------------------------------------------------------------------
  group('AppSettings.setFontSizeIndex (FR-M7-04)', () {
    test(
      'given_any_settings_when_setFontSizeIndex_10_then_index_becomes_10',
      () {
        final settings = AppSettings();
        expect(settings.setFontSizeIndex(10).fontSizeIndex, equals(10));
      },
    );

    test(
      'given_any_settings_when_setFontSizeIndex_minus1_then_index_clamped_to_0',
      () {
        final settings = AppSettings();
        expect(settings.setFontSizeIndex(-1).fontSizeIndex, equals(0));
      },
    );

    test(
      'given_any_settings_when_setFontSizeIndex_99_then_index_clamped_to_20',
      () {
        final settings = AppSettings();
        expect(settings.setFontSizeIndex(99).fontSizeIndex, equals(20));
      },
    );

    test(
      'given_any_settings_when_setFontSizeIndex_21_then_index_clamped_to_20',
      () {
        final settings = AppSettings();
        expect(settings.setFontSizeIndex(21).fontSizeIndex, equals(20));
      },
    );

    test(
      'given_fontSizeIndex_8_when_setFontSizeIndex_8_then_returns_identical_this',
      () {
        final settings = AppSettings(fontSizeIndex: 8);
        expect(identical(settings.setFontSizeIndex(8), settings), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // setUseMonospaceFont — FR-M7-01 (idempotent, NOT a toggle)
  // ---------------------------------------------------------------------------
  group('AppSettings.setUseMonospaceFont (FR-M7-01)', () {
    test(
      'given_useMonospaceFont_true_when_setUseMonospaceFont_false_then_new_instance_with_false',
      () {
        final settings = AppSettings(useMonospaceFont: true);
        final updated = settings.setUseMonospaceFont(false);
        expect(updated.useMonospaceFont, isFalse);
        expect(identical(updated, settings), isFalse);
      },
    );

    test(
      'given_useMonospaceFont_true_when_setUseMonospaceFont_true_then_returns_identical_this',
      () {
        final settings = AppSettings(useMonospaceFont: true);
        expect(identical(settings.setUseMonospaceFont(true), settings), isTrue);
      },
    );
  });
}
