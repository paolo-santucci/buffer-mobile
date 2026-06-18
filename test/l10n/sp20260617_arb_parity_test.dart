// test/l10n/sp20260617_arb_parity_test.dart
//
// ARB-parity gate for SP-20260617 TASK-12 (Liquid Glass floating chrome).
//
// Spec refs: FR-26, NFR-09, OQ-19
//
// Asserts:
//  - All 7 new keys present with non-empty values in both EN and IT ARBs.
//  - Each new key has a @key metadata block with a description.
//  - copiedToast EN == "Copied"; IT == "Copiato".
//  - Full parity: EN and IT visible key sets remain identical (OQ-19).
//
// A compile-time reference to each generated accessor is placed in a dummy
// getter below — this file will not compile (and therefore the test suite will
// fail to load) if flutter gen-l10n has not been re-run after the keys are added.

import 'dart:convert';
import 'dart:io';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Compile-time gate: each accessor must resolve to an actual getter on the
// generated AppLocalizations class.  If gen-l10n was not re-run after the keys
// are added, this file fails to compile and the whole test suite reports a load
// error — which is the intended red signal.
//
// ignore: unused_element
String _compileCopyTooltip(AppLocalizations l10n) => l10n.copyTooltip;

// ignore: unused_element
String _compilePasteTooltip(AppLocalizations l10n) => l10n.pasteTooltip;

// ignore: unused_element
String _compileFindTooltip(AppLocalizations l10n) => l10n.findTooltip;

// ignore: unused_element
String _compileCopySemantics(AppLocalizations l10n) => l10n.copySemantics;

// ignore: unused_element
String _compilePasteSemantics(AppLocalizations l10n) => l10n.pasteSemantics;

// ignore: unused_element
String _compileFindSemantics(AppLocalizations l10n) => l10n.findSemantics;

// ignore: unused_element
String _compileCopiedToast(AppLocalizations l10n) => l10n.copiedToast;

// Dummy reference to BuildContext so the import of package:flutter/widgets.dart
// is not flagged as unused.
// ignore: unused_element
void _unusedContextRef(BuildContext _) {}

Map<String, dynamic> _loadArb(String path) =>
    json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;

Set<String> _visibleKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  const enPath = 'lib/l10n/app_en.arb';
  const itPath = 'lib/l10n/app_it.arb';

  late Map<String, dynamic> en;
  late Map<String, dynamic> it;

  setUpAll(() {
    en = _loadArb(enPath);
    it = _loadArb(itPath);
  });

  // ─── SP-20260617 TASK-12 keys ────────────────────────────────────────────

  const sp17Keys = <String>[
    'copyTooltip',
    'pasteTooltip',
    'findTooltip',
    'copySemantics',
    'pasteSemantics',
    'findSemantics',
    'copiedToast',
  ];

  group(
    'TASK-12 — SP-20260617 ARB keys present in app_en.arb (FR-26, NFR-09)',
    () {
      for (final key in sp17Keys) {
        test('$key: present with non-empty value', () {
          expect(
            en.containsKey(key),
            isTrue,
            reason: 'EN ARB missing key: $key',
          );
          final value = en[key] as String;
          expect(value, isNotEmpty, reason: '$key EN value is empty');
          expect(
            value,
            isNot(equals(key)),
            reason: '$key EN value equals raw key name',
          );
        });

        test('$key: has @key metadata block with description', () {
          final metaKey = '@$key';
          expect(
            en.containsKey(metaKey),
            isTrue,
            reason: 'EN ARB missing metadata block: $metaKey',
          );
          final meta = en[metaKey] as Map<String, dynamic>;
          expect(
            meta.containsKey('description'),
            isTrue,
            reason: '$metaKey has no description field',
          );
        });
      }
    },
  );

  group(
    'TASK-12 — SP-20260617 ARB keys present in app_it.arb (FR-26, NFR-09)',
    () {
      for (final key in sp17Keys) {
        test('$key: present with non-empty value', () {
          expect(
            it.containsKey(key),
            isTrue,
            reason: 'IT ARB missing key: $key',
          );
          final value = it[key] as String;
          expect(value, isNotEmpty, reason: '$key IT value is empty');
          expect(
            value,
            isNot(equals(key)),
            reason: '$key IT value equals raw key name',
          );
        });

        test('$key: has @key metadata block with description', () {
          final metaKey = '@$key';
          expect(
            it.containsKey(metaKey),
            isTrue,
            reason: 'IT ARB missing metadata block: $metaKey',
          );
          final meta = it[metaKey] as Map<String, dynamic>;
          expect(
            meta.containsKey('description'),
            isTrue,
            reason: '$metaKey has no description field',
          );
        });
      }
    },
  );

  group('TASK-12 — SP-20260617 exact value checks', () {
    test('copiedToast EN value == "Copied"', () {
      expect(
        en['copiedToast'],
        equals('Copied'),
        reason: 'copiedToast EN value must be exactly "Copied"',
      );
    });

    test('copiedToast IT value == "Copiato"', () {
      expect(
        it['copiedToast'],
        equals('Copiato'),
        reason: 'copiedToast IT value must be exactly "Copiato"',
      );
    });
  });

  group('TASK-12 — SP-20260617 EN/IT key-set parity (OQ-19, NFR-09)', () {
    test('all 7 new keys present in both EN and IT', () {
      final enKeys = _visibleKeys(en);
      final itKeys = _visibleKeys(it);
      for (final key in sp17Keys) {
        expect(
          enKeys.contains(key),
          isTrue,
          reason: '$key missing from EN visible keys',
        );
        expect(
          itKeys.contains(key),
          isTrue,
          reason: '$key missing from IT visible keys',
        );
      }
    });

    test('EN and IT visible key sets are identical (no drift)', () {
      final enKeys = _visibleKeys(en);
      final itKeys = _visibleKeys(it);
      final missingInIt = enKeys.difference(itKeys);
      final extraInIt = itKeys.difference(enKeys);
      expect(
        missingInIt,
        isEmpty,
        reason: 'IT ARB missing keys that exist in EN: $missingInIt',
      );
      expect(
        extraInIt,
        isEmpty,
        reason: 'IT ARB has extra keys not in EN: $extraInIt',
      );
    });
  });
}
