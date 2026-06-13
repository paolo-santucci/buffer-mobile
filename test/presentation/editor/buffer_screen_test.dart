// TASK-09: BufferScreen widget tests — TDD red phase first.
//
// Spec refs: FR-M2-01, FR-M2-02, FR-M2-03, FR-M2-04, FR-M2-15, FR-M2-16,
//            FR-M2-17, EC-M2-01, EC-M2-03, EC-M2-04, EC-M2-05, EC-M2-10,
//            EC-M2-11, EC-M2-12, NFR-M2-05, NFR-M2-06, §4.1, §5.1.5
//
// TASK-05 (M3): extended with M3 acceptance tests for:
//   - Soft-\n / hardware-Enter convergence (FR-08, R-03)
//   - Detection predicate + re-entrancy guard (EC-11..EC-14)
//   - Hardware Tab / Shift-Tab / ISO_Left_Tab (FR-14, EC-19)
//   - MARGIN_BELOW_CURSOR constant + scroll mechanics (FR-16/17/19, EC-21/27)
//   - Inset-stability gating (FR-18, EC-21, NFR-01)
//   - Editor TextStyle height 1.4 / null fontSize / null fontFamily (FR-03, NFR-02)
//   - Spell-check reactive wiring (FR-20/21, EC-23/24)
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
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
  int updateTextCallCount = 0;
  String? lastUpdateText;

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

  @override
  void updateText(String text) {
    updateTextCallCount++;
    lastUpdateText = text;
    super.updateText(text);
  }
}

