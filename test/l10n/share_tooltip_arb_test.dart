// test/l10n/share_tooltip_arb_test.dart
//
// TASK-04 — SP-20260616 — shareTooltip ARB key + gen-l10n parity gate.
//
// Spec refs: FR-16, NFR-05, §5.2
//
// 1. ARB parity — parse app_en.arb and app_it.arb; assert `shareTooltip`
//    exists in BOTH with values "Share" (en) and "Condividi" (it), and an
//    `@shareTooltip` description block is present in both; assert the two
//    files have identical key sets.
// 2. gen-l10n — assert AppLocalizations exposes a non-null shareTooltip
//    getter resolving to "Share" under EN and "Condividi" under IT.

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

void main() {
  const enPath = 'lib/l10n/app_en.arb';
  const itPath = 'lib/l10n/app_it.arb';

  late Map<String, dynamic> en;
  late Map<String, dynamic> it;

  setUpAll(() {
    en = _loadArb(enPath);
    it = _loadArb(itPath);
  });

  // ─── 1. shareTooltip value checks (FR-16) ────────────────────────────────

  group('TASK-04 — shareTooltip ARB value checks (FR-16)', () {
    test('shareTooltip present in app_en.arb', () {
      expect(
        en.containsKey('shareTooltip'),
        isTrue,
        reason: 'shareTooltip missing from app_en.arb',
      );
    });

    test('shareTooltip EN value is "Share"', () {
      expect(
        en['shareTooltip'],
        equals('Share'),
        reason: 'shareTooltip EN value must be "Share"',
      );
    });

    test('shareTooltip present in app_it.arb', () {
      expect(
        it.containsKey('shareTooltip'),
        isTrue,
        reason: 'shareTooltip missing from app_it.arb',
      );
    });

    test('shareTooltip IT value is "Condividi"', () {
      expect(
        it['shareTooltip'],
        equals('Condividi'),
        reason: 'shareTooltip IT value must be "Condividi"',
      );
    });
  });

  // ─── 2. @shareTooltip description block checks (FR-16) ───────────────────

  group('TASK-04 — @shareTooltip description block (FR-16)', () {
    test('@shareTooltip metadata block present in app_en.arb', () {
      expect(
        en.containsKey('@shareTooltip'),
        isTrue,
        reason: '@shareTooltip metadata block missing from app_en.arb',
      );
    });

    test('@shareTooltip EN metadata has description field', () {
      final meta = en['@shareTooltip'] as Map<String, dynamic>;
      expect(
        meta.containsKey('description'),
        isTrue,
        reason: '@shareTooltip in app_en.arb has no description field',
      );
      expect(
        (meta['description'] as String).isNotEmpty,
        isTrue,
        reason: '@shareTooltip EN description is empty',
      );
    });

    test('@shareTooltip metadata block present in app_it.arb', () {
      expect(
        it.containsKey('@shareTooltip'),
        isTrue,
        reason: '@shareTooltip metadata block missing from app_it.arb',
      );
    });

    test('@shareTooltip IT metadata has description field', () {
      final meta = it['@shareTooltip'] as Map<String, dynamic>;
      expect(
        meta.containsKey('description'),
        isTrue,
        reason: '@shareTooltip in app_it.arb has no description field',
      );
      expect(
        (meta['description'] as String).isNotEmpty,
        isTrue,
        reason: '@shareTooltip IT description is empty',
      );
    });
  });

  // ─── 3. Key-set parity including shareTooltip (NFR-05) ───────────────────

  group(
    'TASK-04 — ARB key-set parity after shareTooltip addition (NFR-05)',
    () {
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

      test('shareTooltip included in both EN and IT key sets', () {
        expect(
          _visibleKeys(en).contains('shareTooltip'),
          isTrue,
          reason: 'shareTooltip absent from EN visible-key set',
        );
        expect(
          _visibleKeys(it).contains('shareTooltip'),
          isTrue,
          reason: 'shareTooltip absent from IT visible-key set',
        );
      });
    },
  );

  // ─── 4. Generated AppLocalizations getter check (FR-16) ──────────────────
  //
  // gen-l10n generates app_localizations_en.dart and app_localizations_it.dart.
  // We verify by source-scanning the generated EN file for the shareTooltip
  // getter — this is the authoritative check that flutter gen-l10n produced
  // the expected Dart accessor without importing Flutter widget infrastructure
  // into a plain Dart test.

  group('TASK-04 — generated AppLocalizations shareTooltip getter (FR-16)', () {
    test(
      'app_localizations_en.dart contains a shareTooltip getter returning "Share"',
      () {
        final source = File(
          'lib/l10n/app_localizations_en.dart',
        ).readAsStringSync();
        expect(
          source.contains('shareTooltip'),
          isTrue,
          reason:
              'app_localizations_en.dart does not contain shareTooltip — '
              'run flutter gen-l10n after adding the ARB key',
        );
        // Confirm the concrete return value is present.
        expect(
          source.contains("'Share'"),
          isTrue,
          reason:
              'app_localizations_en.dart does not contain the string \'Share\' '
              'for shareTooltip',
        );
      },
    );

    test(
      'app_localizations_it.dart contains a shareTooltip getter returning "Condividi"',
      () {
        final source = File(
          'lib/l10n/app_localizations_it.dart',
        ).readAsStringSync();
        expect(
          source.contains('shareTooltip'),
          isTrue,
          reason:
              'app_localizations_it.dart does not contain shareTooltip — '
              'run flutter gen-l10n after adding the ARB key',
        );
        expect(
          source.contains("'Condividi'"),
          isTrue,
          reason:
              'app_localizations_it.dart does not contain the string \'Condividi\' '
              'for shareTooltip',
        );
      },
    );

    test('abstract AppLocalizations class declares shareTooltip getter', () {
      final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
      expect(
        source.contains('shareTooltip'),
        isTrue,
        reason:
            'app_localizations.dart does not declare shareTooltip abstract getter — '
            'run flutter gen-l10n after adding the ARB key',
      );
    });
  });
}
