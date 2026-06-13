// ignore_for_file: prefer_const_constructors
//
// The ignore above is required at RED phase: const constructors on @freezed classes
// require the generated `.freezed.dart` part file, which does not yet exist.
// Without the ignore the analyzer emits a misleading error that masks the expected
// "class not found" compile failure.
//
// Assumed const-scale accessor: TypographySettings.slotList
// The implementer MUST expose it as:
//   static const List<int> slotList = [6,7,8,9,10,11,12,13,14,15,16,17,18,20,22,24,26,28,30,34,38];
//
// These tests will NOT compile until the implementation and freezed codegen exist.
// That is the expected RED state — the orchestrator owns codegen and the
// consolidated Wave-1 test pass (see plan deviation note, §6, 2026-06-13).

import 'package:buffer/domain/typography/typography_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TypographySettings', () {
    // FR-14 / EC-01
    test(
      'given_no_args_when_constructed_then_fontSizeIndex_is_8_and_useMonospaceFont_is_true',
      () {
        const settings = TypographySettings();

        expect(settings.fontSizeIndex, equals(8));
        expect(settings.useMonospaceFont, isTrue);
      },
    );

    // §5.2 invariant — const slot scale
    test(
      'given_slotList_when_inspected_then_length_is_21_and_index_8_equals_14',
      () {
        expect(TypographySettings.slotList.length, equals(21));
        expect(TypographySettings.slotList[8], equals(14));
      },
    );

    // immutability via copyWith
    test(
      'given_default_settings_when_copyWith_fontSizeIndex_14_then_fontSizeIndex_is_14_and_useMonospaceFont_unchanged',
      () {
        const original = TypographySettings();
        final updated = original.copyWith(fontSizeIndex: 14);

        expect(updated.fontSizeIndex, equals(14));
        expect(updated.useMonospaceFont, isTrue);
      },
    );
  });
}