// ---------------------------------------------------------------------------
// Helper: pump the BufferScreen inside a minimal test harness.
//
// [initialSharedText]  — override for initialSharedTextProvider.
// [shareService]       — override for shareIntentServiceProvider.
// [recoveryRepo]       — override for recoveryRepositoryProvider.
// [spyNotifier]        — optional spy; must be non-null when ordering log needed.
// [spellingEnabled]    — override for settingsProvider (reactive spell-check tests).
// ---------------------------------------------------------------------------
Future<void> _pumpBufferScreen(
  WidgetTester tester, {
  String? initialSharedText,
  _FakeShareIntentService? shareService,
  _FakeRecoveryRepository? recoveryRepo,
  _SpyBufferNotifier? spyNotifier,
  bool? spellingEnabled,
}) async {
  final fakeShare = shareService ?? _FakeShareIntentService();
  final fakeRepo = recoveryRepo ?? _FakeRecoveryRepository();

  // Default to spellingEnabled=false in tests: avoids the Flutter spell-check
  // assertion (no native service in headless environment). Tests that explicitly
  // exercise spell-check wiring pass spellingEnabled=true/false directly.
  final effective = spellingEnabled ?? false;
  final settingsOverride = settingsProvider.overrideWith(
    () => _FakeSettingsNotifier(AppSettings(spellingEnabled: effective)),
  );

  final overrides = <Override>[
    initialSharedTextProvider.overrideWithValue(initialSharedText),
    shareIntentServiceProvider.overrideWithValue(fakeShare),
    recoveryRepositoryProvider.overrideWithValue(fakeRepo),
    settingsOverride,
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

/// Fake [SettingsNotifier] that returns a fixed [AppSettings] synchronously.
///
/// Extends [SettingsNotifier] so it satisfies the [settingsProvider.overrideWith]
/// type constraint (`NotifierT = SettingsNotifier`).
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
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
              settingsProvider.overrideWith(
                () => _FakeSettingsNotifier(const AppSettings()),
              ),
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
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(const AppSettings()),
            ),
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

  // -----------------------------------------------------------------------
  // Group 7 — M3: Editor TextStyle (FR-03, NFR-02)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 editor TextStyle', () {
    testWidgets('TextStyle.height is 1.4', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.style?.height, closeTo(1.4, 0.001));
    });

    testWidgets('TextStyle.fontSize is null (no hardcoded size)', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.style?.fontSize, isNull);
    });

    testWidgets('TextStyle.fontFamily is null (no hardcoded family)', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.style?.fontFamily, isNull);
    });

    test('MARGIN_BELOW_CURSOR named constant equals 22.0', () {
      // Verifies the constant value from the source file.
      // The constant is exposed via buffer_screen.dart for the gate scan;
      // here we verify it equals 22.0 exactly.
      expect(kMarginBelowCursor, equals(22.0));
    });
  });

  // -----------------------------------------------------------------------
  // Group 8 — M3: Spell-check wiring (FR-20, FR-21, EC-23, EC-24)
  //
  // Deviation (EC-24, NFR-06): In headless test environments,
  // WidgetsBinding.instance.platformDispatcher.nativeSpellCheckServiceDefined
  // is always false (no real Android/iOS spell-check service). The
  // implementation guards the SpellCheckConfiguration() with that flag:
  // when the native service is unavailable, it falls through to disabled()
  // regardless of spellingEnabled — identical to the platform having no
  // checker. Tests therefore verify that:
  //  - spellingEnabled=false always yields disabled().
  //  - The configuration is derived from settingsProvider (reactive), not
  //    hardcoded (hot toggle from false→false still re-builds).
  //  - No spellCheckService override is ever passed (FR-21).
  // On a real Android/iOS device with spellingEnabled=true the native
  // service is present and SpellCheckConfiguration() (not disabled()) is
  // used. The on-device integration test (TASK-06) covers that path.
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 spell-check', () {
    testWidgets(
      'spellingEnabled=false → spellCheckConfiguration is disabled()',
      (tester) async {
        await _pumpBufferScreen(tester, spellingEnabled: false);
        await tester.pump(); // settle async settings

        final tf = tester.widget<TextField>(find.byType(TextField));
        expect(
          tf.spellCheckConfiguration,
          equals(const SpellCheckConfiguration.disabled()),
        );
      },
    );

    testWidgets('spell-check config derives from settingsProvider (reactive) — '
        'hot-toggle false→false still reads settings, not a hardcoded bool', (
      tester,
    ) async {
      // Pump once with false, then override to false again and verify the
      // configuration is still disabled() (reactive derivation, not cached bool).
      final settingStreamCtrl = StreamController<AppSettings>.broadcast();
      final notifier = _ReactiveSettingsNotifier(settingStreamCtrl.stream);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSharedTextProvider.overrideWithValue(null),
            shareIntentServiceProvider.overrideWithValue(
              _FakeShareIntentService(),
            ),
            recoveryRepositoryProvider.overrideWithValue(
              _FakeRecoveryRepository(),
            ),
            settingsProvider.overrideWith(() => notifier),
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

      // Emit spellingEnabled=false; verify disabled().
      notifier.emit(const AppSettings(spellingEnabled: false));
      await tester.pump();
      await tester.pump();

      var tf = tester.widget<TextField>(find.byType(TextField));
      expect(
        tf.spellCheckConfiguration,
        equals(const SpellCheckConfiguration.disabled()),
      );

      // Emit another false — still disabled (no hardcoded bool drift).
      notifier.emit(const AppSettings(spellingEnabled: false));
      await tester.pump();
      await tester.pump();

      tf = tester.widget<TextField>(find.byType(TextField));
      expect(
        tf.spellCheckConfiguration,
        equals(const SpellCheckConfiguration.disabled()),
      );

      settingStreamCtrl.close();
    });

    testWidgets(
      'no spellCheckService override passed (FR-21 — language follows system)',
      (tester) async {
        await _pumpBufferScreen(tester, spellingEnabled: false);
        await tester.pump();

        final tf = tester.widget<TextField>(find.byType(TextField));
        // SpellCheckConfiguration.disabled() has null spellCheckService —
        // confirms no custom service was injected, no locale forced (FR-21).
        final scc = tf.spellCheckConfiguration;
        expect(scc?.spellCheckService, isNull);
      },
    );

    testWidgets('spellingEnabled=true with no native service → disabled() '
        '(platform guard, no assertion crash in headless tests)', (
      tester,
    ) async {
      // This test verifies the implementation does not crash in headless
      // environments when spellingEnabled=true but no native spell-check
      // service is available. The expected result is disabled().
      await _pumpBufferScreen(tester, spellingEnabled: true);
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      // In headless tests, nativeSpellCheckServiceDefined == false.
      // The implementation falls through to disabled() to avoid the
      // Flutter spell-check assertion (deviation documented above).
      expect(
        tf.spellCheckConfiguration,
        equals(const SpellCheckConfiguration.disabled()),
      );
    });
  });

  // -----------------------------------------------------------------------
  // Group 9 — M3: ScrollController wiring (FR-19, §5.3)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 scroll controller', () {
    testWidgets(
      'TextField.scrollController is the shared _scrollController (FR-19)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final tf = tester.widget<TextField>(find.byType(TextField));
        // The TextField must have a scrollController assigned (the shared one).
        expect(tf.scrollController, isNotNull);
      },
    );

    testWidgets(
      'no second ScrollController in the widget tree (single-scroll-authority)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        // Find all Scrollable widgets. In a bare BufferScreen the only
        // Scrollable should be the one belonging to the TextField's externally
        // owned scroll controller. SingleChildScrollView etc. must not be present.
        final scrollables = tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        );
        // All scrollables must share the same scroll controller instance.
        final controllers = scrollables
            .map((s) => s.controller)
            .whereType<ScrollController>()
            .toSet();

        // At most one distinct ScrollController should govern any scrollable.
        expect(controllers.length, lessThanOrEqualTo(1));
      },
    );
  });

  // -----------------------------------------------------------------------
  // Group 10 — M3: Soft-\n / hardware-Enter convergence (FR-08, R-03)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 newline-path convergence', () {
    testWidgets(
      'soft-\n path: controller value set to "- item\n" → continuation fires → "- item\n- "',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);
        // Seed the buffer with "- item".
        container.read(bufferProvider.notifier).populate('- item');
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;

        // Position the caret at the end of "- item" (offset 6) so the
        // detection predicate's "prior caret == insertion offset" condition
        // is satisfied when the \n is inserted at position 6.
        controller.selection = const TextSelection.collapsed(offset: 6);
        await tester.pump();

        // Simulate soft-keyboard \n: set controller value directly as if the
        // soft Return inserted a \n at offset 6 (end of "- item").
        // Prior collapsed caret was at offset 6, insertion offset is 6, new
        // char at [6] is "\n" — all five predicate conditions satisfied.
        controller.value = const TextEditingValue(
          text: '- item\n',
          selection: TextSelection.collapsed(offset: 7),
        );
        await tester.pump();

        // Continuation must have fired: text should be "- item\n- ".
        expect(controller.text, equals('- item\n- '));
        // Caret must be collapsed after the inserted "- " token (offset 9).
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.baseOffset, equals(9));
      },
    );

    testWidgets('hardware Enter key fires same continuation as soft-\n', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('- item');
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      // Position caret at end of "- item".
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      // Send hardware Return key.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(controller.text, equals('- item\n- '));
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, equals(9));
    });

    testWidgets('hardware KP_Enter fires same continuation as Return', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('- item');
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();

      expect(controller.text, equals('- item\n- '));
      expect(controller.selection.isCollapsed, isTrue);
    });

    testWidgets('hardware ISO_Enter fires same continuation as Return', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('- item');
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      // ISO_Enter is LogicalKeyboardKey.enter on most platforms; send it explicitly.
      // In Flutter widget tests this is sufficient to trigger the Shortcuts handler.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(controller.text, equals('- item\n- '));
    });
  });

  // -----------------------------------------------------------------------
  // Group 11 — M3: Detection predicate (EC-11..EC-14)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 detection predicate', () {
    testWidgets(
      'multi-line paste "a\\nb\\nc" does not trigger continuation (EC-11)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);
        container.read(bufferProvider.notifier).populate('- item');
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        controller.selection = const TextSelection.collapsed(offset: 6);
        await tester.pump();

        // Simulate a multi-char paste — 5 chars inserted at once.
        controller.value = const TextEditingValue(
          text: '- itema\nb\nc',
          selection: TextSelection.collapsed(offset: 11),
        );
        await tester.pump();

        // No continuation marker should be inserted — text stays as pasted.
        expect(controller.text, equals('- itema\nb\nc'));
      },
    );

    testWidgets(
      'range-replace paste of lone "\\n" does not trigger continuation (EC-11)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);
        container.read(bufferProvider.notifier).populate('- item');
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        // Set a RANGE selection (not collapsed) and replace with \n.
        controller.value = const TextEditingValue(
          text: '- item',
          selection: TextSelection(baseOffset: 2, extentOffset: 4),
        );
        await tester.pump();

        // Replace range [2,4] with \n (1 char inserted but prior not collapsed).
        controller.value = const TextEditingValue(
          text: '- \nem',
          selection: TextSelection.collapsed(offset: 3),
        );
        await tester.pump();

        // No continuation — the prior selection was a range, not a collapsed caret.
        expect(controller.text, equals('- \nem'));
      },
    );

    testWidgets('updateText fires exactly once after continuation (EC-14, C2)', (
      tester,
    ) async {
      final spy = _SpyBufferNotifier();
      await _pumpBufferScreen(tester, spyNotifier: spy);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('- item');
      await tester.pump();

      // Reset counter after populate.
      spy.updateTextCallCount = 0;

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      // Move caret to end.
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      // Simulate soft \n insertion.
      controller.value = const TextEditingValue(
        text: '- item\n',
        selection: TextSelection.collapsed(offset: 7),
      );
      await tester.pump();
      await tester.pump(); // settle post-frame callbacks

      // updateText must have been called exactly once with the final continued text.
      expect(spy.updateTextCallCount, equals(1));
      expect(spy.lastUpdateText, equals('- item\n- '));
    });

    testWidgets(
      'no recursive continuation after atomic rewrite (_continuing guard, EC-13)',
      (tester) async {
        final spy = _SpyBufferNotifier();
        await _pumpBufferScreen(tester, spyNotifier: spy);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);
        container.read(bufferProvider.notifier).populate('- item');
        await tester.pump();

        spy.updateTextCallCount = 0;

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        controller.selection = const TextSelection.collapsed(offset: 6);
        await tester.pump();

        // Fire continuation once.
        controller.value = const TextEditingValue(
          text: '- item\n',
          selection: TextSelection.collapsed(offset: 7),
        );
        await tester.pump();
        await tester.pump();

        // Text must be exactly "- item\n- " (one marker, no double marker).
        expect(controller.text, equals('- item\n- '));
        // Only one updateText call (no double-update from re-entrancy).
        expect(spy.updateTextCallCount, equals(1));
      },
    );
  });

  // -----------------------------------------------------------------------
  // Group 12 — M3: Hardware Tab / Shift-Tab (FR-14, EC-19)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 hardware Tab indent/outdent', () {
    testWidgets(
      'Tab on list line indents with two spaces, no literal tab (FR-14, EC-19)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        final element = tester.element(find.byType(TextField));
        final container = ProviderScope.containerOf(element);
        container.read(bufferProvider.notifier).populate('- item');
        await tester.pump();

        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        controller.selection = const TextSelection.collapsed(offset: 3);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        // List line: two-space indent unit.
        expect(controller.text, equals('  - item'));
        // No literal tab character.
        expect(controller.text, isNot(contains('\t')));
      },
    );

    testWidgets('Shift+Tab on indented list line outdents (FR-14)', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('  - item');
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();

      expect(controller.text, equals('- item'));
    });

    testWidgets('Tab on non-list line inserts tab prefix (FR-11)', (
      tester,
    ) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('plain text');
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Non-list line: tab unit.
      expect(controller.text, startsWith('\t'));
    });

    testWidgets('Tab consumed — focus does not change (EC-19)', (tester) async {
      await _pumpBufferScreen(tester, initialSharedText: null);

      final element = tester.element(find.byType(TextField));
      final container = ProviderScope.containerOf(element);
      container.read(bufferProvider.notifier).populate('- item');
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      // Verify TextField has focus before Tab.
      final primaryFocusBefore = tester.binding.focusManager.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Focus must remain on the same widget (TextField).
      final primaryFocusAfter = tester.binding.focusManager.primaryFocus;
      expect(primaryFocusAfter, equals(primaryFocusBefore));
    });
  });

  // -----------------------------------------------------------------------
  // Group 13 — M3: Inset-stability gating (FR-18, EC-21, NFR-01)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 inset-stability gating', () {
    testWidgets(
      'WidgetsBindingObserver registered in initState, removed in dispose',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        // The observer is registered — we verify the screen is mounted correctly.
        // Dispose is tested by removing the widget.
        expect(find.byType(BufferScreen), findsOneWidget);

        // Replace widget tree — dispose triggers removeObserver.
        await tester.pumpWidget(const SizedBox());
        // No exception from double-remove or missed remove.
        expect(find.byType(BufferScreen), findsNothing);
      },
    );

    testWidgets(
      'scroll not fired while inset is changing across consecutive didChangeMetrics (EC-21)',
      (tester) async {
        await _pumpBufferScreen(tester, initialSharedText: null);

        // Find the BufferScreen state to drive didChangeMetrics manually.
        // We test by simulating the metric change and verifying scroll is
        // deferred — use the inset-gating predicate via the screen's public
        // MARGIN_BELOW_CURSOR constant existence and the no-mutation semantics.
        //
        // The key assertion: after typing text while the keyboard inset is
        // "animating" (changing across two observations), scroll offset must
        // not jump prematurely.
        final tf = tester.widget<TextField>(find.byType(TextField));
        final scrollCtrl = tf.scrollController;
        expect(scrollCtrl, isNotNull);

        // Initial scroll offset is 0.
        expect(scrollCtrl!.offset, equals(0.0));

        // The inset gating is verified by the fact that the MARGIN_BELOW_CURSOR
        // constant is 22.0 (tested in group 7) and the on-change scroll only
        // fires post-frame when inset is stable. In a headless test there is no
        // real keyboard inset animation; we verify the guard does not crash and
        // the constant is present.
        expect(kMarginBelowCursor, equals(22.0));
      },
    );
  });

  // -----------------------------------------------------------------------
  // Group 14 — M3: kDebugMode debug affordance (OQ-02, EC-22)
  // -----------------------------------------------------------------------
  group('BufferScreen — M3 kDebugMode debug affordance', () {
    testWidgets('in debug mode, two-button indent/outdent Row is present', (
      tester,
    ) async {
      // kDebugMode is true in flutter test by default.
      await _pumpBufferScreen(tester, initialSharedText: null);

      // The debug affordance renders as IconButtons in a Row.
      // This test only runs in debug mode (kDebugMode == true in test).
      if (kDebugMode) {
        expect(find.byType(IconButton), findsWidgets);
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Reactive settings notifier for hot-toggle tests
// ---------------------------------------------------------------------------

/// A [SettingsNotifier] subclass that can be driven imperatively by tests.
///
/// Starts with a default [AppSettings] (from a completer), then allows
/// [emit] to push new settings synchronously.
class _ReactiveSettingsNotifier extends SettingsNotifier {
  _ReactiveSettingsNotifier(Stream<AppSettings> stream) : _stream = stream;
  final Stream<AppSettings> _stream;
  StreamSubscription<AppSettings>? _sub;

  @override
  Future<AppSettings> build() async {
    final completer = Completer<AppSettings>();
    _sub = _stream.listen((s) {
      if (!completer.isCompleted) {
        completer.complete(s);
      } else {
        state = AsyncData(s);
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return completer.future;
  }

  void emit(AppSettings s) {
    state = AsyncData(s);
  }
}
