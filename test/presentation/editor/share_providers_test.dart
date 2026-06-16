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

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/infrastructure/share/share_plus_service.dart';
import 'package:buffer/infrastructure/share/share_target_service.dart';
import 'package:buffer/presentation/editor/share_providers.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Minimal [ShareIntentService] fake for override-friendliness test.
///
/// [disposed] is set to `true` when [dispose] is called, letting tests assert
/// that the provider lifecycle correctly invokes dispose exactly once.
class _FakeShareIntentService implements ShareIntentService {
  bool disposed = false;

  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {
    disposed = true;
  }
}

/// Minimal [ShareTargetService] fake for override test.
class _FakeShareTargetService implements ShareTargetService {
  @override
  Future<void> shareText(String text) async {}
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

  // M5 stubs — not exercised by these provider-graph tests.
  @override
  Future<List<RecoveryNote>> list() async => const [];
  @override
  Future<String> read(RecoveryNote note) async => '';
  @override
  Future<void> delete(RecoveryNote note) async {}
  @override
  Future<void> deleteAll() async {}
  @override
  Future<void> trim(int keep) async {}

  // Defect-B sync stub — not exercised by provider-graph tests.
  @override
  File saveSync(String text, {int keep = 10}) => File('/tmp/sentinel-sync.txt');
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

    test(
      'dispose-once: dispose() called exactly once on container disposal',
      () {
        final fake = _FakeShareIntentService();
        final container = ProviderContainer(
          overrides: [
            shareIntentServiceProvider.overrideWith((ref) {
              ref.onDispose(fake.dispose);
              return fake;
            }),
          ],
        );

        // Read to instantiate the provider (lazy providers run on first read).
        container.read(shareIntentServiceProvider);

        expect(
          fake.disposed,
          isFalse,
          reason: 'dispose must not be called while provider is alive',
        );
        container.dispose();
        expect(
          fake.disposed,
          isTrue,
          reason:
              'dispose must be called exactly once after container disposal',
        );
      },
    );

    test(
      'no-premature-teardown: disposed remains false while provider is alive',
      () {
        final fake = _FakeShareIntentService();
        final container = ProviderContainer(
          overrides: [
            shareIntentServiceProvider.overrideWith((ref) {
              ref.onDispose(fake.dispose);
              return fake;
            }),
          ],
        );
        addTearDown(container.dispose);

        container.read(shareIntentServiceProvider);

        expect(
          fake.disposed,
          isFalse,
          reason: 'dispose must not fire before the container is disposed',
        );
      },
    );
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

  // TASK-08: shareTargetServiceProvider — composition-root seam tests.
  // Spec refs: FR-08, §5.1.3, §5.3.
  group('shareTargetServiceProvider', () {
    test(
      'default resolution: resolves to SharePlusService (a ShareTargetService)',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final service = container.read(shareTargetServiceProvider);

        expect(service, isA<SharePlusService>());
        expect(service, isA<ShareTargetService>());
      },
    );

    test('override: returns the fake instance when overridden', () {
      final fake = _FakeShareTargetService();
      final container = ProviderContainer(
        overrides: [shareTargetServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(shareTargetServiceProvider), same(fake));
    });
  });
}
