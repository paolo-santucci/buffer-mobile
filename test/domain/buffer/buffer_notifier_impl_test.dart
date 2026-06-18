// ignore_for_file: prefer_const_constructors
// Const constructors require the generated freezed code to exist; at the RED
// phase the generated part file may be absent, so const is intentionally deferred.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/buffer/buffer_state.dart';
import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/domain/buffer/buffer_notifier_impl.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ProviderContainer makeContainer() => ProviderContainer();

// ---------------------------------------------------------------------------
// Tests for BufferNotifierImpl — populate (FR-M2-09 / §5.1.3)
// ---------------------------------------------------------------------------

void main() {
  group('BufferNotifierImpl — populate', () {
    test(
      'given_empty_buffer_when_populate_called_with_hello_then_state_text_is_hello',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(bufferProvider.notifier).populate('hello');
        final state = container.read(bufferProvider);

        expect(state.text, equals('hello'));
      },
    );

    test(
      'given_empty_buffer_when_populate_called_with_empty_string_then_state_text_is_empty_and_no_throw',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        expect(
          () => container.read(bufferProvider.notifier).populate(''),
          returnsNormally,
        );
        expect(container.read(bufferProvider).text, equals(''));
      },
    );

    test(
      'given_buffer_populated_with_hello_when_reset_then_state_equals_BufferState_empty',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(bufferProvider.notifier).populate('hello');
        container.read(bufferProvider.notifier).reset();

        expect(container.read(bufferProvider), equals(BufferState.empty()));
      },
    );

    test(
      'given_buffer_with_existing_text_when_populate_called_then_text_is_replaced',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(bufferProvider.notifier).updateText('existing');
        container.read(bufferProvider.notifier).populate('replacement');

        expect(container.read(bufferProvider).text, equals('replacement'));
      },
    );

    test(
      'given_BufferNotifierImpl_when_inspected_then_it_is_a_BufferNotifierImpl',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(bufferProvider.notifier);

        expect(notifier, isA<BufferNotifierImpl>());
      },
    );
  });
}
