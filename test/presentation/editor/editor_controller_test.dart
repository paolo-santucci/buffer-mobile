// Tests for EditorController — the single unified TextEditingController subclass
// shared by M3 (text-editor) and M4 (find-replace).
//
// Spec refs: FR-15, EC-07, EC-10, EC-26, NFR-09
//
// Test-first (TDD): all tests below are written before the implementation exists.
// Run `flutter test test/presentation/editor/editor_controller_test.dart` to confirm
// they fail, then again after implementation to confirm they pass.

import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // FR-15 — Class exists, subclasses TextEditingController, no-arg constructor
  // ---------------------------------------------------------------------------
  group('EditorController — class contract (FR-15)', () {
    test('is instantiable with no required arguments', () {
      final ec = EditorController();
      expect(ec, isA<EditorController>());
      ec.dispose();
    });

    test('is a TextEditingController subclass', () {
      final ec = EditorController();
      expect(ec, isA<TextEditingController>());
      ec.dispose();
    });

    test('accepts initial text via named parameter', () {
      final ec = EditorController(text: 'hello');
      expect(ec.text, 'hello');
      ec.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // EC-10 — highlightRanges setter stores value and does NOT mutate selection
  // ---------------------------------------------------------------------------
  group('highlightRanges (EC-10 — no selection mutation)', () {
    test('defaults to empty list before any assignment', () {
      final ec = EditorController();
      expect(ec.highlightRanges, isEmpty);
      ec.dispose();
    });

    test('stores the assigned list', () {
      final ec = EditorController();
      const range = TextRange(start: 0, end: 3);
      ec.highlightRanges = [range];
      expect(ec.highlightRanges, [range]);
      ec.dispose();
    });

    test('setting highlightRanges does NOT mutate selection', () {
      final ec = EditorController(text: 'hello world');
      // Establish a non-trivial selection first.
      ec.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      final selectionBefore = ec.selection;

      ec.highlightRanges = [const TextRange(start: 0, end: 3)];

      expect(
        ec.selection,
        selectionBefore,
        reason: 'setting highlightRanges must not mutate selection (EC-10)',
      );
      ec.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // EC-10 — currentMatchIndex setter stores value and does NOT mutate selection
  // ---------------------------------------------------------------------------
  group('currentMatchIndex (EC-10 — no selection mutation)', () {
    test('defaults to null', () {
      final ec = EditorController();
      expect(ec.currentMatchIndex, isNull);
      ec.dispose();
    });

    test('stores the assigned index', () {
      final ec = EditorController();
      ec.currentMatchIndex = 2;
      expect(ec.currentMatchIndex, 2);
      ec.dispose();
    });

    test('setting currentMatchIndex does NOT mutate selection', () {
      final ec = EditorController(text: 'hello world');
      ec.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
      final selectionBefore = ec.selection;

      ec.currentMatchIndex = 0;

      expect(
        ec.selection,
        selectionBefore,
        reason: 'setting currentMatchIndex must not mutate selection (EC-10)',
      );
      ec.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // FR-15 / FR-13 — buildTextSpan: text preserved + highlight painting (M4)
  //
  // These tests cover:
  //   (a) base text still reaches the output (super called for base style)
  //   (b) secondaryContainer background on non-current match runs
  //   (c) primaryContainer background on the current-match run
  //   (d) no background on text outside any match
  //   (e) empty highlightRanges → output equals super (EC-26 composing stays green)
  //   (f) no selection read/write during build (EC-10)
  //   (g) surrogate-pair safe: concatenated text == original (EC-12)
  // ---------------------------------------------------------------------------
  group('buildTextSpan (FR-15 / FR-13 — highlight painting, M4)', () {
    // Helpers ----------------------------------------------------------------

    /// Flattens all text across the TextSpan tree.
    String flatText(InlineSpan root) {
      final buf = StringBuffer();
      void collect(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          s.children?.forEach(collect);
        }
      }

      collect(root);
      return buf.toString();
    }

    /// Collects all (text, background) pairs for TextSpan leaves that have text.
    List<(String, Color?)> spansWithBg(InlineSpan root) {
      final result = <(String, Color?)>[];
      void collect(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null && s.text!.isNotEmpty) {
            result.add((s.text!, s.style?.backgroundColor));
          }
          s.children?.forEach(collect);
        }
      }

      collect(root);
      return result;
    }

    // (a) Base text preserved — super called for base style ------------------

    testWidgets('flattened text contains the editor text', (
      WidgetTester tester,
    ) async {
      final ec = EditorController(text: 'hello');
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final span = ec.buildTextSpan(
        context: ctx,
        style: null,
        withComposing: false,
      );
      expect(flatText(span), contains('hello'));
      ec.dispose();
    });

    // (b/c/d) Highlight painting with one span, currentMatchIndex null -------

    testWidgets(
      'one highlighted range, no current match → secondaryContainer bg on match '
      'run, no bg outside',
      (WidgetTester tester) async {
        // text: "hello world", match on "hello" (0..5)
        final ec = EditorController(text: 'hello world');
        ec.highlightRanges = [const TextRange(start: 0, end: 5)];
        // currentMatchIndex stays null

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final cs = Theme.of(ctx).colorScheme;
        final span = ec.buildTextSpan(
          context: ctx,
          style: null,
          withComposing: false,
        );
        final pairs = spansWithBg(span);

        // The match run must carry secondaryContainer background.
        final matchRuns = pairs.where((p) => p.$1 == 'hello');
        expect(matchRuns, isNotEmpty, reason: 'match text "hello" must appear');
        for (final r in matchRuns) {
          expect(
            r.$2,
            cs.secondaryContainer,
            reason: 'non-current match run must have secondaryContainer bg',
          );
        }

        // Text outside the match must carry NO background override.
        final outsideRuns = pairs.where((p) => p.$1 == ' world');
        expect(
          outsideRuns,
          isNotEmpty,
          reason: 'text outside match must appear',
        );
        for (final r in outsideRuns) {
          expect(
            r.$2,
            isNull,
            reason: 'text outside any match must have null background',
          );
        }

        // Flattened text must still equal the original.
        expect(flatText(span), 'hello world');
        ec.dispose();
      },
    );

    // (b/c) Three spans, currentMatchIndex = 1 --------------------------------

    testWidgets(
      '3 highlighted ranges, currentMatchIndex=1 → primaryContainer on span 1, '
      'secondaryContainer on spans 0 and 2',
      (WidgetTester tester) async {
        // text: "aa bb cc"
        // spans: "aa"@0..2, "bb"@3..5, "cc"@6..8
        final ec = EditorController(text: 'aa bb cc');
        ec.highlightRanges = [
          const TextRange(start: 0, end: 2),
          const TextRange(start: 3, end: 5),
          const TextRange(start: 6, end: 8),
        ];
        ec.currentMatchIndex = 1; // "bb" is the current match

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final cs = Theme.of(ctx).colorScheme;
        final span = ec.buildTextSpan(
          context: ctx,
          style: null,
          withComposing: false,
        );
        final pairs = spansWithBg(span);

        // Span 1 (current match "bb") → primaryContainer.
        final currentRuns = pairs.where((p) => p.$1 == 'bb');
        expect(currentRuns, isNotEmpty, reason: '"bb" must appear as a span');
        for (final r in currentRuns) {
          expect(
            r.$2,
            cs.primaryContainer,
            reason: 'current-match run must have primaryContainer bg',
          );
        }

        // Spans 0 and 2 ("aa", "cc") → secondaryContainer.
        for (final text in ['aa', 'cc']) {
          final nonCurrentRuns = pairs.where((p) => p.$1 == text);
          expect(
            nonCurrentRuns,
            isNotEmpty,
            reason: '"$text" must appear as a span',
          );
          for (final r in nonCurrentRuns) {
            expect(
              r.$2,
              cs.secondaryContainer,
              reason:
                  'non-current match run "$text" must have secondaryContainer bg',
            );
          }
        }

        // Flattened text must still equal the original.
        expect(flatText(span), 'aa bb cc');
        ec.dispose();
      },
    );

    // (e) Empty highlightRanges → no background; text == super output ----------

    testWidgets(
      'empty highlightRanges → flattened text equals super; no background override '
      '(EC-26 composing preserved)',
      (WidgetTester tester) async {
        final ec = EditorController(text: 'seam check');
        // highlightRanges stays [] (default)

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final span = ec.buildTextSpan(
          context: ctx,
          style: null,
          withComposing: false,
        );
        expect(flatText(span), contains('seam check'));

        // No span must carry a non-null background.
        final pairs = spansWithBg(span);
        for (final p in pairs) {
          expect(
            p.$2,
            isNull,
            reason:
                'with no highlightRanges, no background override must appear',
          );
        }
        ec.dispose();
      },
    );

    // (f) No selection read/write during span build (EC-10) -------------------

    testWidgets('buildTextSpan does not mutate selection (EC-10)', (
      WidgetTester tester,
    ) async {
      final ec = EditorController(text: 'hello world');
      ec.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
      final selBefore = ec.selection;

      ec.highlightRanges = [const TextRange(start: 0, end: 5)];
      ec.currentMatchIndex = 0;

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      ec.buildTextSpan(context: ctx, style: null, withComposing: false);

      expect(
        ec.selection,
        selBefore,
        reason: 'buildTextSpan must not mutate selection (EC-10)',
      );
      ec.dispose();
    });

    // (g) Surrogate-pair safe (EC-12) -----------------------------------------

    testWidgets(
      'surrogate-pair emoji text: concatenated spans equal original string (EC-12)',
      (WidgetTester tester) async {
        // "hi 😀 bye" — 😀 is U+1F600, represented as two UTF-16 code units.
        // UTF-16 offsets: h=0,i=1,' '=2,😀=3..5,' '=5,b=6,y=7,e=8
        // Match "bye" at UTF-16 offset 6..9.
        const text = 'hi 😀 bye';
        final ec = EditorController(text: text);
        ec.highlightRanges = [
          TextRange(start: text.length - 3, end: text.length),
        ];
        ec.currentMatchIndex = 0;

        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final span = ec.buildTextSpan(
          context: ctx,
          style: null,
          withComposing: false,
        );

        // Concatenated text of all spans must exactly equal the original.
        expect(
          flatText(span),
          text,
          reason:
              'surrogate-pair text must not be split; concatenated spans == original',
        );
        ec.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // M3 — continueListOnNewline (OQ-10: evolved from M1 plain-\n stub)
  //
  // The return type has widened from String to ({String text, TextSelection selection})?.
  // M1 tests that asserted the plain-"\n" string are replaced by tests that
  // assert:
  //   (a) delegation to ListContinuation.process (non-null result on a list line)
  //   (b) collapsed TextSelection wrapping the returned caret offset
  //   (c) null return on a non-list line (no continuation)
  //   (d) EC-07 purity: no controller mutation, no notifyListeners
  //   (e) no throw at offset 0 or end-of-text
  // ---------------------------------------------------------------------------
  group('continueListOnNewline (M3 — widened delegation, EC-07, OQ-10)', () {
    // ---- Delegation to ListContinuation.process ----

    test('returns non-null record on a list line (bullet)', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('- item', 6);
      expect(
        result,
        isNotNull,
        reason: '"- item" is a bullet list line; process() returns non-null',
      );
      ec.dispose();
    });

    test('returned selection is collapsed (isCollapsed == true)', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('- item', 6);
      expect(result, isNotNull);
      expect(
        result!.selection.isCollapsed,
        isTrue,
        reason: 'caret wraps into a collapsed TextSelection (spec §5.3)',
      );
      ec.dispose();
    });

    test('returned selection.baseOffset equals the caret from process()', () {
      // "- item" → process returns ContinuationResult("- item\n- ", 9).
      // baseOffset must be 9 (after the inserted "- " token).
      final ec = EditorController();
      final result = ec.continueListOnNewline('- item', 6);
      expect(result, isNotNull);
      // The new text is "- item\n- "; the caret sits after "- " at offset 9.
      expect(
        result!.selection.baseOffset,
        9,
        reason: 'baseOffset == process().caret (after "\\n- " insertion)',
      );
      ec.dispose();
    });

    test('returned text matches the continuation-applied buffer', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('- item', 6);
      expect(result, isNotNull);
      expect(
        result!.text,
        '- item\n- ',
        reason: 'text is the post-continuation buffer from process()',
      );
      ec.dispose();
    });

    test('returns null for a non-list line (no continuation fires)', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('plain text', 10);
      expect(
        result,
        isNull,
        reason: 'plain text line: process returns null → method returns null',
      );
      ec.dispose();
    });

    test('returns null for empty text (totality — no throw)', () {
      final ec = EditorController();
      expect(() => ec.continueListOnNewline('', 0), returnsNormally);
      final result = ec.continueListOnNewline('', 0);
      expect(result, isNull);
      ec.dispose();
    });

    test('does not throw at offset 0 on non-empty text', () {
      final ec = EditorController();
      expect(() => ec.continueListOnNewline('- item', 0), returnsNormally);
      ec.dispose();
    });

    test('does not throw at offset equal to string length', () {
      final ec = EditorController();
      expect(() => ec.continueListOnNewline('- item', 6), returnsNormally);
      ec.dispose();
    });

    // ---- EC-07 purity: no controller mutation ----

    test('does NOT mutate controller text on list line', () {
      final ec = EditorController(text: 'original');
      ec.continueListOnNewline('- item', 6);
      expect(
        ec.text,
        'original',
        reason: 'continueListOnNewline is pure — controller.text unchanged',
      );
      ec.dispose();
    });

    test('does NOT mutate controller selection', () {
      final ec = EditorController(text: '- item');
      ec.selection = const TextSelection.collapsed(offset: 3);
      final selBefore = ec.selection;
      ec.continueListOnNewline('- item', 6);
      expect(
        ec.selection,
        selBefore,
        reason: 'continueListOnNewline is pure — selection unchanged',
      );
      ec.dispose();
    });

    test('does NOT call notifyListeners', () {
      final ec = EditorController(text: '- item');
      var notified = false;
      ec.addListener(() => notified = true);
      ec.continueListOnNewline('- item', 6);
      expect(
        notified,
        isFalse,
        reason: 'EC-07: pure delegation must not notify listeners',
      );
      ec.dispose();
    });

    // ---- Ordered list delegation ----

    test('delegates ordered list continuation (numeric +1)', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('1. first', 8);
      expect(result, isNotNull);
      expect(result!.text, '1. first\n2. ');
      expect(result.selection.isCollapsed, isTrue);
      expect(result.selection.baseOffset, 12);
      ec.dispose();
    });

    test('returns null when ordered alpha ceiling reached (z.)', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('z. last', 7);
      expect(result, isNull);
      ec.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // M3 — indentSelection (EC-07, spec §5.3)
  // ---------------------------------------------------------------------------
  group('indentSelection (M3 — delegation, EC-07)', () {
    test('returns a record with text and selection for a bullet line', () {
      final ec = EditorController(text: '- item');
      ec.selection = const TextSelection.collapsed(offset: 6);
      final result = ec.indentSelection();
      expect(result.text, '  - item');
      expect(result.selection, isA<TextSelection>());
      ec.dispose();
    });

    test('collapsed selection (selStart == selExtent) delegates correctly', () {
      final ec = EditorController(text: 'plain text');
      ec.selection = const TextSelection.collapsed(offset: 5);
      // Should not throw and returns a valid record.
      expect(() => ec.indentSelection(), returnsNormally);
      final result = ec.indentSelection();
      // Non-list line → tab prefix.
      expect(result.text, '\tplain text');
      ec.dispose();
    });

    test('does NOT mutate controller text', () {
      final ec = EditorController(text: '- item');
      ec.selection = const TextSelection.collapsed(offset: 6);
      ec.indentSelection();
      expect(ec.text, '- item');
      ec.dispose();
    });

    test('does NOT mutate controller selection', () {
      final ec = EditorController(text: '- item');
      ec.selection = const TextSelection.collapsed(offset: 6);
      final selBefore = ec.selection;
      ec.indentSelection();
      expect(ec.selection, selBefore);
      ec.dispose();
    });

    test('does NOT call notifyListeners', () {
      final ec = EditorController(text: '- item');
      ec.selection = const TextSelection.collapsed(offset: 6);
      var notified = false;
      ec.addListener(() => notified = true);
      ec.indentSelection();
      expect(notified, isFalse, reason: 'EC-07: pure delegation');
      ec.dispose();
    });

    test(
      'returned selection uses baseOffset == selStart and extentOffset == selExtent',
      () {
        // Verify adaption: IndentResult.selStart → selection.baseOffset,
        //                   IndentResult.selExtent → selection.extentOffset.
        final ec = EditorController(text: '- item');
        ec.selection = const TextSelection.collapsed(offset: 6);
        final result = ec.indentSelection();
        // After indent "  - item", caret should shift by 2 (unit = "  ").
        expect(result.selection.baseOffset, 8);
        expect(result.selection.extentOffset, 8);
        ec.dispose();
      },
    );

    test(
      'does NOT touch highlightRanges or currentMatchIndex (EC-26 seam guard)',
      () {
        final ec = EditorController(text: '- item');
        ec.selection = const TextSelection.collapsed(offset: 6);
        const range = TextRange(start: 0, end: 3);
        ec.highlightRanges = [range];
        ec.currentMatchIndex = 0;
        var notifyCount = 0;
        ec.addListener(() => notifyCount++);

        // Reset counter after the above assignments which each call notifyListeners.
        notifyCount = 0;
        ec.indentSelection();

        expect(ec.highlightRanges, [
          range,
        ], reason: 'highlightRanges unchanged');
        expect(ec.currentMatchIndex, 0, reason: 'currentMatchIndex unchanged');
        expect(notifyCount, 0, reason: 'no notify from indentSelection');
        ec.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // M3 — outdentSelection (EC-07, spec §5.3)
  // ---------------------------------------------------------------------------
  group('outdentSelection (M3 — delegation, EC-07)', () {
    test(
      'returns a record with text and selection for an indented bullet line',
      () {
        final ec = EditorController(text: '  - item');
        ec.selection = const TextSelection.collapsed(offset: 8);
        final result = ec.outdentSelection();
        expect(result.text, '- item');
        ec.dispose();
      },
    );

    test('no-op on a line at column 0 (no leading unit)', () {
      final ec = EditorController(text: '- item');
      ec.selection = const TextSelection.collapsed(offset: 6);
      final result = ec.outdentSelection();
      // "- item" has no leading indent unit → text unchanged.
      expect(result.text, '- item');
      ec.dispose();
    });

    test('does NOT mutate controller text', () {
      final ec = EditorController(text: '  - item');
      ec.selection = const TextSelection.collapsed(offset: 8);
      ec.outdentSelection();
      expect(ec.text, '  - item');
      ec.dispose();
    });

    test('does NOT mutate controller selection', () {
      final ec = EditorController(text: '  - item');
      ec.selection = const TextSelection.collapsed(offset: 8);
      final selBefore = ec.selection;
      ec.outdentSelection();
      expect(ec.selection, selBefore);
      ec.dispose();
    });

    test('does NOT call notifyListeners', () {
      final ec = EditorController(text: '  - item');
      ec.selection = const TextSelection.collapsed(offset: 8);
      var notified = false;
      ec.addListener(() => notified = true);
      ec.outdentSelection();
      expect(notified, isFalse, reason: 'EC-07: pure delegation');
      ec.dispose();
    });

    test('collapsed selection delegates correctly (no throw)', () {
      final ec = EditorController(text: '\tplain');
      ec.selection = const TextSelection.collapsed(offset: 6);
      expect(() => ec.outdentSelection(), returnsNormally);
      final result = ec.outdentSelection();
      expect(result.text, 'plain');
      ec.dispose();
    });

    test(
      'does NOT touch highlightRanges or currentMatchIndex (EC-26 seam guard)',
      () {
        final ec = EditorController(text: '  - item');
        ec.selection = const TextSelection.collapsed(offset: 8);
        const range = TextRange(start: 0, end: 3);
        ec.highlightRanges = [range];
        ec.currentMatchIndex = 1;
        var notifyCount = 0;
        ec.addListener(() => notifyCount++);

        notifyCount = 0;
        ec.outdentSelection();

        expect(ec.highlightRanges, [
          range,
        ], reason: 'highlightRanges unchanged');
        expect(ec.currentMatchIndex, 1, reason: 'currentMatchIndex unchanged');
        expect(notifyCount, 0, reason: 'no notify from outdentSelection');
        ec.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // EC-26 — Find-replace seam regression: buildTextSpan / highlightRanges /
  //          currentMatchIndex behaviour after M3 additions.
  //
  // REVISED for M4: the delegation assertion has been updated from
  // "returns super span unchanged" to "calls super for base style/composing
  // AND layers highlight backgrounds on match runs". The EC-10 no-selection-
  // mutation invariants remain unchanged and stay green.
  // ---------------------------------------------------------------------------
  group('EC-26 — seam regression (M4 painting, M4 seams, EC-10 invariants)', () {
    // REVISED: buildTextSpan calls super (base style/composing preserved) AND
    // layers backgrounds on match runs when highlightRanges is non-empty.
    testWidgets(
      'buildTextSpan: super called for base style AND highlight backgrounds '
      'layered on match runs (EC-26 revised for M4)',
      (WidgetTester tester) async {
        final ec = EditorController(text: 'seam check');
        // Set a highlight range so M4 painting fires; secondaryContainer expected.
        ec.highlightRanges = [const TextRange(start: 0, end: 4)]; // "seam"
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final span = ec.buildTextSpan(
          context: ctx,
          style: null,
          withComposing: false,
        );

        // Base text from super must still be present (super called for base style).
        final buf = StringBuffer();
        void collect(InlineSpan s) {
          if (s is TextSpan) {
            if (s.text != null) buf.write(s.text);
            s.children?.forEach(collect);
          }
        }

        collect(span);
        expect(
          buf.toString(),
          contains('seam check'),
          reason:
              'super must be called so base text / composing decoration is present',
        );

        // The match run must carry secondaryContainer background (M4 layering).
        final cs = Theme.of(ctx).colorScheme;
        bool foundMatchBg = false;
        void findBg(InlineSpan s) {
          if (s is TextSpan) {
            if (s.text == 'seam' &&
                s.style?.backgroundColor == cs.secondaryContainer) {
              foundMatchBg = true;
            }
            s.children?.forEach(findBg);
          }
        }

        findBg(span);
        expect(
          foundMatchBg,
          isTrue,
          reason:
              'M4 must layer secondaryContainer background on non-current match '
              'run "seam" (EC-26 revised)',
        );

        ec.dispose();
      },
    );

    test(
      'highlightRanges assignment still does NOT mutate selection (EC-26)',
      () {
        final ec = EditorController(text: 'hello world');
        ec.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
        final selBefore = ec.selection;
        ec.highlightRanges = [const TextRange(start: 0, end: 3)];
        expect(ec.selection, selBefore);
        ec.dispose();
      },
    );

    test(
      'currentMatchIndex assignment still does NOT mutate selection (EC-26)',
      () {
        final ec = EditorController(text: 'hello world');
        ec.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
        final selBefore = ec.selection;
        ec.currentMatchIndex = 0;
        expect(ec.selection, selBefore);
        ec.dispose();
      },
    );
  });
}
