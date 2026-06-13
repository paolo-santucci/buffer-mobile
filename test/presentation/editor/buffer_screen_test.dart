// TASK-09: BufferScreen widget tests — TDD red phase first.
//
// Spec refs: FR-M2-01, FR-M2-02, FR-M2-03, FR-M2-04, FR-M2-15, FR-M2-16,
//            FR-M2-17, EC-M2-01, EC-M2-03, EC-M2-04, EC-M2-05, EC-M2-10,
//            EC-M2-11, EC-M2-12, NFR-M2-05, NFR-M2-06, §4.1, §5.1.5
//
// High-risk seams tested first:
//   1. Echo-loop guard (state→controller must not re-trigger controller→state).
//   2. Selection preservation + clamping on shrink.
//   3. Cold-start no-flash: first built frame shows seeded text.
//   4. Warm-start save→reset→populate ordering.
//
// ProviderScope overrides replace all I/O with fakes — no filesystem access.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Ordering-aware [RecoveryRepository] fake.
///
/// Records each [save] call in [savedTexts] and also appends an entry to a
/// shared [log] list so warm-start ordering tests can verify save comes BEFORE
/// reset and populate.
class _FakeRecoveryRepository implements RecoveryRepository {
  final List<String> savedTexts = [];

  /// Optional shared ordering log — push `save:text` here.
  List<String>? log;

  @override
  Future<File> save(String text) async {
    savedTexts.add(text);
    log?.add('save:$text');
    return File('/tmp/sentinel-${savedTexts.length}.txt');
  }
}

/// Fake [ShareIntentService] with a controllable warm-start stream.
class _FakeShareIntentService implements ShareIntentService {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  void emit(String text) => _controller.add(text);

  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => _controller.stream;

  @override
  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }
}

/// Spy [BufferNotifierImpl] subclass that records method call ordering.
///
/// Extends the real [BufferNotifierImpl] so it's compatible with
/// [bufferProvider.overrideWith].
class _SpyBufferNotifier extends BufferNotifierImpl {
  List<String>? log;

  @override
  void reset() {
    log?.add('reset');
    super.reset();
  }

  @override
  void populate(String text) {
    log?.add('populate:$text');
    super.populate(text);
  }
}

