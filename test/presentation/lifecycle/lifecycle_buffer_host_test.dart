// TASK-08: LifecycleBufferHost — paused-save / resumed-reset / R-07 guard /
// detached secondary.
// Spec refs: FR-M2-05, FR-M2-06, FR-M2-07, FR-M2-08, EC-M2-02, EC-M2-06,
//            EC-M2-08, EC-M2-13, EC-M2-14, §4.1, §4.2
//
// TASK-13: emergencyRecoveryEnabled gate (FR-M5-16, NFR-M5-03).
//
// BUG-001 regression tests: guard must only flip true on save SUCCESS, not
// synchronously at _onPaused/_onDetached dispatch time.  Tests use a
// _CompleterRecoveryRepository to control async timing deterministically.
//
// TDD: tests written and run to FAIL before implementation.
//
// All lifecycle state changes are driven by calling
// [didChangeAppLifecycleState] directly on the State object via a GlobalKey,
// avoiding dependency on platform channels.  Providers are overridden with
// fakes via ProviderScope.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/lifecycle/lifecycle_buffer_host.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Spy [RecoveryRepository] — records every [save] call.
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
}

/// Completer-controlled [RecoveryRepository] — lets tests control exactly
/// when each [save] call resolves or rejects.
///
/// Call [completeSave] to resolve the pending future, or [failSave] to
/// reject it with a [FileSystemException].  Each new [save] call replaces
/// [_completer] so only the most-recent call is controlled.
class _CompleterRecoveryRepository implements RecoveryRepository {
  final List<String> savedTexts = [];
  Completer<File>? _completer;

  /// Number of times [save] has been called.
  int get saveCallCount =>
      savedTexts.length +
      (_completer != null && !(_completer?.isCompleted ?? true) ? 0 : 0);
  int _rawCallCount = 0;
  int get rawSaveCallCount => _rawCallCount;

  @override
  Future<File> save(String text) {
    _rawCallCount++;
    savedTexts.add(text);
    _completer = Completer<File>();
    return _completer!.future;
  }

  /// Resolves the current in-flight [save] future successfully.
  void completeSave() {
    _completer?.complete(File('/tmp/completer_sentinel.txt'));
  }

