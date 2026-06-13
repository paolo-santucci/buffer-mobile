// ignore_for_file: prefer_const_constructors
// Const constructors require the generated freezed code to exist; at the RED
// phase the generated part file is absent, so const is intentionally deferred.

import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BufferState value equality', () {
    test(
      'given_two_instances_with_identical_fields_when_compared_then_equal_and_hashcodes_match',
      () {
        final a = BufferState(text: 'a', isDirty: true);
        final b = BufferState(text: 'a', isDirty: true);

        expect(a == b, isTrue);
        expect(a.hashCode, equals(b.hashCode));
      },
    );

    test(
      'given_two_instances_with_same_text_but_different_isDirty_when_compared_then_not_equal',
      () {
        final dirty = BufferState(text: 'hello', isDirty: true);
        final clean = BufferState(text: 'hello', isDirty: false);

        expect(dirty == clean, isFalse);
      },
    );
  });

  group('BufferState immutability', () {
    test(
      'given_instance_with_isDirty_true_when_copyWith_isDirty_false_then_result_has_updated_field_and_original_unchanged',
      () {
        final original = BufferState(text: 'hello', isDirty: true);

        final updated = original.copyWith(isDirty: false);

        expect(updated.text, equals('hello'));
        expect(updated.isDirty, isFalse);
        // original must not mutate
        expect(original.isDirty, isTrue);
      },
    );
  });

  group('BufferState.empty factory', () {
    test(
      'given_no_arguments_when_calling_empty_then_returns_instance_equal_to_BufferState_with_blank_text_and_clean',
      () {
        final empty = BufferState.empty();

        expect(empty, equals(BufferState(text: '', isDirty: false)));
      },
    );
  });
}
