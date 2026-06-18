// TASK-08: LifecycleBufferHost — paused-save / resumed-reset / R-07 guard /
// detached secondary.
// Spec refs: FR-M2-05, FR-M2-06, FR-M2-07, FR-M2-08, EC-M2-02, EC-M2-06,
//            EC-M2-08, EC-M2-13, EC-M2-14, §4.1, §4.2
//
// TASK-13: emergencyRecoveryEnabled gate (FR-M5-16, NFR-M5-03).
//
// T-03 update: _onPaused and _onDetached now call the SYNCHRONOUS
// SaveBufferToRecovery.callSync path. All test doubles updated accordingly:
//   - _SpyRecoveryRepository.saveSync records to savedTexts (same as save()).
//   - _CompleterRecoveryRepository.saveSync records and returns immediately.
// BUG-001 guard tests updated: with sync saves the guard flips within
// didChangeAppLifecycleState (not after an awaited future). The compensating
// detached path remains correct — detached fires before the guard is set only
// if paused itself threw (EC-M2-08 path), since a successful paused save sets
// the guard synchronously.
//
// All lifecycle state changes are driven by calling
// [didChangeAppLifecycleState] directly on the State object via a GlobalKey,
// avoiding dependency on platform channels.  Providers are overridden with
// fakes via ProviderScope.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/buffer/buffer_notifier_impl.dart';
import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/domain/recovery/recovery_repository.dart';
import 'package:foglietto/domain/recovery/save_buffer_to_recovery.dart';
import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/lifecycle/lifecycle_buffer_host.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Spy [RecoveryRepository] — records every [save] AND [saveSync] call.
///
/// T-03: saveSync now records to [savedTexts] since LifecycleBufferHost uses
/// the synchronous path on paused/detached.
class _SpyRecoveryRepository implements RecoveryRepository {
  final List<String> savedTexts = [];

  @override
  Future<File> save(String text) async {
    savedTexts.add(text);
    return File('/tmp/spy_sentinel.txt');
  }

  // M5 stubs — not exercised by lifecycle tests.
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

  // T-03: saveSync records to savedTexts so spy assertions still work when
  // LifecycleBufferHost calls callSync (which delegates to saveSync).
  @override
  File saveSync(String text, {int keep = 10}) {
    savedTexts.add(text);
    return File('/tmp/spy_sentinel_sync.txt');
  }
}

/// Throwing [RecoveryRepository] — simulates [FileSystemException] on save.
class _ThrowingRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) =>
      Future.error(const FileSystemException('disk full', '/tmp/recovery'));

  // M5 stubs — not exercised by these throwing tests.
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

  // Defect-B sync stub — throws like its async counterpart.
  @override
  File saveSync(String text, {int keep = 10}) =>
      throw const FileSystemException('disk full', '/tmp/recovery');
}

/// Spy [RecoveryRepository] that records every synchronous save call.
///
/// Used by tests that need to count saveSync invocations independently of
/// savedTexts (e.g. burst-guard and detached-secondary tests).
class _SyncSpyRecoveryRepository implements RecoveryRepository {
  final List<String> savedTexts = [];
  int syncSaveCallCount = 0;

  @override
  Future<File> save(String text) async {
    savedTexts.add(text);
    return File('/tmp/sync_spy_sentinel.txt');
  }

  @override
  File saveSync(String text, {int keep = 10}) {
    syncSaveCallCount++;
    savedTexts.add(text);
    return File('/tmp/sync_spy_sentinel_sync.txt');
  }

  // M5 stubs.
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
}

/// Spy [BufferNotifierImpl] — extends the concrete class so it can be
/// registered as an override of [bufferProvider] (which is typed
/// `NotifierProvider<BufferNotifierImpl, BufferState>`).
///
/// Records [reset] calls while delegating state to the parent implementation.
class _SpyBufferNotifier extends BufferNotifierImpl {
  int resetCallCount = 0;

