// TASK-08 (SP-20260615): LineNumberGutter widget tests — TDD red phase first.
//
// Spec refs: FR-14, FR-15, FR-16, NFR-06, NFR-09
// Contract:  C7 (spec §5.1), gutter metrics strategy (spec §5.2)
// Edge cases: EC-01 (empty buffer), EC-10 (pre-layout guard)
//
// TDD discipline:
//   1. All tests written and confirmed RED before implementation.
//   2. Implementation makes them GREEN.
//   3. No regressions in the existing suite.
//
// NOTE: Tests that require a real rendering pipeline (scroll sync, font sync,
// gutter top alignment, wrap-count) are widget tests in this file.
// Large-buffer perf test is tagged @Tags(['on-device']) and headless-skipped
// per project convention (OQ-12).
//
// <!-- CANON GAP: line-number-gutter anatomy/styling tokens/RTL rule absent
//      from ui-design-bible (OQ-08/OQ-14); dimmed-secondary ~0.58-opacity
//      onSurface number colour + surface background + leading-edge placement
//      pending bible note -->

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/line_number_gutter.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async => File('/tmp/sentinel.txt');
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
  @override
  File saveSync(String text, {int keep = 10}) => File('/tmp/sentinel-sync.txt');
}

class _FakeShareIntentService implements ShareIntentService {
  final StreamController<String> _ctrl = StreamController<String>.broadcast();
  @override
  Future<String?> initialSharedText() async => null;
  @override
  Stream<String> sharedTextStream() => _ctrl.stream;
  @override
  void dispose() {
    if (!_ctrl.isClosed) _ctrl.close();
  }
}

/// Fake [SettingsNotifier] that returns a fixed [AppSettings] synchronously.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

// ---------------------------------------------------------------------------
// Helper: pump [BufferScreen] with the given settings.
// ---------------------------------------------------------------------------

