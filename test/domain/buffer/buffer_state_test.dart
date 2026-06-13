// ignore_for_file: prefer_const_constructors
// Const constructors require the generated freezed code to exist; at the RED
// phase the generated part file is absent, so const is intentionally deferred.

import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BufferState shape', () {
    test(
      'given_BufferState_when_constructed_then_only_text_field_is_present',
      () {
        // Compile-time proof: BufferState(text: ...) compiles without isDirty.
        // If isDirty were still on the class, nothing here would fail — but the
        // forbidden-field test below uses dart:mirrors-free introspection via
        // the toString() output, which freezed renders faithfully.
        final state = BufferState(text: 'hello');
        expect(state.text, equals('hello'));
        // toString() from freezed includes all fields; assert isDirty is absent.
        expect(
          state.toString(),
          isNot(contains('isDirty')),
          reason: 'isDirty must not exist on BufferState (assessment I-3)',
        );
      },
    );

    test(
      'given_BufferState_empty_when_inspected_then_toString_does_not_contain_isDirty',
      () {
        final empty = BufferState.empty();
        expect(
          empty.toString(),
          isNot(contains('isDirty')),
          reason: 'isDirty must not exist on BufferState (assessment I-3)',
        );
      },
    );
  });

  group('BufferState value equality', () {
    test(
      'given_two_instances_with_identical_text_when_compared_then_equal_and_hashcodes_match',
      () {
        final a = BufferState(text: 'a');
        final b = BufferState(text: 'a');

        expect(a == b, isTrue);
        expect(a.hashCode, equals(b.hashCode));
      },
    );

    test(
      'given_two_instances_with_different_text_when_compared_then_not_equal',
      () {
        final hello = BufferState(text: 'hello');
        final world = BufferState(text: 'world');

        expect(hello == world, isFalse);
      },
    );
  });

  group('BufferState immutability', () {
    test(
      'given_instance_with_text_hello_when_copyWith_different_text_then_result_has_updated_text_and_original_unchanged',
      () {
        final original = BufferState(text: 'hello');

        final updated = original.copyWith(text: 'world');

        expect(updated.text, equals('world'));
        // original must not mutate
        expect(original.text, equals('hello'));
      },
    );
  });

  group('BufferState.empty factory', () {
    test(
      'given_no_arguments_when_calling_empty_then_returns_instance_equal_to_BufferState_with_blank_text',
      () {
        final empty = BufferState.empty();

        expect(empty, equals(BufferState(text: '')));
      },
    );
  });
}
