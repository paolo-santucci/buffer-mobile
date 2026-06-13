// Tests for EditorController — the single unified TextEditingController subclass
// shared by M3 (text-editor) and M4 (find-replace).
//
// Spec refs: FR-15, EC-07, EC-10, NFR-09
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
  // EC-07 — continueListOnNewline is pure: inserts "\n" at caretOffset,
  //          does not throw, does not mutate the controller.
  // ---------------------------------------------------------------------------
  group('continueListOnNewline (EC-07 — pure seam)', () {
    test('inserts a plain newline at the given offset', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('hello', 5);
      expect(
        result,
        'hello\n',
        reason: 'a plain "\\n" is inserted at offset 5 (end of "hello")',
      );
      ec.dispose();
    });

    test('inserts newline in the middle of the string', () {
      final ec = EditorController();
      final result = ec.continueListOnNewline('hello', 2);
      expect(result, 'he\nllo');
      ec.dispose();
    });

    test('does not mutate the controller text', () {
      final ec = EditorController(text: 'original');
      ec.continueListOnNewline('hello', 5);
      expect(
        ec.text,
        'original',
        reason: 'continueListOnNewline is pure — controller must be unchanged',
      );
      ec.dispose();
    });

    test('does not mutate the controller selection', () {
      final ec = EditorController(text: 'hello');
      ec.selection = const TextSelection.collapsed(offset: 3);
      final selectionBefore = ec.selection;

      ec.continueListOnNewline('hello', 5);

      expect(
        ec.selection,
        selectionBefore,
        reason: 'continueListOnNewline is pure — selection must be unchanged',
      );
      ec.dispose();
    });

    test('does not throw at offset 0', () {
      final ec = EditorController();
      expect(() => ec.continueListOnNewline('hello', 0), returnsNormally);
      ec.dispose();
    });

    test('does not throw at offset equal to string length', () {
      final ec = EditorController();
      expect(() => ec.continueListOnNewline('hello', 5), returnsNormally);
      ec.dispose();
    });
  });
}
