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
  // FR-15 — buildTextSpan seam: returns TextSpan containing the editor text
  // ---------------------------------------------------------------------------
  group('buildTextSpan (FR-15 — seam exercised)', () {
    testWidgets(
      'returns a TextSpan whose flattened text contains the editor text',
      (WidgetTester tester) async {
        final ec = EditorController(text: 'hello');

        // buildTextSpan requires a BuildContext; pump a minimal widget to get one.
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final span = ec.buildTextSpan(
          context: capturedContext,
          style: null,
          withComposing: false,
        );

        // Flatten all text across the span tree.
        final buffer = StringBuffer();
        void collect(InlineSpan s) {
          if (s is TextSpan) {
            if (s.text != null) buffer.write(s.text);
            s.children?.forEach(collect);
          }
        }

        collect(span);
        expect(buffer.toString(), contains('hello'));
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
  //          currentMatchIndex are byte-for-byte unchanged from M1 baseline.
  //          These tests mirror the M1 EC-10 no-selection-mutation group and
  //          confirm they remain green after M3 additions.
  // ---------------------------------------------------------------------------
  group('EC-26 — seam regression (M4 seams unchanged by M3)', () {
    testWidgets('buildTextSpan still delegates to super after M3 changes', (
      WidgetTester tester,
    ) async {
      final ec = EditorController(text: 'seam check');
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
      final buf = StringBuffer();
      void collect(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          s.children?.forEach(collect);
        }
      }

      collect(span);
      expect(buf.toString(), contains('seam check'));
      ec.dispose();
    });

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