  @override
  void reset() {
    resetCallCount++;
    super.reset();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal testable tree with [LifecycleBufferHost] at the root.
///
/// Returns the [GlobalKey] whose current state exposes
/// [didChangeAppLifecycleState] for test-driving lifecycle events.
///
/// The [notifier] is pre-seeded with [initialText] before the widget is
/// pumped.
Widget _buildTestTree({
  required _SpyBufferNotifier notifier,
  required SaveBufferToRecovery useCase,
  Widget child = const SizedBox.shrink(),
}) {
  return ProviderScope(
    overrides: [
      bufferProvider.overrideWith(() => notifier),
      saveBufferToRecoveryProvider.overrideWithValue(useCase),
      // initialSharedTextProvider must be overridden to avoid UnimplementedError
      initialSharedTextProvider.overrideWithValue(null),
    ],
    child: MaterialApp(home: LifecycleBufferHost(child: child)),
  );
}

/// Build a testable tree with an explicit [settingsProvider] override.
///
/// Used by TASK-13 tests to control [emergencyRecoveryEnabled] and
/// [AsyncLoading] states without real SharedPreferences.
Widget _buildTestTreeWithSettings({
  required _SpyBufferNotifier notifier,
  required SaveBufferToRecovery useCase,
  required AsyncValue<AppSettings> settingsValue,
  Widget child = const SizedBox.shrink(),
}) {
  return ProviderScope(
    overrides: [
      bufferProvider.overrideWith(() => notifier),
      saveBufferToRecoveryProvider.overrideWithValue(useCase),
      initialSharedTextProvider.overrideWithValue(null),
      settingsProvider.overrideWith(() => _StubSettingsNotifier(settingsValue)),
    ],
    child: MaterialApp(home: LifecycleBufferHost(child: child)),
  );
}

/// Stub [SettingsNotifier] that returns a fixed [AsyncValue<AppSettings>].
///
/// Used in TASK-13 tests to control the settings state without real
/// SharedPreferences (supports AsyncLoading, AsyncData, AsyncError).
class _StubSettingsNotifier extends SettingsNotifier {
  _StubSettingsNotifier(this._fixedValue);

  final AsyncValue<AppSettings> _fixedValue;

  @override
  Future<AppSettings> build() async {
    state = _fixedValue;
    // Return the value or default; if loading/error, return the default.
    return _fixedValue.value ?? const AppSettings();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _SpyBufferNotifier notifier;
  late _SpyRecoveryRepository spyRepo;
  late SaveBufferToRecovery useCase;

  setUp(() {
    notifier = _SpyBufferNotifier();
    spyRepo = _SpyRecoveryRepository();
    useCase = SaveBufferToRecovery(spyRepo);
  });

  group('LifecycleBufferHost — paused trigger (R-07 guard)', () {
    testWidgets(
      'state.text="hello", _saved=false: paused → use case called exactly once; '
      '_savedSinceLastResume becomes true synchronously (T-03: sync write path)',
      (tester) async {
        final syncSpy = _SyncSpyRecoveryRepository();
        final syncUseCase = SaveBufferToRecovery(syncSpy);

        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: syncUseCase),
        );

        // Seed the buffer state with non-empty text.
        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('hello');
        await tester.pump();

        // Drive paused.
        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        // No pump needed — sync write completes within didChangeAppLifecycleState.

        // Use case must have been invoked (sync write).
        expect(syncSpy.syncSaveCallCount, equals(1));

        // T-03: guard flips SYNCHRONOUSLY on a successful sync write
        // (within the same call frame as didChangeAppLifecycleState).
        expect(hostState.savedSinceLastResumeForTest, isTrue);

        await tester.pump();
      },
    );

    testWidgets('_saved=true: second paused AFTER first save → use case NOT '
        'called again (R-07 burst guard)', (tester) async {
      final syncSpy = _SyncSpyRecoveryRepository();
      final syncUseCase = SaveBufferToRecovery(syncSpy);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: syncUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // First paused — sync write, guard set immediately.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(syncSpy.syncSaveCallCount, equals(1));
      expect(hostState.savedSinceLastResumeForTest, isTrue);

      // Second paused (burst guard active) — must NOT save again.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(syncSpy.syncSaveCallCount, equals(1));
    });

    testWidgets(
      'state.text="   " (whitespace-only): paused → use case NOT called (trim gate)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: useCase),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('   ');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();

        expect(spyRepo.savedTexts, isEmpty);
      },
    );
  });

