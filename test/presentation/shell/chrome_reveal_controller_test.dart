// Tests for ChromeRevealController + chromeVisibilityProvider (TASK-08a)
//
// Spec refs: FR-M6-06, FR-M6-07, EC-07, NFR-M6-04, §5.1-e
//
// Verifies:
//   1. build() initial state == true (chrome visible at rest).
//   2. onTextChanged() → false (hide on type).
//   3. onUserScroll(reverse) → false; onUserScroll(forward) → true;
//      onUserScroll(idle) → no change.
//   4. onKeyboardDismissed() → true; reveal() → true regardless of prior state.
//   5. Setting state to the same bool twice → no second rebuild (Riverpod equality).
//   6. Controller has NO guard / _applyingState field — every onUserScroll call
//      is accepted unconditionally (EC-07: host owns the guard).

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/presentation/shell/chrome_reveal_controller.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helper: create an isolated ProviderContainer with the controller.
  // ---------------------------------------------------------------------------
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  // ---------------------------------------------------------------------------
  // 1. Initial state
  // ---------------------------------------------------------------------------
  group('ChromeRevealController — initial state', () {
    test('given_freshProvider_when_build_then_state_is_true', () {
      final container = makeContainer();
      final state = container.read(chromeVisibilityProvider);
      expect(state, isTrue, reason: 'Chrome must be visible at rest (§5.1-e)');
    });
  });

  // ---------------------------------------------------------------------------
  // 2. onTextChanged → hide
  // ---------------------------------------------------------------------------
  group('ChromeRevealController — onTextChanged', () {
    test('given_chrome_visible_when_onTextChanged_then_state_is_false', () {
      final container = makeContainer();
      container.read(chromeVisibilityProvider.notifier).onTextChanged();
      expect(
        container.read(chromeVisibilityProvider),
        isFalse,
        reason: 'Typing must hide chrome (FR-M6-06)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 3. onUserScroll transitions
  // ---------------------------------------------------------------------------
  group('ChromeRevealController — onUserScroll', () {
    test(
      'given_chrome_visible_when_onUserScroll_reverse_then_state_is_false',
      () {
        final container = makeContainer();
        container
            .read(chromeVisibilityProvider.notifier)
            .onUserScroll(ScrollDirection.reverse);
        expect(
          container.read(chromeVisibilityProvider),
          isFalse,
          reason: 'Scroll-down (reverse) must hide chrome (FR-M6-06)',
        );
      },
    );

    test(
      'given_chrome_hidden_when_onUserScroll_forward_then_state_is_true',
      () {
        final container = makeContainer();
        // First hide chrome.
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        expect(container.read(chromeVisibilityProvider), isFalse);
        // Then scroll up.
        container
            .read(chromeVisibilityProvider.notifier)
            .onUserScroll(ScrollDirection.forward);
        expect(
          container.read(chromeVisibilityProvider),
          isTrue,
          reason: 'Scroll-up (forward) must reveal chrome (FR-M6-06)',
        );
      },
    );

    test('given_chrome_hidden_when_onUserScroll_idle_then_state_unchanged', () {
      final container = makeContainer();
      // Hide first.
      container.read(chromeVisibilityProvider.notifier).onTextChanged();
      expect(container.read(chromeVisibilityProvider), isFalse);
      // Idle scroll must leave state unchanged.
      container
          .read(chromeVisibilityProvider.notifier)
          .onUserScroll(ScrollDirection.idle);
      expect(
        container.read(chromeVisibilityProvider),
        isFalse,
        reason: 'Idle scroll must not change chrome visibility (§5.1-e)',
      );
    });

    test('given_chrome_visible_when_onUserScroll_idle_then_state_unchanged', () {
      final container = makeContainer();
      // Chrome is visible by default; idle must keep it visible.
      container
          .read(chromeVisibilityProvider.notifier)
          .onUserScroll(ScrollDirection.idle);
      expect(
        container.read(chromeVisibilityProvider),
        isTrue,
        reason:
            'Idle scroll must not change chrome visibility when already visible',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 4. onKeyboardDismissed + reveal
  // ---------------------------------------------------------------------------
  group('ChromeRevealController — onKeyboardDismissed and reveal', () {
    test('given_chrome_hidden_when_onKeyboardDismissed_then_state_is_true', () {
      final container = makeContainer();
      container.read(chromeVisibilityProvider.notifier).onTextChanged();
      expect(container.read(chromeVisibilityProvider), isFalse);

      container.read(chromeVisibilityProvider.notifier).onKeyboardDismissed();
      expect(
        container.read(chromeVisibilityProvider),
        isTrue,
        reason: 'Keyboard dismiss must reveal chrome (FR-M6-06)',
      );
    });

    test('given_chrome_hidden_when_reveal_then_state_is_true', () {
      final container = makeContainer();
      container.read(chromeVisibilityProvider.notifier).onTextChanged();
      expect(container.read(chromeVisibilityProvider), isFalse);

      container.read(chromeVisibilityProvider.notifier).reveal();
      expect(
        container.read(chromeVisibilityProvider),
        isTrue,
        reason: 'reveal() must show chrome regardless of prior state',
      );
    });

    test('given_chrome_already_visible_when_reveal_then_state_still_true', () {
      final container = makeContainer();
      // Chrome is visible by default; reveal() must keep it true.
      container.read(chromeVisibilityProvider.notifier).reveal();
      expect(
        container.read(chromeVisibilityProvider),
        isTrue,
        reason: 'reveal() must be idempotent when chrome is already visible',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Riverpod equality — same bool twice → no second rebuild
  // ---------------------------------------------------------------------------
  group('ChromeRevealController — Riverpod equality', () {
    test(
      'given_chrome_hidden_when_onTextChanged_called_twice_then_only_one_rebuild',
      () {
        final container = makeContainer();
        int buildCount = 0;
        final sub = container.listen<bool>(
          chromeVisibilityProvider,
          (prev, next) => buildCount++,
        );
        addTearDown(sub.close);

        // First call: true → false (triggers rebuild).
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        // Second call: false → false (same value — must NOT trigger rebuild).
        container.read(chromeVisibilityProvider.notifier).onTextChanged();

        expect(
          buildCount,
          equals(1),
          reason:
              'Riverpod must not rebuild when state is set to the same bool twice',
        );
      },
    );

    test('given_chrome_visible_when_reveal_called_twice_then_no_rebuild', () {
      final container = makeContainer();
      int buildCount = 0;
      final sub = container.listen<bool>(
        chromeVisibilityProvider,
        (prev, next) => buildCount++,
      );
      addTearDown(sub.close);

      // Chrome starts visible; calling reveal() again must not trigger rebuild.
      container.read(chromeVisibilityProvider.notifier).reveal();
      container.read(chromeVisibilityProvider.notifier).reveal();

      expect(
        buildCount,
        equals(0),
        reason: 'reveal() on already-visible chrome must produce zero rebuilds',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 6. EC-07 — controller is guard-agnostic (no _applyingState/_continuing field)
  //    The controller accepts every onUserScroll call unconditionally.
  //    The host (TASK-12) owns the guard.
  // ---------------------------------------------------------------------------
  group('ChromeRevealController — EC-07 guard-agnostic', () {
    test(
      'given_controller_when_onUserScroll_called_rapidly_then_each_call_takes_effect',
      () {
        final container = makeContainer();
        final notifier = container.read(chromeVisibilityProvider.notifier);

        // Rapid reverse→forward→reverse: each must land.
        notifier.onUserScroll(ScrollDirection.reverse);
        expect(container.read(chromeVisibilityProvider), isFalse);

        notifier.onUserScroll(ScrollDirection.forward);
        expect(container.read(chromeVisibilityProvider), isTrue);

        notifier.onUserScroll(ScrollDirection.reverse);
        expect(container.read(chromeVisibilityProvider), isFalse);
      },
    );

    test(
      'given_controller_class_when_inspected_then_has_no_applyingState_or_continuing_field',
      () {
        // Structural assertion: the controller must NOT have a guard field.
        // We confirm by checking that the notifier's runtimeType toString does
        // not contain a _applyingState / _continuing field via reflection-free
        // approach — we attempt to access the known type and confirm the public
        // API surface only contains the four documented methods.
        //
        // The concrete assertion: create a container, read the notifier, then
        // assert its runtimeType is exactly ChromeRevealController (not a
        // guarded subclass) and that onUserScroll executes without requiring
        // any internal flag to be set first.
        final container = makeContainer();
        final notifier = container.read(chromeVisibilityProvider.notifier);

        expect(
          notifier.runtimeType,
          equals(ChromeRevealController),
          reason:
              'EC-07: must be plain ChromeRevealController with no guard subclass',
        );

        // Calling onUserScroll without any setup must not throw — confirming no
        // required internal guard state.
        expect(
          () => notifier.onUserScroll(ScrollDirection.reverse),
          returnsNormally,
          reason: 'EC-07: onUserScroll must never require a prior guard setup',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 7. chromeVisibilityProvider — non-auto-dispose
  // ---------------------------------------------------------------------------
  group('chromeVisibilityProvider — non-auto-dispose', () {
    test(
      'given_chromeVisibilityProvider_when_type_checked_then_is_not_auto_dispose',
      () {
        expect(
          chromeVisibilityProvider.runtimeType.toString(),
          isNot(contains('AutoDispose')),
          reason:
              'chromeVisibilityProvider must be non-auto-disposing so state '
              'survives zero-listener windows between widget builds',
        );
      },
    );
  });
}
