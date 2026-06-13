// Tests for EditorActions — TASK-04 (M3 Text Editor).
//
// TDD discipline: these tests are written BEFORE the implementation file
// (lib/presentation/editor/editor_actions.dart) exists. They must fail
// (red) on first run, then pass (green) after implementation.
//
// Spec refs: FR-08, FR-14, FR-15, §5.4(c), §4.1

import 'package:buffer/presentation/editor/editor_actions.dart';
import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake controller — captures calls without exercising real helpers
// ---------------------------------------------------------------------------

/// A fake [EditorController] that records method calls and returns
/// pre-programmed results, keeping tests hermetic.
class _FakeController extends EditorController {
  _FakeController({String text = ''}) : super(text: text);

  // Programmed responses
  ({String text, TextSelection selection})? continueResult;
  ({String text, TextSelection selection}) indentResult = (
    text: '',
    selection: const TextSelection.collapsed(offset: 0),
  );
  ({String text, TextSelection selection}) outdentResult = (
    text: '',
    selection: const TextSelection.collapsed(offset: 0),
  );

  // Call tracking
  int continueCallCount = 0;
  int indentCallCount = 0;
  int outdentCallCount = 0;

  String? lastContinueText;
  int? lastContinueCaret;

  @override
  ({String text, TextSelection selection})? continueListOnNewline(
    String currentText,
    int caretOffset,
  ) {
    continueCallCount++;
    lastContinueText = currentText;
    lastContinueCaret = caretOffset;
    return continueResult;
  }

  @override
  ({String text, TextSelection selection}) indentSelection() {
    indentCallCount++;
    return indentResult;
  }

  @override
  ({String text, TextSelection selection}) outdentSelection() {
    outdentCallCount++;
    return outdentResult;
  }
}

// ---------------------------------------------------------------------------
// Helper — capture the apply callback argument
// ---------------------------------------------------------------------------

class _ApplyCapture {
  ({String text, TextSelection selection})? captured;