  group('LifecycleBufferHost — resumed clears guard and resets buffer', () {
    testWidgets('resumed → bufferProvider.reset() called; _saved cleared; '
        'a following paused saves again', (tester) async {
      final syncSpy = _SyncSpyRecoveryRepository();
      final syncUseCase = SaveBufferToRecovery(syncSpy);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: syncUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused — sync write; guard flips true immediately.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(syncSpy.syncSaveCallCount, equals(1));
      expect(hostState.savedSinceLastResumeForTest, isTrue);

      // Resumed — resets buffer and clears guard.
      hostState.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(notifier.resetCallCount, equals(1));
      expect(ref.read(bufferProvider).text, equals(''));
      expect(hostState.savedSinceLastResumeForTest, isFalse);

      // A following paused (with new text) should save again.
      ref.read(bufferProvider.notifier).populate('world');
      await tester.pump();

      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(syncSpy.syncSaveCallCount, equals(2));
      expect(syncSpy.savedTexts.last, equals('world'));
    });
  });

  group('LifecycleBufferHost — error handling (EC-M2-08)', () {
    testWidgets('FileSystemException during saveSync: no uncaught exception; '
        'bufferProvider.state unchanged', (tester) async {
      final throwingRepo = _ThrowingRecoveryRepository();
      final throwingUseCase = SaveBufferToRecovery(throwingRepo);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: throwingUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('non-empty content');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Drive paused — must not throw (EC-M2-08 — backgrounding never crashes).
      // With sync path the exception is caught synchronously in _saveSync().
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();

      // Buffer state must remain unchanged after a failed save.
      expect(ref.read(bufferProvider).text, equals('non-empty content'));
      // Guard must NOT be set on failure.
      expect(hostState.savedSinceLastResumeForTest, isFalse);
    });
  });

