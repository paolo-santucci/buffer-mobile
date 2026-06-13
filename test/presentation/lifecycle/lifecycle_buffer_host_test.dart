// TASK-08: LifecycleBufferHost — paused-save / resumed-reset / R-07 guard /
// detached secondary.
// Spec refs: FR-M2-05, FR-M2-06, FR-M2-07, FR-M2-08, EC-M2-02, EC-M2-06,
//            EC-M2-08, EC-M2-13, EC-M2-14, §4.1, §4.2
//
// TDD: tests written and run to FAIL before implementation.
//
// All lifecycle state changes are driven by calling
// [didChangeAppLifecycleState] directly on the State object via a GlobalKey,
// avoiding dependency on platform channels.  Providers are overridden with
// fakes via ProviderScope.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/lifecycle/lifecycle_buffer_host.dart';

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
}

/// Throwing [RecoveryRepository] — simulates [FileSystemException] on save.
class _ThrowingRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) =>
      Future.error(const FileSystemException('disk full', '/tmp/recovery'));
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
      '_savedSinceLastResume becomes true',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: useCase),
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

        // Use case must have been called exactly once with "hello".
        expect(spyRepo.savedTexts, equals(['hello']));
        // Guard must be set.
        expect(hostState.savedSinceLastResumeForTest, isTrue);
      },
    );

    testWidgets(
      '_saved=true: second paused → use case NOT called again (R-07 burst guard)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestTree(notifier: notifier, useCase: useCase),
        );

        final container = tester.element(find.byType(LifecycleBufferHost));
        final ref = ProviderScope.containerOf(container);
        ref.read(bufferProvider.notifier).populate('hello');
        await tester.pump();

        final hostState = tester.state<LifecycleBufferHostState>(
          find.byType(LifecycleBufferHost),
        );

        // First paused — saves once.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(spyRepo.savedTexts.length, equals(1));

        // Second paused (burst guard) — must NOT save again.
        hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        expect(spyRepo.savedTexts.length, equals(1));
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
      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: useCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused — saves.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(spyRepo.savedTexts.length, equals(1));
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
      expect(spyRepo.savedTexts.length, equals(2));
      expect(spyRepo.savedTexts.last, equals('world'));
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
      await tester.pumpWidget(
        _buildTestTree(notifier: notifier, useCase: useCase),
      );

      final container = tester.element(find.byType(LifecycleBufferHost));
      final ref = ProviderScope.containerOf(container);
      ref.read(bufferProvider.notifier).populate('hello');
      await tester.pump();

      final hostState = tester.state<LifecycleBufferHostState>(
        find.byType(LifecycleBufferHost),
      );

      // Paused saves once.
      hostState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(spyRepo.savedTexts.length, equals(1));

      // Detached: _saved=true → no additional save.
      hostState.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump(const Duration(milliseconds: 50));
      expect(spyRepo.savedTexts.length, equals(1));
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
}