  void call(({String text, TextSelection selection}) result) {
    captured = result;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ContinueListIntent', () {
    test('is a concrete Intent subclass', () {
      expect(const ContinueListIntent(), isA<Intent>());
    });

    test('const constructor', () {
      const a = ContinueListIntent();
      const b = ContinueListIntent();
      // Equality for const value objects
      expect(identical(a, b), isTrue);
    });
  });

  group('IndentIntent', () {
    test('is a concrete Intent subclass', () {
      expect(const IndentIntent(), isA<Intent>());
    });
  });

  group('OutdentIntent', () {
    test('is a concrete Intent subclass', () {
      expect(const OutdentIntent(), isA<Intent>());
    });
  });

  // -------------------------------------------------------------------------
  // IndentIntent → Action
  // -------------------------------------------------------------------------
  group('IndentAction', () {
    late _FakeController controller;
    late _ApplyCapture capture;
    late EditorIndentAction action;

    setUp(() {
      controller = _FakeController(text: '- item');
      controller.selection = const TextSelection.collapsed(offset: 6);

      final expectedResult = (
        text: '  - item',
        selection: const TextSelection.collapsed(offset: 8),
      );
      controller.indentResult = expectedResult;

      capture = _ApplyCapture();
      action = EditorIndentAction(controller: controller, apply: capture.call);
    });

    test('invokes EditorController.indentSelection()', () {
      action.invoke(const IndentIntent());
      expect(controller.indentCallCount, 1);
    });

    test('forwards indentSelection result to apply callback', () {
      action.invoke(const IndentIntent());
      expect(capture.captured, isNotNull);
      expect(capture.captured!.text, '  - item');
      expect(capture.captured!.selection.baseOffset, 8);
    });

    test('does NOT call outdentSelection or continueListOnNewline', () {
      action.invoke(const IndentIntent());
      expect(controller.outdentCallCount, 0);
      expect(controller.continueCallCount, 0);
    });

    test('apply is called exactly once per invoke', () {
      int callCount = 0;
      final countingAction = EditorIndentAction(
        controller: controller,
        apply: (_) => callCount++,
      );
      countingAction.invoke(const IndentIntent());
      expect(callCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  // OutdentIntent → Action
  // -------------------------------------------------------------------------
  group('OutdentAction', () {
    late _FakeController controller;
    late _ApplyCapture capture;
    late EditorOutdentAction action;

    setUp(() {
      controller = _FakeController(text: '  - item');
      controller.selection = const TextSelection.collapsed(offset: 8);

      controller.outdentResult = (
        text: '- item',
        selection: const TextSelection.collapsed(offset: 6),
      );

      capture = _ApplyCapture();
      action = EditorOutdentAction(controller: controller, apply: capture.call);
    });

    test('invokes EditorController.outdentSelection()', () {
      action.invoke(const OutdentIntent());
      expect(controller.outdentCallCount, 1);
    });

    test('forwards outdentSelection result to apply callback', () {
      action.invoke(const OutdentIntent());
      expect(capture.captured, isNotNull);
      expect(capture.captured!.text, '- item');
      expect(capture.captured!.selection.baseOffset, 6);
    });

    test('does NOT call indentSelection or continueListOnNewline', () {
      action.invoke(const OutdentIntent());
      expect(controller.indentCallCount, 0);
      expect(controller.continueCallCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  // ContinueListIntent → Action — non-null path
  // -------------------------------------------------------------------------
  group('ContinueListAction — non-null continuation', () {
    late _FakeController controller;
    late _ApplyCapture capture;
    late EditorContinueListAction action;

    setUp(() {
      controller = _FakeController(text: '- item');
      controller.selection = const TextSelection.collapsed(offset: 6);

      // continueListOnNewline returns a non-null result
      controller.continueResult = (
        text: '- item\n- ',
        selection: const TextSelection.collapsed(offset: 9),
      );

      capture = _ApplyCapture();
      action = EditorContinueListAction(
        controller: controller,
        apply: capture.call,
      );
    });

    test('invokes continueListOnNewline with current text and caret', () {
      action.invoke(const ContinueListIntent());
      expect(controller.continueCallCount, 1);
      expect(controller.lastContinueText, '- item');
      expect(controller.lastContinueCaret, 6);
    });

    test('apply callback IS called when result is non-null', () {
      action.invoke(const ContinueListIntent());
      expect(capture.captured, isNotNull);
      expect(capture.captured!.text, '- item\n- ');
      expect(capture.captured!.selection.baseOffset, 9);
    });
  });

  // -------------------------------------------------------------------------
  // ContinueListIntent → Action — null path (plain \n, apply NOT called)
  // -------------------------------------------------------------------------
  group('ContinueListAction — null continuation', () {
    late _FakeController controller;
    late _ApplyCapture capture;
    late EditorContinueListAction action;

    setUp(() {
      controller = _FakeController(text: 'plain text');
      controller.selection = const TextSelection.collapsed(offset: 10);

      // continueListOnNewline returns null (plain \n stays)
      controller.continueResult = null;

      capture = _ApplyCapture();
      action = EditorContinueListAction(
        controller: controller,
        apply: capture.call,
      );
    });

    test('apply callback is NOT called when result is null', () {
      action.invoke(const ContinueListIntent());
      expect(capture.captured, isNull);
    });

    test('continueListOnNewline IS called even when result is null', () {
      action.invoke(const ContinueListIntent());
      expect(controller.continueCallCount, 1);
    });

    test('apply is never called regardless of how many times invoke fires', () {
      action.invoke(const ContinueListIntent());
      action.invoke(const ContinueListIntent());
      expect(capture.captured, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // onIndent / onOutdent callbacks — FR-15 chrome-independence
  //
  // These run the indent/outdent path with NO widget/button in the tree.
  // A direct callback invocation indents/outdents the current line.
  // -------------------------------------------------------------------------
  group('onIndent/onOutdent chrome-independence (FR-15)', () {
    test('onIndent callback runs indent path with no widget tree', () {
      final controller = _FakeController(text: '- item');
      controller.selection = const TextSelection.collapsed(offset: 6);
      controller.indentResult = (
        text: '  - item',
        selection: const TextSelection.collapsed(offset: 8),
      );

      ({String text, TextSelection selection})? applied;

      // Build the callback surface — no widget tree involved
      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (r) => applied = r,
      );

      // Invoke indent with no button, no Shortcuts widget, no BuildContext
      callbacks.onIndent();

      expect(controller.indentCallCount, 1);
      expect(applied, isNotNull);
      expect(applied!.text, '  - item');
    });

    test('onOutdent callback runs outdent path with no widget tree', () {
      final controller = _FakeController(text: '  - item');
      controller.selection = const TextSelection.collapsed(offset: 8);
      controller.outdentResult = (
        text: '- item',
        selection: const TextSelection.collapsed(offset: 6),
      );

      ({String text, TextSelection selection})? applied;

      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (r) => applied = r,
      );

      callbacks.onOutdent();

      expect(controller.outdentCallCount, 1);
      expect(applied, isNotNull);
      expect(applied!.text, '- item');
    });

    test('onIndent does NOT trigger outdent', () {
      final controller = _FakeController(text: 'text');
      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.indentResult = (
        text: '\ttext',
        selection: const TextSelection.collapsed(offset: 5),
      );

      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (_) {},
      );

      callbacks.onIndent();

      expect(controller.outdentCallCount, 0);
    });

    test('onOutdent does NOT trigger indent', () {
      final controller = _FakeController(text: '\ttext');
      controller.selection = const TextSelection.collapsed(offset: 5);
      controller.outdentResult = (
        text: 'text',
        selection: const TextSelection.collapsed(offset: 4),
      );

      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (_) {},
      );

      callbacks.onOutdent();

      expect(controller.indentCallCount, 0);
    });

    test('multiple sequential onIndent invocations each call apply once', () {
      final controller = _FakeController(text: '- item');
      controller.selection = const TextSelection.collapsed(offset: 6);
      controller.indentResult = (
        text: '  - item',
        selection: const TextSelection.collapsed(offset: 8),
      );

      int applyCount = 0;
      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (_) => applyCount++,
      );

      callbacks.onIndent();
      callbacks.onIndent();

      expect(controller.indentCallCount, 2);
      expect(applyCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // EditorActionCallbacks exposes onIndent + onOutdent as typed functions
  // -------------------------------------------------------------------------
  group('EditorActionCallbacks shape', () {
    test('onIndent is a VoidCallback', () {
      final controller = _FakeController();
      controller.indentResult = (
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (_) {},
      );

      // If onIndent is a VoidCallback, it can be assigned to VoidCallback
      final VoidCallback fn = callbacks.onIndent;
      expect(fn, isA<VoidCallback>());
    });

    test('onOutdent is a VoidCallback', () {
      final controller = _FakeController();
      controller.outdentResult = (
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
      final callbacks = EditorActionCallbacks(
        controller: controller,
        apply: (_) {},
      );

      final VoidCallback fn = callbacks.onOutdent;
      expect(fn, isA<VoidCallback>());
    });
  });

  // -------------------------------------------------------------------------
  // Actions are wirable — confirm they accept the matching Intent type
  // (structural smoke for BufferScreen wiring in TASK-05)
  // -------------------------------------------------------------------------
  group('Action/Intent pairing', () {
    test('EditorIndentAction.isEnabled returns true for IndentIntent', () {
      final controller = _FakeController();
      controller.indentResult = (
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
      final action = EditorIndentAction(controller: controller, apply: (_) {});
      expect(action.isEnabled(const IndentIntent()), isTrue);
    });

    test('EditorOutdentAction.isEnabled returns true for OutdentIntent', () {
      final controller = _FakeController();
      controller.outdentResult = (
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
      final action = EditorOutdentAction(controller: controller, apply: (_) {});
      expect(action.isEnabled(const OutdentIntent()), isTrue);
    });

    test(
      'EditorContinueListAction.isEnabled returns true for ContinueListIntent',
      () {
        final controller = _FakeController();
        final action = EditorContinueListAction(
          controller: controller,
          apply: (_) {},
        );
        expect(action.isEnabled(const ContinueListIntent()), isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // No visible widget chrome — confirms no Navigator/Scaffold/Button in
  // the test tree (the test itself is the evidence: these are plain unit
  // tests with no testWidgets(), no WidgetTester, no widget pump)
  // -------------------------------------------------------------------------
  group('No visible chrome in actions/callbacks (FR-15, OQ-02)', () {
    test(
      'actions and callbacks exercise controller with zero widget infrastructure',
      () {
        // This entire test runs without a widget tree — no MaterialApp, no
        // Scaffold, no Button. That is the chrome-independence proof for FR-15.
        final controller = _FakeController(text: '+ task');
        controller.selection = const TextSelection.collapsed(offset: 6);
        controller.indentResult = (
          text: '  + task',
          selection: const TextSelection.collapsed(offset: 8),
        );
        controller.outdentResult = (
          text: '+ task',
          selection: const TextSelection.collapsed(offset: 6),
        );
        controller.continueResult = (
          text: '+ task\n+ ',
          selection: const TextSelection.collapsed(offset: 9),
        );

        final indentCapture = <({String text, TextSelection selection})>[];
        final outdentCapture = <({String text, TextSelection selection})>[];
        final continueCapture = <({String text, TextSelection selection})>[];

        final indentAction = EditorIndentAction(
          controller: controller,
          apply: indentCapture.add,
        );
        final outdentAction = EditorOutdentAction(
          controller: controller,
          apply: outdentCapture.add,
        );
        final continueAction = EditorContinueListAction(
          controller: controller,
          apply: continueCapture.add,
        );
        final callbacks = EditorActionCallbacks(
          controller: controller,
          apply: (_) {},
        );

        indentAction.invoke(const IndentIntent());
        outdentAction.invoke(const OutdentIntent());
        continueAction.invoke(const ContinueListIntent());
        callbacks.onIndent();
        callbacks.onOutdent();

        expect(indentCapture, hasLength(1));
        expect(outdentCapture, hasLength(1));
        expect(continueCapture, hasLength(1));
        expect(controller.indentCallCount, 2); // action + callback
        expect(controller.outdentCallCount, 2); // action + callback
        expect(controller.continueCallCount, 1);
      },
    );
  });
}