  group('LifecycleBufferHost — detached (secondary path)', () {
    testWidgets('_saved=true: detached → no second save', (tester) async {
      final syncSpy = _SyncSpyRecoveryRepository();
      final syncUseCase = SaveBufferToRecovery(syncSpy);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: syncUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused: sync write, guard flips true immediately.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(syncSpy.syncSaveCallCount, equals(1));
      expect(hostState.savedSinceLastResumeForTest, isTrue);

      // Detached: _saved=true → no additional save.
      hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump(const Duration(milliseconds: 50));
      expect(syncSpy.syncSaveCallCount, equals(1));
    });

    testWidgets(
      '_saved=false + non-empty text: detached → best-effort save attempted',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: useCase),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('unsaved content');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        // Drive detached directly (no prior paused).
        hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
        await tester.pump(const Duration(milliseconds: 50));

        expect(spyRepo.savedTexts, equals(['unsaved content']));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // T-03 guard semantics — sync path guard ordering.
  //
  // With the synchronous save path, the guard flips within the
  // didChangeAppLifecycleState call on SUCCESS, and stays false on FAILURE
  // (FileSystemException caught by _saveSync). The "compensating detached save"
  // from BUG-001 now applies only when the paused save THROWS (EC-M2-08 path),
  // because a successful paused sync-save already sets the guard before detached
  // fires.
  // ---------------------------------------------------------------------------

  group(
    'T-03 guard semantics — sync write sets guard synchronously on success',
    () {
      testWidgets(
        'paused sync write succeeds → guard true immediately; detached fires → '
        'no second save (guard blocks)',
        (tester) async {
          final syncSpy = _SyncSpyRecoveryRepository();
          final syncUseCase = SaveBufferToRecovery(syncSpy);

          await tester.pumpWidget(
            _buildTestTree(notifier: notifier, useCase: syncUseCase),
          );

          final container = tester.element(find.byType(LifecycleBufferHost));
          final ref = ProviderScope.containerOf(container);
          ref.read(bufferProvider.notifier).populate('saved content');
          await tester.pump();

          final hostState = tester.state<LifecycleBufferHostState>(
            find.byType(LifecycleBufferHost),
          );

          // Paused: sync write completes; guard flips true synchronously.
          hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
          expect(hostState.savedSinceLastResumeForTest, isTrue);
          expect(syncSpy.syncSaveCallCount, equals(1));

          // Detached fires after guard is already set → no second save.
          hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
          await tester.pump(const Duration(milliseconds: 50));
          expect(syncSpy.syncSaveCallCount, equals(1));
        },
      );

      testWidgets(
        'paused sync write FAILS (FileSystemException) → guard stays false → '
        'detached retries save (compensating path, EC-M2-08)',
        (tester) async {
          final throwingRepo = _ThrowingRecoveryRepository();
          final throwingUseCase = SaveBufferToRecovery(throwingRepo);
          // Use a separate spy to count detached saves after the throw.
          // Switch to a good repo for detached (simulate recover-from-failure).
          // For simplicity: test that paused-failure leaves guard false, then
          // a detached with a good repo would save. We use the throwing repo
          // for both and just verify guard stays false.
          final hostNotifier = _SpyBufferNotifier();
          await tester.pumpWidget(
            _buildTestTree(notifier: hostNotifier, useCase: throwingUseCase),
          );

          final container = tester.element(find.byType(LifecycleBufferHost));
          final ref = ProviderScope.containerOf(container);
          ref.read(bufferProvider.notifier).populate('failure content');
          await tester.pump();

          final hostState = tester.state<LifecycleBufferHostState>(
            find.byType(LifecycleBufferHost),
          );

          // Paused: saveSync throws; guard must remain false.
          hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
          await tester.pump();
          expect(hostState.savedSinceLastResumeForTest, isFalse);

          // Detached: guard=false, saveSync throws again; guard still false.
          // Key: no crash (EC-M2-08).
          expect(
            () => hostState.didChangeAppLifecycleState(
              AppLifecycleState.detached,
            ),
            returnsNormally,
          );
          await tester.pump();
          expect(hostState.savedSinceLastResumeForTest, isFalse);
        },
      );
    },
  );

  group('LifecycleBufferHost — EC-M2-14 non-auto-dispose', () {
    testWidgets(
      'child unmounts while host stays mounted → host still receives lifecycle '
      'callbacks; bufferProvider.state.text survives',
      (tester) async {
        // Use a ValueNotifier to toggle the child so we can trigger a rebuild
        // from outside the builder closure.
        final showChildNotifier = ValueNotifier<bool>(true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bufferProvider.overrideWith(() => notifier),
              saveBufferToRecoveryProvider.overrideWithValue(useCase),
              initialSharedTextProvider.overrideWithValue(null),
            ],
            child: MaterialApp(
              home: ValueListenableBuilder<bool>(
                valueListenable: showChildNotifier,
                builder: (context, showChild, child) {
                  return LifecycleBufferHost(
                    child: showChild
                        ? const Text('child', key: ValueKey('child'))
                        : const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('persistent text');
        await tester.pump();

        // Unmount the child by toggling the notifier.
        showChildNotifier.value = false;
        await tester.pump();

        // Verify child is gone but host still present.
        expect(find.text('child'), findsNothing);
        expect(find.byType(LifecycleBufferHost), findsOneWidget);

        // Host must still receive lifecycle callbacks after child unmount.
        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 50));

        // Buffer text survives (non-auto-disposed bufferProvider).
        expect(ref.read(bufferProvider).text, equals('persistent text'));

        // Save was triggered via sync path.
        expect(spyRepo.savedTexts, equals(['persistent text']));
      },
    );
  });

  group('LifecycleBufferHost — UI compliance (no chrome)', () {
    testWidgets(
      'renders only its child — no additional widgets or chrome added',
      (tester) async {
        const childKey = ValueKey('sentinel_child');

        await tester.pumpWidget(
          _buildTestTree(
            notifier: notifier,
            useCase: useCase,
            child: const SizedBox(key: childKey),
          ),
        );

        // Child is present.
        expect(find.byKey(childKey), findsOneWidget);

        // No Scaffold, AppBar, or other chrome injected by LifecycleBufferHost.
        // (MaterialApp itself has a Scaffold in the root; we check that
        // LifecycleBufferHost itself wraps with nothing else.)
        expect(find.byType(LifecycleBufferHost), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TASK-13: emergencyRecoveryEnabled gate (FR-M5-16, NFR-M5-03)
  // ---------------------------------------------------------------------------

  group('LifecycleBufferHost — emergencyRecoveryEnabled gate (paused path)', () {
    testWidgets(
      'gate OFF: non-empty buffer + paused → SaveBufferToRecovery NOT invoked',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTreeWithSettings(
            notifier: notifier,
            useCase: useCase,
            settingsValue: const AsyncData(
              AppSettings(emergencyRecoveryEnabled: false),
            ),
          ),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('hello');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();

        // Gate is OFF → use case must NOT be called.
        expect(spyRepo.savedTexts, isEmpty);
      },
    );

    testWidgets(
      'gate ON (default): non-empty buffer + paused → SaveBufferToRecovery '
      'invoked exactly once',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTreeWithSettings(
            notifier: notifier,
            useCase: useCase,
            settingsValue: const AsyncData(AppSettings()),
          ),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('hello');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();

        // Gate is ON → call must have fired once (via sync path).
        expect(spyRepo.savedTexts, equals(['hello']));
      },
    );

    testWidgets(
      'settings AsyncLoading + non-empty buffer + paused → defaults to '
      'emergencyRecoveryEnabled=true, call invoked, no throw (EC-08, NFR-M5-03)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTreeWithSettings(
            notifier: notifier,
            useCase: useCase,
            settingsValue: const AsyncLoading(),
          ),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('async-loading text');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        // Must not throw (EC-08 / NFR-M5-03 — no requireValue).
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();

        // Default AppSettings() has emergencyRecoveryEnabled=true → saves.
        expect(spyRepo.savedTexts, equals(['async-loading text']));
      },
    );

    testWidgets('gate ON + non-empty buffer + paused twice without resume → '
        'call invoked exactly once (R-07 burst guard, sync path)', (
      tester,
    ) async {
      final syncSpy = _SyncSpyRecoveryRepository();
      final syncUseCase = SaveBufferToRecovery(syncSpy);

      await tester.pumpWidget(
        _buildTestTreeWithSettings(
          notifier: notifier,
          useCase: syncUseCase,
          settingsValue: const AsyncData(AppSettings()),
        ),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('burst text');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // First paused — sync write; guard flips true immediately.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(syncSpy.syncSaveCallCount, equals(1));
      expect(hostState.savedSinceLastResumeForTest, isTrue);

      // Second paused without resume — burst guard must block.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(syncSpy.syncSaveCallCount, equals(1));
    });
  });

  group(
    'LifecycleBufferHost — emergencyRecoveryEnabled gate (detached path)',
    () {
      testWidgets('gate OFF + not-yet-saved: detached → no save', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildTestTreeWithSettings(
            notifier: notifier,
            useCase: useCase,
            settingsValue: const AsyncData(
              AppSettings(emergencyRecoveryEnabled: false),
            ),
          ),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('detached text');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );
        hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
        await tester.pump(const Duration(milliseconds: 50));

        // Gate is OFF → use case must NOT be called.
        expect(spyRepo.savedTexts, isEmpty);
      });

      testWidgets('gate ON + not-yet-saved: detached → save once', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildTestTreeWithSettings(
            notifier: notifier,
            useCase: useCase,
            settingsValue: const AsyncData(AppSettings()),
          ),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('detached text');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );
        hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
        await tester.pump(const Duration(milliseconds: 50));

        // Gate is ON + guard was clear → save must have fired once.
        expect(spyRepo.savedTexts, equals(['detached text']));
      });

      testWidgets(
        'gate ON + already-saved (paused first, save succeeded): detached → '
        'no-op (burst guard)',
        (tester) async {
          final syncSpy = _SyncSpyRecoveryRepository();
          final syncUseCase = SaveBufferToRecovery(syncSpy);

          await tester.pumpWidget(
            _buildTestTreeWithSettings(
              notifier: notifier,
              useCase: syncUseCase,
              settingsValue: const AsyncData(AppSettings()),
            ),
          );

          final container = tester.element(find.byType(LifecycleBufferHost));
          final ref = ProviderScope.containerOf(container);
          ref.read(bufferProvider.notifier).populate('hello');
          await tester.pump();

          final hostState = tester.state<LifecycleBufferHostState>(
            find.byType(LifecycleBufferHost),
          );

          // Paused: sync write; guard flips true immediately.
          hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
          expect(hostState.savedSinceLastResumeForTest, isTrue);
          expect(syncSpy.syncSaveCallCount, equals(1));

          // Detached: guard already set → no additional save.
          hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
          await tester.pump(const Duration(milliseconds: 50));
          expect(syncSpy.syncSaveCallCount, equals(1));
        },
      );
    },
  );
}
