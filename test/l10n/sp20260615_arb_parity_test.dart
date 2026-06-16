// test/l10n/sp20260615_arb_parity_test.dart
//
// ARB-parity gate for SP-20260615 TASK-01.
//
// Spec refs: FR-17, NFR-07
//
// Asserts:
//  - "menuFind" present with non-empty value in both EN and IT ARBs.
//  - "menuFind" has a @key metadata block with a description.
//  - Full parity: EN and IT visible key sets are identical (extending the
//    NFR-M6-02 / NFR-07 discipline already established in
//    app_it_arb_parity_test.dart).
//
// A compile-time reference to AppLocalizations.menuFind is placed in a dummy
// getter below — this file will not compile (and therefore the test suite will
// fail to load) if flutter gen-l10n has not been re-run after the key is added.

import 'dart:convert';
import 'dart:io';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Compile-time gate: this accessor must resolve to an actual getter on the
// generated AppLocalizations class.  If gen-l10n was not re-run the file fails
// to compile and the whole test suite reports a load error — which is the
// intended red signal.
//
// The getter is never executed at runtime (the widget tree is not pumped);
// it exists solely to make the Dart analyser / compiler verify the symbol.
// ignore: unused_element
String _compileTimeMenuFind(AppLocalizations l10n) => l10n.menuFind;

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

  // ─── SP-20260615 TASK-01 keys ────────────────────────────────────────────

  const spKeys = <String>['menuFind'];

  group(
    'TASK-01 — SP-20260615 ARB keys present in app_en.arb (FR-17, FR-18)',
    () {
      for (final key in spKeys) {
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
    'TASK-01 — SP-20260615 ARB keys present in app_it.arb (FR-17, FR-18)',
    () {
      for (final key in spKeys) {
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

  group('TASK-01 — SP-20260615 EN/IT key-set parity (NFR-07)', () {
    test('menuFind present in both EN and IT', () {
      expect(
        _visibleKeys(en).contains('menuFind'),
        isTrue,
        reason: 'menuFind missing from EN visible keys',
      );
      expect(
        _visibleKeys(it).contains('menuFind'),
        isTrue,
        reason: 'menuFind missing from IT visible keys',
      );
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
