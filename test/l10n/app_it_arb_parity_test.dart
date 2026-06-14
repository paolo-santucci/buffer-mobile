// test/l10n/app_it_arb_parity_test.dart
//
// Parity tests for app_it.arb vs app_en.arb.
//
// NFR-M6-02: The Italian ARB key set must be EXACTLY equal to the English
// ARB key set (set difference empty both directions).
//
// EC-06: Each of the 23 M6 keys must have a non-empty IT value that is
// distinct from the raw key name; fontSizeToast must contain '{n}'.
// aboutWebsite / aboutIssues IT values must be labels (non-URL strings).
//
// Spec refs: FR-M6-17, NFR-M6-02, EC-06, §5.4

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadArb(String path) {
  final file = File(path);
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Returns only the user-visible keys (no @@locale, no @meta-keys).
Set<String> _visibleKeys(Map<String, dynamic> arb) {
  return arb.keys.where((k) => !k.startsWith('@')).toSet();
}

/// Returns the @meta sibling keys (e.g. '@appTitle').
Set<String> _metaKeys(Map<String, dynamic> arb) {
  return arb.keys.where((k) => k.startsWith('@') && k != '@@locale').toSet();
}

void main() {
  const enPath = 'lib/l10n/app_en.arb';
  const itPath = 'lib/l10n/app_it.arb';

  late Map<String, dynamic> en;
  late Map<String, dynamic> it;

  setUpAll(() {
    en = _loadArb(enPath);
    it = _loadArb(itPath);
  });

  // ─── 1. Full key-set parity ───────────────────────────────────────────────

  group('key-set parity (NFR-M6-02)', () {
    test('every EN visible key exists in IT', () {
      final enKeys = _visibleKeys(en);
      final itKeys = _visibleKeys(it);
      final missing = enKeys.difference(itKeys);
      expect(
        missing,
        isEmpty,
        reason: 'IT ARB is missing keys present in EN: $missing',
      );
    });

    test('IT has no extra visible keys not in EN', () {
      final enKeys = _visibleKeys(en);
      final itKeys = _visibleKeys(it);
      final extra = itKeys.difference(enKeys);
      expect(
        extra,
        isEmpty,
        reason: 'IT ARB contains extra keys not in EN: $extra',
      );
    });

    test('every EN @meta key has a matching @meta key in IT', () {
      final enMeta = _metaKeys(en);
      final itMeta = _metaKeys(it);
      final missing = enMeta.difference(itMeta);
      expect(
        missing,
        isEmpty,
        reason: 'IT ARB is missing @meta entries: $missing',
      );
    });
  });

  // ─── 2. M6 §5.4 key-level checks (EC-06) ─────────────────────────────────

  const m6Keys = <String>[
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

  group('M6 §5.4 keys present and non-trivial (EC-06)', () {
    for (final key in m6Keys) {
      test(
        '$key: present in IT with non-empty value distinct from key name',
        () {
          expect(
            it.containsKey(key),
            isTrue,
            reason: '$key missing from app_it.arb',
          );
          final value = it[key] as String;
          expect(value, isNotEmpty, reason: '$key has empty IT value');
          expect(
            value,
            isNot(equals(key)),
            reason: '$key IT value equals the raw key name — not translated',
          );
        },
      );
    }

    test('fontSizeToast IT value contains the {n} placeholder', () {
      final value = it['fontSizeToast'] as String;
      expect(
        value.contains('{n}'),
        isTrue,
        reason:
            'fontSizeToast IT value must contain "{n}" placeholder; got: "$value"',
      );
    });

    test(
      'aboutLicense IT value is "GPL-3.0" (license identifier, never translated)',
      () {
        expect(it['aboutLicense'], equals('GPL-3.0'));
      },
    );

    test('aboutIssues IT value is a label, not a URL', () {
      final value = it['aboutIssues'] as String;
      expect(
        value.startsWith('http'),
        isFalse,
        reason: 'aboutIssues should be a label text, not a URL; got: "$value"',
      );
    });

    test('aboutWebsite IT value is a label, not a URL', () {
      final value = it['aboutWebsite'] as String;
      expect(
        value.startsWith('http'),
        isFalse,
        reason: 'aboutWebsite should be a label text, not a URL; got: "$value"',
      );
    });

    test(
      'aboutDeveloper IT value matches EN (proper name, not translated)',
      () {
        expect(it['aboutDeveloper'], equals(en['aboutDeveloper']));
      },
    );
  });

  // ─── 3. M7 TASK-04 additions ─────────────────────────────────────────────

  const m7Keys = <String>[
    'settingsFontSize',
    'settingsMonospaceFont',
    'a11yZoomIn',
    'a11yZoomOut',
  ];

  group('TASK-04 — §FR-M7-12 M7 ARB keys present and non-trivial (EN+IT)', () {
    for (final key in m7Keys) {
      test('$key: present in EN with non-empty value', () {
        expect(
          en.containsKey(key),
          isTrue,
          reason: '$key missing from app_en.arb',
        );
        final value = en[key] as String;
        expect(value, isNotEmpty, reason: '$key has empty EN value');
        expect(
          value,
          isNot(equals(key)),
          reason: '$key EN value equals raw key name',
        );
      });

      test('$key: present in IT with non-empty value', () {
        expect(
          it.containsKey(key),
          isTrue,
          reason: '$key missing from app_it.arb',
        );
        final value = it[key] as String;
        expect(value, isNotEmpty, reason: '$key has empty IT value');
        expect(
          value,
          isNot(equals(key)),
          reason: '$key IT value equals raw key name',
        );
      });
    }

    test(
      'fontSizeToast value entry appears exactly once in app_en.arb (not re-declared by M7)',
      () {
        final source = File('lib/l10n/app_en.arb').readAsStringSync();
        final count = RegExp(
          r'(?<!@)"fontSizeToast"\s*:',
        ).allMatches(source).length;
        expect(
          count,
          equals(1),
          reason:
              'fontSizeToast value entry appears $count times in app_en.arb; expected exactly 1',
        );
      },
    );

    test(
      'fontSizeToast value entry appears exactly once in app_it.arb (not re-declared by M7)',
      () {
        final source = File('lib/l10n/app_it.arb').readAsStringSync();
        final count = RegExp(
          r'(?<!@)"fontSizeToast"\s*:',
        ).allMatches(source).length;
        expect(
          count,
          equals(1),
          reason:
              'fontSizeToast value entry appears $count times in app_it.arb; expected exactly 1',
        );
      },
    );

    test('EN/IT key-sets include all M7 keys (parity gate extension)', () {
      final enKeys = _visibleKeys(en);
      final itKeys = _visibleKeys(it);
      for (final key in m7Keys) {
        expect(
          enKeys.contains(key),
          isTrue,
          reason: '$key missing from EN key set',
        );
        expect(
          itKeys.contains(key),
          isTrue,
          reason: '$key missing from IT key set',
        );
      }
    });
  });
}
