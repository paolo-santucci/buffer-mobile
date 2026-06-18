// Tests for ToastController + toastProvider.
//
// Timer assertions use fake_async (transitive via flutter_test/test).
// All test names follow the given_when_then convention.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/presentation/shell/toast_controller.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helper: build a ProviderContainer with an overrideable clock seam.
  // ---------------------------------------------------------------------------
  ProviderContainer makeContainer() => ProviderContainer();

  // ---------------------------------------------------------------------------
  // 1. show('hello'): state == ToastMessage('hello'); after duration → null.
  // ---------------------------------------------------------------------------
  test('given_noState_when_showHello_then_stateIsToastMessageHello', () {
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(toastProvider.notifier);

      notifier.show('hello');
      expect(
        container.read(toastProvider),
        equals(const ToastMessage('hello')),
      );

      // Advance past the default 3-second duration.
      async.elapse(const Duration(seconds: 3));
      expect(container.read(toastProvider), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. show('A') then show('B') before A fires (EC-05).
  //    A timer cancelled; state ToastMessage('B'); after B duration → null;
  //    exactly one auto-dismiss; no dangling timer.
  // ---------------------------------------------------------------------------
  test('given_showA_when_showBBeforeAFires_then_onlyBStateAndSingleDismiss', () {
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(toastProvider.notifier);

      notifier.show('A', duration: const Duration(seconds: 3));
      expect(container.read(toastProvider), equals(const ToastMessage('A')));

      // Advance 1 second (A has not fired yet).
      async.elapse(const Duration(seconds: 1));
      expect(container.read(toastProvider), equals(const ToastMessage('A')));

      // Show B — this cancels A's timer.
      notifier.show('B', duration: const Duration(seconds: 3));
      expect(container.read(toastProvider), equals(const ToastMessage('B')));

      // Advance to where A would have fired (total 3s), then B's 3s starts
      // from the moment show('B') was called. The A-timer must NOT fire.
      async.elapse(const Duration(seconds: 2));
      // At t=3s from start — A timer position; B still alive (only 2s into B).
      expect(container.read(toastProvider), equals(const ToastMessage('B')));

      // Advance 1 more second — B is at 3s from its start; it auto-dismisses.
      async.elapse(const Duration(seconds: 1));
      expect(container.read(toastProvider), isNull);

      // Advance further to confirm no second auto-dismiss or dangling timer.
      async.elapse(const Duration(seconds: 5));
      expect(container.read(toastProvider), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. dismiss(): immediate null + timer cancelled.
  // ---------------------------------------------------------------------------
  test('given_showHello_when_dismiss_then_stateIsNullAndTimerCancelled', () {
    fakeAsync((async) {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(toastProvider.notifier);

      notifier.show('hello', duration: const Duration(seconds: 3));
      expect(
        container.read(toastProvider),
        equals(const ToastMessage('hello')),
      );

      // Dismiss immediately.
      notifier.dismiss();
      expect(container.read(toastProvider), isNull);

      // Advance past the original duration — should remain null; no second
      // auto-dismiss should fire.
      async.elapse(const Duration(seconds: 5));
      expect(container.read(toastProvider), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Dispose mid-countdown: pending timer cancelled; no state mutation after
  //    dispose (no StateNotifierError / assertion failure).
  // ---------------------------------------------------------------------------
  test(
    'given_showHelloMidCountdown_when_containerDisposed_then_noPendingTimerFires',
    () {
      fakeAsync((async) {
        final container = makeContainer();

        final notifier = container.read(toastProvider.notifier);
        notifier.show('hello', duration: const Duration(seconds: 3));
        expect(
          container.read(toastProvider),
          equals(const ToastMessage('hello')),
        );

        // Dispose the container at 1s (timer has not fired).
        async.elapse(const Duration(seconds: 1));
        container.dispose(); // triggers ref.onDispose → _timer?.cancel()

        // Advance past the original expiry — the timer must NOT fire; no
        // exception thrown.
        expect(() => async.elapse(const Duration(seconds: 5)), returnsNormally);
      });
    },
  );

  // ---------------------------------------------------------------------------
  // 5. toastProvider is non-auto-disposing (the M7 seam must survive zero
  //    listeners without being destroyed).
  // ---------------------------------------------------------------------------
  test('given_toastProvider_when_checkAutoDispose_then_isNotAutoDispose', () {
    expect(
      toastProvider.runtimeType.toString().contains('AutoDispose'),
      isFalse,
    );
  });
}
