// TASK-07: share_providers.dart — Riverpod provider composition seam.
// Spec refs: FR-M2-15 (seam), §5.1.4
//
// TDD contract:
//   1. initialSharedTextProvider throws UnimplementedError without an override.
//   2. initialSharedTextProvider returns "x" when overridden with "x".
//   3. saveBufferToRecoveryProvider resolves to a SaveBufferToRecovery whose
//      internal _repository is the value from recoveryRepositoryProvider
//      (type-check the resolved graph).
//   4. shareIntentServiceProvider resolves to a ShareIntentService (overridable
//      with a fake in tests).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/presentation/editor/share_providers.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Minimal [ShareIntentService] fake for override-friendliness test.
class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

/// Minimal [RecoveryRepository] fake for graph-wiring assertion.
class _FakeRecoveryRepository implements RecoveryRepository {
  bool saveCalled = false;

  @override
  Future<File> save(String text) async {
    saveCalled = true;
    // Return a non-existent sentinel File — the test only checks saveCalled.
    return File('/tmp/sentinel.txt');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('initialSharedTextProvider', () {
    test('throws UnimplementedError when read without an override', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(initialSharedTextProvider),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('returns the overridden value when overridden with a String', () {
      final container = ProviderContainer(
        overrides: [initialSharedTextProvider.overrideWithValue('x')],
      );
      addTearDown(container.dispose);

      expect(container.read(initialSharedTextProvider), equals('x'));
    });

    test('returns null when overridden with null', () {
      final container = ProviderContainer(
        overrides: [initialSharedTextProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      expect(container.read(initialSharedTextProvider), isNull);
    });
  });

  group('shareIntentServiceProvider', () {
    test('resolves to a ShareIntentService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(shareIntentServiceProvider),
        isA<ShareIntentService>(),
      );
    });

    test('can be overridden with a fake in tests', () {
      final fake = _FakeShareIntentService();
      final container = ProviderContainer(
        overrides: [shareIntentServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(shareIntentServiceProvider), same(fake));
    });
  });

  group('recoveryRepositoryProvider', () {
    test('resolves to a RecoveryRepository', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(recoveryRepositoryProvider),
        isA<RecoveryRepository>(),
      );
    });
  });

  group('saveBufferToRecoveryProvider', () {
    test('resolves to a SaveBufferToRecovery', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(saveBufferToRecoveryProvider),
        isA<SaveBufferToRecovery>(),
      );
    });

    test(
      'wired SaveBufferToRecovery routes through recoveryRepositoryProvider',
      () async {
        // Override recoveryRepositoryProvider with a fake; the wired
        // saveBufferToRecoveryProvider must use that same fake instance.
        final fakeRepo = _FakeRecoveryRepository();
        final container = ProviderContainer(
          overrides: [recoveryRepositoryProvider.overrideWithValue(fakeRepo)],
        );
        addTearDown(container.dispose);

        // Resolve the use-case provider — it must not throw.
        final useCase = container.read(saveBufferToRecoveryProvider);
        expect(useCase, isA<SaveBufferToRecovery>());

        // Calling the use case with non-empty text routes through fakeRepo.save.
        await useCase.call('hello');
        expect(fakeRepo.saveCalled, isTrue);
      },
    );

    test(
      'trim-guard: empty text does not call recoveryRepositoryProvider repo',
      () async {
        final fakeRepo = _FakeRecoveryRepository();
        final container = ProviderContainer(
          overrides: [recoveryRepositoryProvider.overrideWithValue(fakeRepo)],
        );
        addTearDown(container.dispose);

        final useCase = container.read(saveBufferToRecoveryProvider);
        await useCase.call('');
        expect(fakeRepo.saveCalled, isFalse);
      },
    );
  });
}
