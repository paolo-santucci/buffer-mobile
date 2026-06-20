// test/l10n/sp20260620_keyboard_done_tooltip_test.dart
//
// ARB-parity gate for SP-20260620 TASK-03 (iOS keyboard accessory bar).
//
// Spec refs: FR-20, NFR-08
//
// Asserts:
//  - keyboardDoneTooltip key present with non-empty values in both EN and IT ARBs.
//  - Each key has a @key metadata block with a description.
//  - Full parity: EN and IT visible key sets remain identical (NFR-08).
//
// A compile-time reference to the generated accessor is placed in a dummy
// getter below — this file will not compile (and therefore the test suite will
// fail to load) if flutter gen-l10n has not been re-run after the key is added.

import 'dart:convert';
import 'dart:io';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Compile-time gate: the accessor must resolve to an actual getter on the
// generated AppLocalizations class.  If gen-l10n was not re-run after the key
// is added, this file fails to compile and the whole test suite reports a load
// error — which is the intended red signal.
//
// ignore: unused_element
String _compileKeyboardDoneTooltip(AppLocalizations l10n) =>
    l10n.keyboardDoneTooltip;

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
  late Set<String> enKeys;
  late Set<String> itKeys;

  setUpAll(() {
    en = _loadArb(enPath);
    it = _loadArb(itPath);
    enKeys = _visibleKeys(en);
    itKeys = _visibleKeys(it);
  });

  // ─── SP-20260620 TASK-03 keys ────────────────────────────────────────────

  const sp20Task03Keys = <String>['keyboardDoneTooltip'];

  group(
    'TASK-03 — SP-20260620 ARB keys present in app_en.arb (FR-20, NFR-08)',
    () {
      for (final key in sp20Task03Keys) {
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
    'TASK-03 — SP-20260620 ARB keys present in app_it.arb (FR-20, NFR-08)',
    () {
      for (final key in sp20Task03Keys) {
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

  group('TASK-03 — SP-20260620 EN/IT parity (NFR-08)', () {
    test('keyboardDoneTooltip present in both EN and IT', () {
      expect(
        enKeys.contains('keyboardDoneTooltip'),
        isTrue,
        reason: 'keyboardDoneTooltip missing from EN visible keys',
      );
      expect(
        itKeys.contains('keyboardDoneTooltip'),
        isTrue,
        reason: 'keyboardDoneTooltip missing from IT visible keys',
      );
    });

    test('EN and IT visible key sets remain identical (no drift)', () {
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
