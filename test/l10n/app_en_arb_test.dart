import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> arb;

  setUpAll(() {
    final file = File('lib/l10n/app_en.arb');
    arb = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  // Keys defined in §5.4 of the M6 spec.
  const m6Keys = [
    'themeFollowSystem',
    'themeLight',
    'themeDark',
    'themeSelectorLabel',
    'menuTooltip',
    'menuPreferences',
    'menuAbout',
    'menuRecovery',
    'settingsTitle',
    'settingsAppearance',
    'settingsBehavior',
    'settingsThemeMode',
    'settingsRecoveryEnabled',
    'settingsSpellCheck',
    'aboutTitle',
    'aboutDeveloper',
    'aboutVersion',
    'aboutLicense',
    'aboutIssues',
    'aboutWebsite',
    'fontSizeToast',
    'editorIndentLabel',
    'editorOutdentLabel',
  ];

  group('TASK-05 — §5.4 M6 ARB keys present in app_en.arb', () {
    test('all 23 §5.4 keys are present', () {
      for (final key in m6Keys) {
        expect(arb.containsKey(key), isTrue, reason: 'Missing key: $key');
      }
    });

    test('all 23 §5.4 keys have non-empty string values', () {
      for (final key in m6Keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$key value is not a String');
        expect(
          (value as String).isNotEmpty,
          isTrue,
          reason: '$key value is empty',
        );
      }
    });

    test('all 23 §5.4 keys have @key metadata blocks', () {
      for (final key in m6Keys) {
        final metaKey = '@$key';
        expect(
          arb.containsKey(metaKey),
          isTrue,
          reason: 'Missing metadata block: $metaKey',
        );
        final meta = arb[metaKey] as Map<String, dynamic>;
        expect(
          meta.containsKey('description'),
          isTrue,
          reason: '$metaKey has no description field',
        );
      }
    });

    test('fontSizeToast value contains {n} ICU placeholder', () {
      final value = arb['fontSizeToast'] as String;
      expect(
        value.contains('{n}'),
        isTrue,
        reason: 'fontSizeToast value "$value" does not contain {n}',
      );
    });

    test('@fontSizeToast metadata declares placeholders.n', () {
      final meta = arb['@fontSizeToast'] as Map<String, dynamic>;
      expect(
        meta.containsKey('placeholders'),
        isTrue,
        reason: '@fontSizeToast has no placeholders block',
      );
      final placeholders = meta['placeholders'] as Map<String, dynamic>;
      expect(
        placeholders.containsKey('n'),
        isTrue,
        reason: '@fontSizeToast placeholders block has no "n" entry',
      );
    });

    test('fontSizeToast placeholder n has a type field', () {
      final meta = arb['@fontSizeToast'] as Map<String, dynamic>;
      final placeholders = meta['placeholders'] as Map<String, dynamic>;
      final n = placeholders['n'] as Map<String, dynamic>;
      expect(
        n.containsKey('type'),
        isTrue,
        reason: '@fontSizeToast.placeholders.n has no type field',
      );
    });

    test('editorIndentLabel is non-empty and is not the raw key name', () {
      final value = arb['editorIndentLabel'] as String;
      expect(value.isNotEmpty, isTrue);
      expect(value, isNot(equals('editorIndentLabel')));
    });

    test('editorOutdentLabel is non-empty and is not the raw key name', () {
      final value = arb['editorOutdentLabel'] as String;
      expect(value.isNotEmpty, isTrue);
      expect(value, isNot(equals('editorOutdentLabel')));
    });

    test('aboutLicense value contains GPL-3.0', () {
      final value = arb['aboutLicense'] as String;
      // Accept 'GPL-3.0' directly or 'GPL' and '3.0' both present
      final containsGpl30 = value.contains('GPL-3.0');
      final containsGplAnd30 = value.contains('GPL') && value.contains('3.0');
      expect(
        containsGpl30 || containsGplAnd30,
        isTrue,
        reason: 'aboutLicense "$value" does not reference GPL-3.0',
      );
    });

    test('existing pre-M6 keys are still present (regression guard)', () {
      final existingKeys = [
        'appTitle',
        'findHintText',
        'findCountLabel',
        'recoveryTitle',
        'recoveryEmpty',
        'recoveryToggleLabel',
      ];
      for (final key in existingKeys) {
        expect(
          arb.containsKey(key),
          isTrue,
          reason: 'Regression: $key removed',
        );
      }
    });
  });

  // ─── M7 TASK-04 additions ────────────────────────────────────────────────

  const m7Keys = [
    'settingsFontSize',
    'settingsMonospaceFont',
    'a11yZoomIn',
    'a11yZoomOut',
  ];

  group('TASK-04 — §FR-M7-12 M7 ARB keys present in app_en.arb', () {
    test('all 4 M7 keys are present', () {
      for (final key in m7Keys) {
        expect(arb.containsKey(key), isTrue, reason: 'Missing key: $key');
      }
    });

    test('all 4 M7 keys have non-empty string values', () {
      for (final key in m7Keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$key value is not a String');
        expect(
          (value as String).isNotEmpty,
          isTrue,
          reason: '$key value is empty',
        );
      }
    });

    test('all 4 M7 keys have @key metadata blocks with description', () {
      for (final key in m7Keys) {
        final metaKey = '@$key';
        expect(
          arb.containsKey(metaKey),
          isTrue,
          reason: 'Missing metadata block: $metaKey',
        );
        final meta = arb[metaKey] as Map<String, dynamic>;
        expect(
          meta.containsKey('description'),
          isTrue,
          reason: '$metaKey has no description field',
        );
      }
    });

    test(
      'fontSizeToast appears exactly once as a value entry (not re-declared by M7)',
      () {
        // Guard against re-declaration: the non-@ value entry "fontSizeToast": "..."
        // must appear exactly once in the source. The @fontSizeToast meta entry has
        // a leading @, so the pattern /"fontSizeToast"\s*:/ (without @) catches only
        // the value declaration.
        final source = File('lib/l10n/app_en.arb').readAsStringSync();
        // Match "fontSizeToast" NOT preceded by @
        final occurrences = RegExp(
          r'(?<!@)"fontSizeToast"\s*:',
        ).allMatches(source).length;
        expect(
          occurrences,
          equals(1),
          reason:
              'fontSizeToast value entry appears $occurrences times in app_en.arb; '
              'expected exactly 1. If > 1, the key has been re-declared.',
        );
      },
    );
  });
}