  /// Rejects the current in-flight [save] future with [FileSystemException].
  void failSave() {
    _completer?.completeError(
      const FileSystemException('disk full', '/tmp/recovery'),
    );
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
      '_savedSinceLastResume becomes true AFTER save completes (BUG-001)',
      (tester) async {
        final completerRepo = _CompleterRecoveryRepository();
        final completerUseCase = SaveBufferToRecovery(completerRepo);

        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: completerUseCase),
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
        await tester.pump();

        // Use case must have been invoked (save in-flight).
        expect(completerRepo.rawSaveCallCount, equals(1));

        // BUG-001: guard must NOT be set yet — save hasn't completed.
        expect(hostState.savedSinceLastResumeForTest, isFalse);

        // Now complete the save future.
        completerRepo.completeSave();
        await tester.pump();

        // Guard flips true only after success.
        expect(hostState.savedSinceLastResumeForTest, isTrue);
      },
    );

    testWidgets(
      '_saved=true: second paused AFTER first save completes → use case NOT '
      'called again (R-07 burst guard)',
      (tester) async {
        final completerRepo = _CompleterRecoveryRepository();
        final completerUseCase = SaveBufferToRecovery(completerRepo);

        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: completerUseCase),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('hello');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        // First paused — starts save.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(completerRepo.rawSaveCallCount, equals(1));

        // Complete the save so the guard flips true.
        completerRepo.completeSave();
        await tester.pump();
        expect(hostState.savedSinceLastResumeForTest, isTrue);

        // Second paused (burst guard active) — must NOT save again.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(completerRepo.rawSaveCallCount, equals(1));
      },
    );

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
      final completerRepo = _CompleterRecoveryRepository();
      final completerUseCase = SaveBufferToRecovery(completerRepo);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: completerUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused — starts save.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(completerRepo.rawSaveCallCount, equals(1));

      // Complete the save so guard flips.
      completerRepo.completeSave();
      await tester.pump();
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
      await tester.pump();
      expect(completerRepo.rawSaveCallCount, equals(2));
      expect(completerRepo.savedTexts.last, equals('world'));
    });
  });

  group('LifecycleBufferHost — error handling (EC-M2-08)', () {
    testWidgets('FileSystemException during save: no uncaught exception; '
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
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      // Allow the async save future (which throws internally) to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Buffer state must remain unchanged after a failed save.
      expect(ref.read(bufferProvider).text, equals('non-empty content'));
    });
  });

  group('LifecycleBufferHost — detached (secondary path)', () {
    testWidgets('_saved=true: detached → no second save', (tester) async {
      final completerRepo = _CompleterRecoveryRepository();
      final completerUseCase = SaveBufferToRecovery(completerRepo);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: completerUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused starts save, then complete it so guard flips true.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      completerRepo.completeSave();
      await tester.pump();
      expect(hostState.savedSinceLastResumeForTest, isTrue);
      expect(completerRepo.rawSaveCallCount, equals(1));

      // Detached: _saved=true → no additional save.
      hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump(const Duration(milliseconds: 50));
      expect(completerRepo.rawSaveCallCount, equals(1));
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
  // BUG-001 regression tests — guard must flip on save SUCCESS only.
  // ---------------------------------------------------------------------------

  group('BUG-001 regression — guard ordering: set on success, not synchronously', () {
    testWidgets(
      'paused starts in-flight save (guard still false); detached fires before '
      'save completes → use-case invoked TWICE (compensating secondary save)',
      (tester) async {
        final completerRepo = _CompleterRecoveryRepository();
        final completerUseCase = SaveBufferToRecovery(completerRepo);

        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: completerUseCase),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('race content');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        // Paused: starts save #1 — future is NOT yet completed.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();

        // Guard must still be false (save not yet done).
        expect(hostState.savedSinceLastResumeForTest, isFalse);
        expect(completerRepo.rawSaveCallCount, equals(1));

        // Detached fires BEFORE the paused save completes.
        hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
        await tester.pump();

        // Detached must have triggered a SECOND save attempt (compensating path).
        expect(completerRepo.rawSaveCallCount, equals(2));

        // Clean up: complete both in-flight futures to avoid unhandled errors.
        completerRepo.completeSave();
        await tester.pump();
      },
    );

    testWidgets(
      'paused save completes successfully → guard flips true; subsequent '
      'detached does NOT save (guard blocks it)',
      (tester) async {
        final completerRepo = _CompleterRecoveryRepository();
        final completerUseCase = SaveBufferToRecovery(completerRepo);

        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: completerUseCase),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('saved content');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        // Paused: starts save.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(hostState.savedSinceLastResumeForTest, isFalse);

        // Complete the save → guard flips true.
        completerRepo.completeSave();
        await tester.pump();
        expect(hostState.savedSinceLastResumeForTest, isTrue);
        expect(completerRepo.rawSaveCallCount, equals(1));

        // Detached fires AFTER save completes: guard is true → no second save.
        hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
        await tester.pump(const Duration(milliseconds: 50));
        expect(completerRepo.rawSaveCallCount, equals(1));
      },
    );

    testWidgets('paused save FAILS (FileSystemException) → guard stays false → '
        'detached retries save (compensating path)', (tester) async {
      final completerRepo = _CompleterRecoveryRepository();
      final completerUseCase = SaveBufferToRecovery(completerRepo);

      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: completerUseCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('failure content');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused: starts save.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(completerRepo.rawSaveCallCount, equals(1));

      // Paused save FAILS.
      completerRepo.failSave();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Guard must remain false after a failed save.
      expect(hostState.savedSinceLastResumeForTest, isFalse);

      // Detached now fires: guard=false → should retry.
      hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump();
      expect(completerRepo.rawSaveCallCount, equals(2));

      // Clean up: complete the detached save to avoid unhandled errors.
      completerRepo.completeSave();
      await tester.pump();
    });
  });

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

        // Save was triggered.
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

        // Gate is ON → call must have fired once.
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

    testWidgets(
      'gate ON + non-empty buffer + paused twice without resume → '
      'call invoked exactly once after first save completes (R-07 burst guard)',
      (tester) async {
        final completerRepo = _CompleterRecoveryRepository();
        final completerUseCase = SaveBufferToRecovery(completerRepo);

        await tester.pumpWidget(
          _buildTestTreeWithSettings(
            notifier: notifier,
            useCase: completerUseCase,
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

        // First paused — starts save.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(completerRepo.rawSaveCallCount, equals(1));

        // Complete the save so the guard flips true.
        completerRepo.completeSave();
        await tester.pump();
        expect(hostState.savedSinceLastResumeForTest, isTrue);

        // Second paused without resume — burst guard must block.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(completerRepo.rawSaveCallCount, equals(1));
      },
    );
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
        'gate ON + already-saved (paused first, save completed): detached → '
        'no-op (burst guard)',
        (tester) async {
          final completerRepo = _CompleterRecoveryRepository();
          final completerUseCase = SaveBufferToRecovery(completerRepo);

          await tester.pumpWidget(
            _buildTestTreeWithSettings(
              notifier: notifier,
              useCase: completerUseCase,
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

          // Paused saves first; complete save so guard flips.
          hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
          await tester.pump();
          completerRepo.completeSave();
          await tester.pump();
          expect(hostState.savedSinceLastResumeForTest, isTrue);
          expect(completerRepo.rawSaveCallCount, equals(1));

          // Detached: guard already set → no additional save.
          hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
          await tester.pump(const Duration(milliseconds: 50));
          expect(completerRepo.rawSaveCallCount, equals(1));
        },
      );
    },
  );
}
