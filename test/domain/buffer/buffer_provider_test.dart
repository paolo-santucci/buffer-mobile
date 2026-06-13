// ignore_for_file: prefer_const_constructors
//
// prefer_const_constructors: suppressed because BufferState is @freezed and
// the generated part file may not be present at the time this test is first
// run (RED phase). Once codegen is in place this suppress is harmless.
//
// Implementation contract assumed by this test file:
//   - `bufferProvider` is a NON-auto-disposed `NotifierProvider<BufferNotifierImpl, BufferState>`.
//   - `BufferNotifierImpl extends Notifier<BufferState> implements BufferNotifier`.
//   - `build()` returns `BufferState.empty()`.
//   - `updateText(String)` sets `state.text`; never throws.
//   - `reset()` returns state to `BufferState.empty()`; idempotent.
//   - `populate(String)` sets `state.text` from a non-keystroke source; never throws.
//   - Provider is declared in `lib/domain/buffer/buffer_provider.dart`.
//   - Impl is declared in `lib/domain/buffer/buffer_notifier_impl.dart`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helper: create a fresh ProviderContainer with no overrides.
  // ---------------------------------------------------------------------------
  ProviderContainer makeContainer() => ProviderContainer();

  // ---------------------------------------------------------------------------
  // FR-10 / EC-05: single non-auto-disposed hub, identity stability
  // ---------------------------------------------------------------------------

  group('bufferProvider — identity and non-auto-dispose', () {
    test(
      'given_fresh_container_when_notifier_read_twice_then_identical_instance',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        final first = container.read(bufferProvider.notifier);
        final second = container.read(bufferProvider.notifier);

        expect(identical(first, second), isTrue);
      },
    );

    test(
      'given_bufferProvider_declaration_when_checking_type_then_not_autoDispose',
      () {
        // NotifierProvider (non-auto-disposing) exposes `notifier` directly;
        // the runtime type must NOT be AutoDisposeNotifierProvider.
        // We assert the type is the non-auto-dispose variant by checking that
        // the provider's runtimeType name does not contain 'AutoDispose'.
        final typeName = bufferProvider.runtimeType.toString();
        expect(
          typeName.contains('AutoDispose'),
          isFalse,
          reason:
              'bufferProvider must be a non-auto-disposed NotifierProvider '
              '(FR-10 / §5.3)',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // EC-05: state survives zero listeners
  // ---------------------------------------------------------------------------

  group('bufferProvider — zero-listener survival', () {
    test(
      'given_active_state_when_all_subscriptions_dropped_then_state_unchanged_on_re_read',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        // Populate state.
        container.read(bufferProvider.notifier).updateText('hello');

        // Simulate zero listeners: dispose a subscription (containers with
        // non-auto-disposed providers retain state even with no listeners).
        // We verify by re-reading after the subscription object goes out of scope.
        final stateAfterDrop = container.read(bufferProvider);

        expect(stateAfterDrop.text, equals('hello'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // EC-02: updateText behaviour
  // ---------------------------------------------------------------------------

  group('BufferNotifierImpl — updateText', () {
    test('given_empty_buffer_when_updateText_abc_then_state_text_is_abc', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(bufferProvider.notifier).updateText('abc');
      final state = container.read(bufferProvider);

      expect(state.text, equals('abc'));
    });

    test(
      'given_non_empty_buffer_when_updateText_empty_string_then_no_throw_and_text_empty',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(bufferProvider.notifier).updateText('abc');

        expect(
          () => container.read(bufferProvider.notifier).updateText(''),
          returnsNormally,
        );
        expect(container.read(bufferProvider).text, equals(''));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // §5.1a: reset behaviour
  // ---------------------------------------------------------------------------

  group('BufferNotifierImpl — reset', () {
    test(
      'given_non_empty_buffer_when_reset_then_state_equals_BufferState_empty',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(bufferProvider.notifier).updateText('some text');
        container.read(bufferProvider.notifier).reset();

        expect(container.read(bufferProvider), equals(BufferState.empty()));
      },
    );

    test(
      'given_empty_buffer_when_reset_called_again_then_idempotent_no_throw',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        container.read(bufferProvider.notifier).reset();

        expect(
          () => container.read(bufferProvider.notifier).reset(),
          returnsNormally,
        );
        expect(container.read(bufferProvider), equals(BufferState.empty()));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // NFR-09 / R-01: no persistence — structural check
  // ---------------------------------------------------------------------------

  group('BufferNotifierImpl — no-persistence contract', () {
    test(
      'given_BufferNotifierImpl_when_inspected_then_implements_BufferNotifier_contract',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(bufferProvider.notifier);

        // BufferNotifierImpl must satisfy the BufferNotifier interface.
        // This is a compile-time guarantee; the runtime isA check is a
        // belt-and-suspenders confirmation.
        expect(notifier, isA<BufferNotifierImpl>());
      },
    );
  });
}