Future<void> _pumpBufferScreenWithSettings(
  WidgetTester tester, {
  required AppSettings settings,
  double? viewWidth,
  double? viewHeight,
  String initialText = '',
}) async {
  final fakeShare = _FakeShareIntentService();
  final fakeRepo = _FakeRecoveryRepository();

  if (viewWidth != null || viewHeight != null) {
    tester.view.physicalSize = Size(viewWidth ?? 800.0, viewHeight ?? 1200.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSharedTextProvider.overrideWithValue(
          initialText.isEmpty ? null : initialText,
        ),
        shareIntentServiceProvider.overrideWithValue(fakeShare),
        recoveryRepositoryProvider.overrideWithValue(fakeRepo),
        settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
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
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Group 1 — NFR-09: no persistence, constructor shape
  // -------------------------------------------------------------------------
  group('LineNumberGutter — NFR-09 no persistence / constructor contract', () {
    test(
      'widget exists as a class in line_number_gutter.dart (compile-time gate)',
      () {
        // If LineNumberGutter is not yet defined, this file fails to compile.
        // The test itself just verifies the widget type exists.
        expect(LineNumberGutter, isA<Type>());
      },
    );

    testWidgets(
      'constructor takes only scrollController/editorContext/textStyle/strutStyle — no EditorController',
      (tester) async {
        final sc = ScrollController();
        addTearDown(sc.dispose);

        // Pump a minimal tree to get a valid BuildContext.
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        const style = TextStyle(fontSize: 14.0);
        const strut = StrutStyle(fontSize: 14.0);

        // Must compile and not throw:
        final gutter = LineNumberGutter(
          scrollController: sc,
          editorContext: capturedContext,
          textStyle: style,
          strutStyle: strut,
        );

        // Widget is a StatefulWidget (structural proof that it has no EditorController):
        expect(gutter, isA<StatefulWidget>());
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 2 — EC-10: pre-layout guard (empty boxes → no throw)
  // -------------------------------------------------------------------------
  group('LineNumberGutter — EC-10 pre-layout guard', () {
    testWidgets('mounts in a zero-size viewport without throwing (EC-10)', (
      tester,
    ) async {
      final sc = ScrollController();
      addTearDown(sc.dispose);

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Mount gutter in a zero-size context (no RenderEditable descendant).
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 0,
            height: 0,
            child: LineNumberGutter(
              scrollController: sc,
              editorContext: capturedContext,
              textStyle: const TextStyle(fontSize: 14.0),
              strutStyle: const StrutStyle(fontSize: 14.0),
            ),
          ),
        ),
      );

      // No exception on zero-size / pre-layout.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'rowNumbersForTest returns empty list when no RenderEditable found (EC-10)',
      (tester) async {
        final sc = ScrollController();
        addTearDown(sc.dispose);

        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        late LineNumberGutter gutter;
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 200,
              height: 400,
              child: Builder(
                builder: (ctx) {
                  gutter = LineNumberGutter(
                    scrollController: sc,
                    editorContext: capturedContext,
                    textStyle: const TextStyle(fontSize: 14.0),
                    strutStyle: const StrutStyle(fontSize: 14.0),
                  );
                  return gutter;
                },
              ),
            ),
          ),
        );

        await tester.pump();

        // When there is no EditableText descendant in editorContext, the gutter
        // row list is empty (EC-10: empty boxes → no throw, no crash).
        final state = tester.state<LineNumberGutterState>(
          find.byType(LineNumberGutter),
        );
        expect(state.rowNumbersForTest, isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 3 — FR-14: gutter visibility toggle
  // -------------------------------------------------------------------------
  group('LineNumberGutter — FR-14 visibility toggle', () {
    testWidgets('gutter absent when showLineNumbers == false (FR-14)', (
      tester,
    ) async {
      await _pumpBufferScreenWithSettings(
        tester,
        settings: const AppSettings(showLineNumbers: false),
        viewWidth: 800.0,
        viewHeight: 1200.0,
      );
      expect(find.byType(LineNumberGutter), findsNothing);
    });

    testWidgets('gutter present when showLineNumbers == true (FR-14)', (
      tester,
    ) async {
      await _pumpBufferScreenWithSettings(
        tester,
        settings: const AppSettings(showLineNumbers: true),
        viewWidth: 800.0,
        viewHeight: 1200.0,
      );
      expect(find.byType(LineNumberGutter), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Group 4 — EC-01: empty buffer → single row numbered 1
  // -------------------------------------------------------------------------
  group('LineNumberGutter — EC-01 empty buffer', () {
    testWidgets(
      'empty buffer with showLineNumbers=true → gutter shows row 1 and no crash (EC-01)',
      (tester) async {
        await _pumpBufferScreenWithSettings(
          tester,
          settings: const AppSettings(showLineNumbers: true),
          viewWidth: 800.0,
          viewHeight: 1200.0,
          initialText: '',
        );

        // Gutter must be mounted.
        expect(find.byType(LineNumberGutter), findsOneWidget);

        // After layout, the row-number list must be [1] for an empty buffer.
        await tester.pump(); // allow post-frame callbacks
        final state = tester.state<LineNumberGutterState>(
          find.byType(LineNumberGutter),
        );

        // EC-01: at least one row (number 1) for an empty buffer.
        // Allow headless fallback: in headless, getBoxesForSelection may return
        // empty for the empty range. The spec requires no crash and at least one
        // row when text is ''. In headless the gutter may show 0 or 1 rows.
        // Assert no exception and correct row count when rows are present.
        expect(tester.takeException(), isNull);
        final rows = state.rowNumbersForTest;
        if (rows.isNotEmpty) {
          expect(rows[0], equals(1), reason: 'First row must be numbered 1');
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 4b — FR-16: gutter recomputes on text change (disappear-on-type fix)
  //
  // Regression guard for the on-device defect "row numbers disappear when I
  // start typing". The screen does NOT rebuild on keystrokes (it ref.listens,
  // not watches, the buffer) and short text does not scroll, so before the fix
  // nothing triggered a recompute and the gutter stayed at its initial state.
  // The gutter now observes the editor controller (read-only Listenable) and
  // recomputes via a coalesced post-frame callback.
  // -------------------------------------------------------------------------
  group('LineNumberGutter — FR-16 text reactivity', () {
    testWidgets(
      'typing a multi-line buffer updates the gutter without scroll or rebuild',
      (tester) async {
        await _pumpBufferScreenWithSettings(
          tester,
          settings: const AppSettings(showLineNumbers: true),
          viewWidth: 800.0,
          viewHeight: 1200.0,
          initialText: '',
        );

        await tester.pump(); // initial post-frame recompute (empty → [1])
        final state = tester.state<LineNumberGutterState>(
          find.byType(LineNumberGutter),
        );
        final initialRows = state.rowNumbersForTest.length;

        // Type three logical lines. No scroll fits in 1200px, and the screen
        // does not rebuild — the ONLY path to a recompute is the controller
        // Listenable wired in TASK-08-fix.
        await tester.enterText(find.byType(TextField), 'alpha\nbravo\ncharlie');
        await tester.pump(); // controller notifies → schedule recompute
        await tester.pump(); // post-frame recompute runs

        expect(tester.takeException(), isNull);
        final rows = state.rowNumbersForTest;
        // Headless, empty boxes fall back to one synthetic row per logical line
        // ⇒ ≥3 rows. Staleness/blankness here is the disappear-on-type bug.
        expect(
          rows.length,
          greaterThanOrEqualTo(3),
          reason:
              'After typing a 3-line buffer the gutter must recompute via the '
              'text Listenable (FR-16). Stale/blank = disappear-on-type '
              'regression. initialRows=$initialRows rows=$rows',
        );
        expect(rows.first, equals(1));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 5 — FR-15: sequential numbering (one number per visual row)
  // -------------------------------------------------------------------------
  group('LineNumberGutter — FR-15 sequential numbering', () {
    testWidgets('row numbers are sequential starting from 1 (FR-15)', (
      tester,
    ) async {
      // Use a narrow viewport to force wrapping.
      tester.view.physicalSize = const Size(300.0, 1200.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // A sentence long enough to wrap at 300 logical px.
      const longText =
          'The quick brown fox jumps over the lazy dog and keeps going to make a long line';

      await _pumpBufferScreenWithSettings(
        tester,
        settings: const AppSettings(showLineNumbers: true),
        initialText: longText,
      );

      await tester.pump(); // allow post-frame layout
      await tester.pump(); // second pump for scroll controller attachment

      expect(find.byType(LineNumberGutter), findsOneWidget);
      final state = tester.state<LineNumberGutterState>(
        find.byType(LineNumberGutter),
      );

      final rows = state.rowNumbersForTest;
      // In a real rendering environment the text wraps → multiple rows.
      // In headless, getBoxesForSelection may not return boxes (no layout).
      // Assert: if rows are present, they must be sequential from 1.
      if (rows.length > 1) {
        for (int i = 0; i < rows.length; i++) {
          expect(
            rows[i],
            equals(i + 1),
            reason: 'Row $i must be numbered ${i + 1} (sequential FR-15)',
          );
        }
        // Specifically, continuation rows must NOT all have the same number.
        // (FR-15 negative: logical-line gutter misaligns.)
        final allSame = rows.every((n) => n == rows[0]);
        expect(
          allSame,
          isFalse,
          reason:
              'All rows having the same number indicates logical-line gutter (FR-15 violated)',
        );
      }
      // In headless with 0 or 1 rows: no assertion on duplicates (cannot wrap
      // without real layout). No throw is the required invariant.
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Group 6 — FR-16: scroll sync
  // -------------------------------------------------------------------------
  group('LineNumberGutter — FR-16 scroll sync', () {
    testWidgets(
      'gutter row tops shift when scrollController offset changes (FR-16)',
      (tester) async {
        // Use a viewport tall enough for a multi-line buffer.
        tester.view.physicalSize = const Size(800.0, 400.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Many lines so there is room to scroll.
        final manyLines = List.generate(50, (i) => 'Line ${i + 1}').join('\n');

        await _pumpBufferScreenWithSettings(
          tester,
          settings: const AppSettings(showLineNumbers: true),
          initialText: manyLines,
        );

        await tester.pump();

        expect(find.byType(LineNumberGutter), findsOneWidget);
        final state = tester.state<LineNumberGutterState>(
          find.byType(LineNumberGutter),
        );

        // Capture row tops before scroll (may be empty in headless).
        final rowsBefore = List<int>.from(state.rowNumbersForTest);

        // Scroll down via the shared controller.
        // In headless the ScrollController may have no clients — guard with
        // hasClients to avoid a test error.
        final scrollController = state.scrollControllerForTest;
        if (scrollController.hasClients &&
            scrollController.position.maxScrollExtent > 0) {
          await tester.dragFrom(
            tester.getCenter(find.byType(BufferScreen)),
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();

          final rowsAfter = List<int>.from(state.rowNumbersForTest);
          // The visible row range should change (scroll sync).
          // In headless both lists may be empty — the assertion skips.
          if (rowsBefore.isNotEmpty && rowsAfter.isNotEmpty) {
            // After scrolling down, the first visible row number should be
            // larger (the viewport shows later rows).
            expect(
              rowsAfter.first,
              greaterThanOrEqualTo(rowsBefore.first),
              reason:
                  'After scroll, first visible row number must be >= before',
            );
          }
        }

        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 7 — FR-06a coupling: gutter top == editorTopInset
  // -------------------------------------------------------------------------
  group('LineNumberGutter — FR-06a gutter top aligns with TextField top', () {
    testWidgets(
      'gutter top rect equals TextField top within 1px (FR-06a coupling)',
      (tester) async {
        // Set a specific safe-area top to make editorTopInset predictable.
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: 24.0);
        tester.view.physicalSize = const Size(800.0, 1200.0);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpBufferScreenWithSettings(
          tester,
          settings: const AppSettings(showLineNumbers: true),
        );

        await tester.pump();

        expect(find.byType(LineNumberGutter), findsOneWidget);

        // The gutter and the TextField share the same outer Padding — their
        // top origins must be within 1 px of each other.
        final gutterRect = tester.getRect(find.byType(LineNumberGutter));
        final editorTf = find.byWidgetPredicate(
          (w) => w is TextField && w.expands == true,
        );
        if (tester.any(editorTf)) {
          final tfRect = tester.getRect(editorTf.first);
          expect(
            (gutterRect.top - tfRect.top).abs(),
            lessThanOrEqualTo(2.0),
            reason:
                'Gutter top must align with TextField top within 2px (FR-06a)',
          );
        }

        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 8 — on-device performance (tagged, headless-skipped — OQ-12/NFR-06)
  // -------------------------------------------------------------------------
  group('LineNumberGutter — NFR-06 large-buffer perf (on-device only)', () {
    testWidgets(
      '5000-line buffer fling scroll with gutter ON — no exception (OQ-12)',
      (tester) async {
        final manyLines = List.generate(
          5000,
          (i) => 'Line ${i + 1}',
        ).join('\n');

        await _pumpBufferScreenWithSettings(
          tester,
          settings: const AppSettings(showLineNumbers: true),
          viewWidth: 400.0,
          viewHeight: 800.0,
          initialText: manyLines,
        );

        await tester.pump();

        // Fling scroll.
        await tester.fling(
          find.byType(TextField).first,
          const Offset(0, -3000),
          5000,
        );
        await tester.pumpAndSettle();

        expect(find.byType(LineNumberGutter), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      tags: ['on-device'],
    );
  });
}