// ---------------------------------------------------------------------------
// Helper: pump the BufferScreen inside a minimal test harness.
//
// [initialSharedText] — override for initialSharedTextProvider.
// [shareService]      — override for shareIntentServiceProvider.
// [recoveryRepo]      — override for recoveryRepositoryProvider.
// [spyNotifier]       — optional spy; must be non-null when ordering log needed.
// ---------------------------------------------------------------------------
Future<void> _pumpBufferScreen(
  WidgetTester tester, {
  String? initialSharedText,
  _FakeShareIntentService? shareService,
  _FakeRecoveryRepository? recoveryRepo,
  _SpyBufferNotifier? spyNotifier,
}) async {
  final fakeShare = shareService ?? _FakeShareIntentService();
  final fakeRepo = recoveryRepo ?? _FakeRecoveryRepository();

  final overrides = <Override>[
    initialSharedTextProvider.overrideWithValue(initialSharedText),
    shareIntentServiceProvider.overrideWithValue(fakeShare),
    recoveryRepositoryProvider.overrideWithValue(fakeRepo),
    // saveBufferToRecovery wires over recoveryRepositoryProvider automatically.
    if (spyNotifier != null) bufferProvider.overrideWith(() => spyNotifier),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BufferScreen(),
      ),
    ),
  );

  // Allow initState synchronous work to execute and first frame to build.
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -----------------------------------------------------------------------
  // Group 1 — Chrome-free surface (FR-M2-01, §Components §1/§3)
  // -----------------------------------------------------------------------
  group('BufferScreen — chrome-free surface', () {
    testWidgets('cold launch with null initialSharedText → TextField empty', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);
    });

    testWidgets('no AppBar widget present in tree', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('Scaffold has extendBodyBehindAppBar true', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.extendBodyBehindAppBar, isTrue);
    });

    testWidgets(
      'TextField uses InputDecoration.collapsed — no visible border',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final tf = tester.widget<TextField>(find.byType(TextField));
        // InputDecoration.collapsed collapses all decoration.
        // No enabledBorder or focusedBorder means no underline/outline chrome.
        expect(tf.decoration?.enabledBorder, isNull);
        expect(tf.decoration?.focusedBorder, isNull);
      },
    );

    testWidgets('TextField maxLines is null (unbounded)', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.maxLines, isNull);
    });

    testWidgets('TextField is autofocused', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.autofocus, isTrue);
    });

    testWidgets(
      'text colour comes from colorScheme.onSurface (not hardcoded)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final tf = tester.widget<TextField>(find.byType(TextField));
        final expectedColor = AppTheme.light().colorScheme.onSurface;
        expect(tf.style?.color, equals(expectedColor));
      },
    );
  });

  // -----------------------------------------------------------------------
  // Group 2 — controller→state sync (FR-M2-02, EC-M2-01)
  // -----------------------------------------------------------------------
  group('BufferScreen — controller → state sync', () {
    testWidgets('typing updates bufferProvider.state.text', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      // Read state from the ProviderScope: use a descendant element as context.
      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      expect(container.read(bufferProvider).text, equals('abc'));
    });

    testWidgets(
      'typing does NOT write a recovery file (no disk I/O on keystroke)',
      (tester) async {
        final fakeRepo = _FakeRecoveryRepository();
        await _pumpBufferScreen(tester, recoveryRepo: fakeRepo);

        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pump();

        expect(fakeRepo.savedTexts, isEmpty);
      },
    );
  });

  // -----------------------------------------------------------------------
  // Group 3 — echo-loop guard (EC-M2-03)
  // -----------------------------------------------------------------------
  group('BufferScreen — echo-loop guard', () {
    testWidgets('state update carrying same text does not re-trigger updateText', (
      tester,
    ) async {
      // Track how many times updateText is called via the container.
      await _pumpBufferScreen(tester, initialSharedText: null);

      // Type text: controller→state fires once.
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);

      // Verify state holds 'abc'.
      expect(container.read(bufferProvider).text, equals('abc'));

      // Simulate a no-op state update with same text: the state→controller
      // guard must not set controller.text again (which would collapse cursor).
      // We verify indirectly: the TextField's text hasn't changed after pump.
      final tf = tester.widget<TextField>(find.byType(TextField));
      final selectionBefore = tf.controller!.selection;

      // Artificially push an identical state update.
      container.read(bufferProvider.notifier).updateText('abc');
      await tester.pump();

      // Selection must not have changed (no blind reassignment of controller.text).
      final selectionAfter = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .selection;
      expect(selectionAfter, equals(selectionBefore));
    });
  });

  // -----------------------------------------------------------------------
  // Group 4 — state→controller selection preservation (EC-M2-04, EC-M2-05)
  // -----------------------------------------------------------------------
  group('BufferScreen — selection preservation on state→controller', () {
    testWidgets(
      'programmatic shrink: cursor at offset 50 with empty reset → clamped to 0, no RangeError',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);

        // Populate with 60-character text.
        container.read(bufferProvider.notifier).populate('A' * 60);
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        // Move cursor to offset 50.
        controller.selection = const TextSelection.collapsed(offset: 50);
        await tester.pump();

        // reset() shrinks text to "".
        container.read(bufferProvider.notifier).reset();
        await tester.pump();

        // No RangeError; selection clamped to 0.
        expect(controller.selection.baseOffset, equals(0));
        expect(controller.selection.extentOffset, equals(0));
      },
    );

    testWidgets(
      'state→controller: mid-string selection preserved when text changes',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);

        // Populate with initial text.
        container.read(bufferProvider.notifier).populate('hello world');
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        // Set selection at offset 5.
        controller.selection = const TextSelection.collapsed(offset: 5);
        await tester.pump();

        // Populate with longer text — selection at 5 should remain.
        container.read(bufferProvider.notifier).populate('hello world again!');
        await tester.pump();

        // Offset 5 is within 18 chars, so selection must be preserved.
        expect(controller.selection.baseOffset, equals(5));
      },
    );

    testWidgets(
      'state→controller: selection clamped when new text is shorter than cursor offset',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);

        // Populate with text long enough for offset 10.
        container.read(bufferProvider.notifier).populate('0123456789012');
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        controller.selection = const TextSelection.collapsed(offset: 10);
        await tester.pump();

        // Populate with text shorter than offset 10 → selection must clamp.
        container.read(bufferProvider.notifier).populate('short');
        await tester.pump();

        // 'short'.length == 5; clamped to 5.
        expect(
          controller.selection.baseOffset,
          lessThanOrEqualTo('short'.length),
        );
      },
    );
  });

  // -----------------------------------------------------------------------
  // Group 5 — cold-start no-flash (NFR-M2-06, B1/R-14, FR-M2-15)
  // -----------------------------------------------------------------------
  group('BufferScreen — cold-start no-flash', () {
    testWidgets(
      'initialSharedText "shared content" appears in TextField on first frame',
      (tester) async {
        final fakeShare = _FakeShareIntentService();
        final fakeRepo = _FakeRecoveryRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialSharedTextProvider.overrideWithValue('shared content'),
              shareIntentServiceProvider.overrideWithValue(fakeShare),
              recoveryRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const BufferScreen(),
            ),
          ),
        );

        // Single pump — first frame only.
        await tester.pump();

        final tf = tester.widget<TextField>(find.byType(TextField));
        expect(tf.controller?.text ?? '', equals('shared content'));
      },
    );

    testWidgets('null initialSharedText → TextField empty on first frame', (
      tester,
    ) async {
      final fakeShare = _FakeShareIntentService();
      final fakeRepo = _FakeRecoveryRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSharedTextProvider.overrideWithValue(null),
            shareIntentServiceProvider.overrideWithValue(fakeShare),
            recoveryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const BufferScreen(),
          ),
        ),
      );

      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);
    });
  });

  // -----------------------------------------------------------------------
  // Group 6 — warm-start subscriber (FR-M2-16, FR-M2-17, EC-M2-12)
  // -----------------------------------------------------------------------
  group('BufferScreen — warm-start subscriber', () {
    testWidgets(
      'stream emits text → save("old text") → reset() → populate("new text") in order',
      (tester) async {
        // Ordering log shared between spy notifier and fake repo.
        final orderLog = <String>[];

        final spy = _SpyBufferNotifier()..log = orderLog;
        final fakeShare = _FakeShareIntentService();
        final fakeRepo = _FakeRecoveryRepository()..log = orderLog;

        await _pumpBufferScreen(
          tester,
          spyNotifier: spy,
          shareService: fakeShare,
          recoveryRepo: fakeRepo,
        );

        // Establish pre-existing text.
        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);
        container.read(bufferProvider.notifier).populate('old text');
        await tester.pump();

        // Clear the log entries from the populate call above.
        orderLog.clear();
        fakeRepo.savedTexts.clear();

        // Warm-start: stream emits new shared text.
        fakeShare.emit('new text');
        await tester.pump();
        await tester.pump(); // settle async stream delivery

        // 1. Recovery file written for "old text".
        expect(fakeRepo.savedTexts, equals(['old text']));
        // 2. Final state is "new text".
        expect(container.read(bufferProvider).text, equals('new text'));
        // 3. Ordering: save → reset → populate.
        expect(
          orderLog,
          equals(['save:old text', 'reset', 'populate:new text']),
        );
      },
    );

    testWidgets(
      'warm-start with empty buffer: no recovery file, reset, populate',
      (tester) async {
        final orderLog = <String>[];
        final spy = _SpyBufferNotifier()..log = orderLog;
        final fakeShare = _FakeShareIntentService();
        final fakeRepo = _FakeRecoveryRepository()..log = orderLog;

        await _pumpBufferScreen(
          tester,
          spyNotifier: spy,
          shareService: fakeShare,
          recoveryRepo: fakeRepo,
        );

        // Buffer starts empty (default).
        orderLog.clear();
        fakeRepo.savedTexts.clear();

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);

        // Stream emits new text.
        fakeShare.emit('new text');
        await tester.pump();
        await tester.pump();

        // No save (trim guard: empty → SaveBufferToRecovery returns null).
        expect(fakeRepo.savedTexts, isEmpty);
        // Reset and populate still run.
        expect(container.read(bufferProvider).text, equals('new text'));
        // Order: no save entry, then reset, then populate.
        expect(orderLog, containsAll(['reset', 'populate:new text']));
        expect(orderLog, isNot(contains('save:')));
      },
    );

    testWidgets('stream emits nothing → no save/reset/populate cycle', (
      tester,
    ) async {
      final fakeShare = _FakeShareIntentService();
      final fakeRepo = _FakeRecoveryRepository();

      await _pumpBufferScreen(
        tester,
        shareService: fakeShare,
        recoveryRepo: fakeRepo,
      );

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);

      // Populate with some text — no stream emission.
      container.read(bufferProvider.notifier).populate('some text');
      await tester.pump();
      await tester.pump();

      // No stream emission → no save, no reset, no populate.
      expect(fakeRepo.savedTexts, isEmpty);
      // Text is still the same 'some text' (not reset).
      expect(container.read(bufferProvider).text, equals('some text'));
    });
  });
}
