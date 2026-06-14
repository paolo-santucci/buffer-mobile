// Tests for EditorActions — TASK-04 (M3 Text Editor) + TASK-06 (M4 Find/Replace)
//                           + TASK-14 (M6 PasteIntent / DismissChromeIntent).
//
// TDD discipline: new TASK-14 tests written BEFORE implementation. Red-phase
// confirmed before adding PasteIntent/PasteAction/DismissChromeIntent/
// DismissChromeAction to editor_actions.dart.
//
// Spec refs: FR-08, FR-14, FR-15, §5.4(c), §4.1 (M3)
//            FR-21, §5.3 intents (M4)
//            FR-M6-20, FR-M6-21, FR-M6-22, EC-11, §5.1-g (M6)

import 'package:buffer/presentation/editor/editor_actions.dart';
import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
// Call-recording helpers for find Actions
// (Actions take explicit VoidCallbacks / named callbacks — no WidgetRef,
// no concrete FindNotifier import — keeping them testable without a tree)
// ---------------------------------------------------------------------------

/// Records calls to findProvider.startSearch({required int entryOffset}).
class _StartSearchCapture {
  int callCount = 0;
  int? lastOffset;

  void call({required int entryOffset}) {
    callCount++;
    lastOffset = entryOffset;
  }
}

/// Records calls to a single no-arg verb (next / previous / close).
class _VerbCapture {
  int callCount = 0;

  void call() => callCount++;
}

// ---------------------------------------------------------------------------
// Tests — M3 intents/actions (existing; keep intact)
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

  // =========================================================================
  // M4 Find/Replace Intents & Actions (TASK-06, FR-21, spec §5.3 intents)
  // =========================================================================

  // -------------------------------------------------------------------------
  // Intent type identity — each intent is a distinct concrete Intent subclass
  // recognised by its paired Action (FR-21 / spec §5.3)
  // -------------------------------------------------------------------------
  group('Find intents — type identity', () {
    test('OpenFindIntent is a concrete Intent subclass', () {
      expect(const OpenFindIntent(), isA<Intent>());
    });

    test('FindNextIntent is a concrete Intent subclass', () {
      expect(const FindNextIntent(), isA<Intent>());
    });

    test('FindPrevIntent is a concrete Intent subclass', () {
      expect(const FindPrevIntent(), isA<Intent>());
    });

    test('ToggleReplaceIntent is a concrete Intent subclass', () {
      expect(const ToggleReplaceIntent(), isA<Intent>());
    });

    test('CloseFindIntent is a concrete Intent subclass', () {
      expect(const CloseFindIntent(), isA<Intent>());
    });

    test('OpenFindIntent, FindNextIntent, FindPrevIntent, ToggleReplaceIntent, '
        'CloseFindIntent are all distinct runtime types', () {
      expect(
        const OpenFindIntent().runtimeType,
        isNot(equals(const FindNextIntent().runtimeType)),
      );
      expect(
        const FindNextIntent().runtimeType,
        isNot(equals(const FindPrevIntent().runtimeType)),
      );
      expect(
        const FindPrevIntent().runtimeType,
        isNot(equals(const ToggleReplaceIntent().runtimeType)),
      );
      expect(
        const ToggleReplaceIntent().runtimeType,
        isNot(equals(const CloseFindIntent().runtimeType)),
      );
    });

    test('find intent const constructors produce identical instances', () {
      expect(identical(const OpenFindIntent(), const OpenFindIntent()), isTrue);
      expect(identical(const FindNextIntent(), const FindNextIntent()), isTrue);
      expect(identical(const FindPrevIntent(), const FindPrevIntent()), isTrue);
      expect(
        identical(const ToggleReplaceIntent(), const ToggleReplaceIntent()),
        isTrue,
      );
      expect(
        identical(const CloseFindIntent(), const CloseFindIntent()),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // OpenFindIntent → OpenFindAction
  // Invokes findProvider.startSearch(entryOffset) with the caret offset
  // captured from the controller (FR-21, spec §5.3).
  // -------------------------------------------------------------------------
  group('OpenFindAction', () {
    late _FakeController controller;
    late _StartSearchCapture startSearch;
    late OpenFindAction action;

    setUp(() {
      controller = _FakeController(text: 'hello world');
      controller.selection = const TextSelection.collapsed(offset: 5);
      startSearch = _StartSearchCapture();
      action = OpenFindAction(
        controller: controller,
        startSearch: startSearch.call,
      );
    });

    test('is enabled for OpenFindIntent', () {
      expect(action.isEnabled(const OpenFindIntent()), isTrue);
    });

    test('invokes findProvider.startSearch with current caret offset', () {
      action.invoke(const OpenFindIntent());
      expect(startSearch.callCount, 1);
      expect(startSearch.lastOffset, 5);
    });

    test('caret offset reflects controller.selection.baseOffset', () {
      controller.selection = const TextSelection.collapsed(offset: 7);
      action.invoke(const OpenFindIntent());
      expect(startSearch.lastOffset, 7);
    });

    test('startSearch called exactly once per invoke', () {
      action.invoke(const OpenFindIntent());
      action.invoke(const OpenFindIntent());
      expect(startSearch.callCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // FindNextIntent → FindNextAction
  // Invokes findProvider.next() exactly once; no divergent second path
  // (FR-21 single-path convergence, EC-16).
  // -------------------------------------------------------------------------
  group('FindNextAction', () {
    late _VerbCapture nextCapture;
    late FindNextAction action;

    setUp(() {
      nextCapture = _VerbCapture();
      action = FindNextAction(next: nextCapture.call);
    });

    test('is enabled for FindNextIntent', () {
      expect(action.isEnabled(const FindNextIntent()), isTrue);
    });

    test('invokes findProvider.next() exactly once', () {
      action.invoke(const FindNextIntent());
      expect(nextCapture.callCount, 1);
    });

    test('next called once per invoke (no duplicate calls)', () {
      action.invoke(const FindNextIntent());
      action.invoke(const FindNextIntent());
      expect(nextCapture.callCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // FindPrevIntent → FindPrevAction
  // Invokes findProvider.previous() exactly once; no divergent second path
  // (FR-21 single-path convergence).
  // -------------------------------------------------------------------------
  group('FindPrevAction', () {
    late _VerbCapture prevCapture;
    late FindPrevAction action;

    setUp(() {
      prevCapture = _VerbCapture();
      action = FindPrevAction(previous: prevCapture.call);
    });

    test('is enabled for FindPrevIntent', () {
      expect(action.isEnabled(const FindPrevIntent()), isTrue);
    });

    test('invokes findProvider.previous() exactly once', () {
      action.invoke(const FindPrevIntent());
      expect(prevCapture.callCount, 1);
    });

    test('previous called once per invoke (no duplicate calls)', () {
      action.invoke(const FindPrevIntent());
      action.invoke(const FindPrevIntent());
      expect(prevCapture.callCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // ToggleReplaceIntent → ToggleReplaceAction
  // Toggles the replace row via a screen-owned VoidCallback (UI-row concern
  // per spec §5.3 — the replace-row visibility is owned by FindSearchBar,
  // not by the find provider).
  // -------------------------------------------------------------------------
  group('ToggleReplaceAction', () {
    test('is enabled for ToggleReplaceIntent', () {
      int callCount = 0;
      final action = ToggleReplaceAction(onToggle: () => callCount++);
      expect(action.isEnabled(const ToggleReplaceIntent()), isTrue);
    });

    test('invokes the onToggle callback exactly once per invoke', () {
      int callCount = 0;
      final action = ToggleReplaceAction(onToggle: () => callCount++);
      action.invoke(const ToggleReplaceIntent());
      expect(callCount, 1);
    });

    test('invokes onToggle a second time on second invoke', () {
      int callCount = 0;
      final action = ToggleReplaceAction(onToggle: () => callCount++);
      action.invoke(const ToggleReplaceIntent());
      action.invoke(const ToggleReplaceIntent());
      expect(callCount, 2);
    });

    test('does NOT require findProvider — VoidCallback only', () {
      // ToggleReplaceAction only holds the VoidCallback; its construction
      // does not require a notifier — verifying it compiles and invokes
      // without a notifier is sufficient.
      bool toggled = false;
      final action = ToggleReplaceAction(onToggle: () => toggled = true);
      action.invoke(const ToggleReplaceIntent());
      expect(toggled, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // CloseFindIntent → CloseFindAction
  // Invokes findProvider.close() on activation (FR-21, FR-20).
  // -------------------------------------------------------------------------
  group('CloseFindAction', () {
    late _VerbCapture closeCapture;
    late CloseFindAction action;

    setUp(() {
      closeCapture = _VerbCapture();
      action = CloseFindAction(close: closeCapture.call);
    });

    test('is enabled for CloseFindIntent', () {
      expect(action.isEnabled(const CloseFindIntent()), isTrue);
    });

    test('invokes findProvider.close() exactly once', () {
      action.invoke(const CloseFindIntent());
      expect(closeCapture.callCount, 1);
    });

    test('close called once per invoke (no duplicate calls)', () {
      action.invoke(const CloseFindIntent());
      action.invoke(const CloseFindIntent());
      expect(closeCapture.callCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Single-path convergence (FR-21 / EC-16) — hardware shortcut Actions
  // call the same findProvider verbs the on-screen buttons call.
  // Testable without a widget tree: Actions take explicit callbacks that
  // bind to findProvider.startSearch / .next / .previous / .close at the
  // BufferScreen wiring site (TASK-07); no divergent second codepath exists.
  // -------------------------------------------------------------------------
  group('Single-path convergence (FR-21 / EC-16)', () {
    test('all five find Actions operate without a widget tree '
        '— zero widget infrastructure', () {
      final controller = _FakeController(text: 'some text');
      controller.selection = const TextSelection.collapsed(offset: 4);

      final startSearch = _StartSearchCapture();
      final nextVerb = _VerbCapture();
      final prevVerb = _VerbCapture();
      final closeVerb = _VerbCapture();
      int toggleCount = 0;

      final openAction = OpenFindAction(
        controller: controller,
        startSearch: startSearch.call,
      );
      final nextAction = FindNextAction(next: nextVerb.call);
      final prevAction = FindPrevAction(previous: prevVerb.call);
      final closeAction = CloseFindAction(close: closeVerb.call);
      final toggleAction = ToggleReplaceAction(onToggle: () => toggleCount++);

      openAction.invoke(const OpenFindIntent());
      nextAction.invoke(const FindNextIntent());
      prevAction.invoke(const FindPrevIntent());
      closeAction.invoke(const CloseFindIntent());
      toggleAction.invoke(const ToggleReplaceIntent());

      expect(startSearch.callCount, 1);
      expect(startSearch.lastOffset, 4);
      expect(nextVerb.callCount, 1);
      expect(prevVerb.callCount, 1);
      expect(closeVerb.callCount, 1);
      expect(toggleCount, 1);
    });
  });

  // =========================================================================
  // M6 — PasteIntent / PasteAction (TASK-14, FR-M6-20, EC-11, §5.1-g)
  // =========================================================================
  //
  // The Clipboard platform channel is stubbed via
  // TestDefaultBinaryMessengerBinding so no real clipboard is accessed.
  // PasteAction takes (controller, apply) — identical dependency-pair
  // pattern as EditorIndentAction. It reads getData synchronously in tests
  // by stubbing the MethodChannel codec.
  //
  // Stub helper: registers a handler on BasicMessageChannel used by
  // Clipboard.getData that returns the supplied ClipboardData map, then
  // cleans up after the test.

  // ---------------------------------------------------------------------------
  // Clipboard stub utilities
  // ---------------------------------------------------------------------------

  /// Registers a fake Clipboard.getData response on the platform channel.
  ///
  /// [data] — the text to return, or null to simulate an empty clipboard.
  /// Returns a teardown callback; call it (or pass to addTearDown) to
  /// remove the handler after the test.
  void Function() stubClipboard(String? data) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'Clipboard.getData') {
            return data == null ? null : {'text': data};
          }
          return null;
        });
    return () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    };
  }

  // -------------------------------------------------------------------------
  // PasteIntent — type identity
  // -------------------------------------------------------------------------
  group('PasteIntent — type identity', () {
    test('PasteIntent is a concrete Intent subclass', () {
      expect(const PasteIntent(), isA<Intent>());
    });

    test('PasteIntent const constructor produces identical instances', () {
      expect(identical(const PasteIntent(), const PasteIntent()), isTrue);
    });

    test('PasteIntent is distinct from all M4 intent runtime types', () {
      expect(
        const PasteIntent().runtimeType,
        isNot(equals(const OpenFindIntent().runtimeType)),
      );
      expect(
        const PasteIntent().runtimeType,
        isNot(equals(const CloseFindIntent().runtimeType)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // PasteAction — clipboard has data → insert at caret via apply callback
  //
  // Uses testWidgets because PasteAction.invoke is async (Clipboard.getData
  // returns a Future) and we need a WidgetTester pump to drive the async call.
  // -------------------------------------------------------------------------
  group('PasteAction — clipboard has data (FR-M6-20, EC-11)', () {
    testWidgets(
      'inserts clipboard text at caret and forwards to apply callback',
      (tester) async {
        final teardown = stubClipboard('pasted');
        addTearDown(teardown);

        final controller = _FakeController(text: 'hello world');
        // caret at offset 5 (between 'hello' and ' world')
        controller.selection = const TextSelection.collapsed(offset: 5);

        ({String text, TextSelection selection})? applied;
        final action = PasteAction(
          controller: controller,
          apply: (r) => applied = r,
        );

        action.invoke(const PasteIntent());
        await tester.pump();

        expect(applied, isNotNull);
        expect(applied!.text, 'hellopasted world');
        expect(applied!.selection.baseOffset, 11); // 5 + 'pasted'.length
        expect(applied!.selection.isCollapsed, isTrue);
      },
    );

    testWidgets('Clipboard.getData is called exactly once per invoke', (
      tester,
    ) async {
      int callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.getData') {
              callCount++;
              return {'text': 'x'};
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final controller = _FakeController(text: 'abc');
      controller.selection = const TextSelection.collapsed(offset: 3);
      final action = PasteAction(controller: controller, apply: (_) {});

      action.invoke(const PasteIntent());
      await tester.pump();

      expect(callCount, 1);
    });

    testWidgets(
      'routes through the single write path — apply called exactly once',
      (tester) async {
        final teardown = stubClipboard('data');
        addTearDown(teardown);

        final controller = _FakeController(text: 'text');
        controller.selection = const TextSelection.collapsed(offset: 4);
        int applyCount = 0;
        final action = PasteAction(
          controller: controller,
          apply: (_) => applyCount++,
        );

        action.invoke(const PasteIntent());
        await tester.pump();

        expect(applyCount, 1);
      },
    );

    testWidgets('is enabled for PasteIntent', (tester) async {
      final teardown = stubClipboard('anything');
      addTearDown(teardown);

      final controller = _FakeController(text: '');
      controller.selection = const TextSelection.collapsed(offset: 0);
      final action = PasteAction(controller: controller, apply: (_) {});

      expect(action.isEnabled(const PasteIntent()), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // PasteAction — clipboard null / empty → no-op, no exception (EC-11)
  // -------------------------------------------------------------------------
  group('PasteAction — null clipboard (EC-11 no-op)', () {
    testWidgets('null clipboard data → apply NOT called, no exception', (
      tester,
    ) async {
      final teardown = stubClipboard(null);
      addTearDown(teardown);

      final controller = _FakeController(text: 'original');
      controller.selection = const TextSelection.collapsed(offset: 8);
      ({String text, TextSelection selection})? applied;
      final action = PasteAction(
        controller: controller,
        apply: (r) => applied = r,
      );

      // Must not throw.
      action.invoke(const PasteIntent());
      await tester.pump();

      expect(applied, isNull, reason: 'no-op: apply must not be called');
    });

    testWidgets('empty-string clipboard data → apply NOT called', (
      tester,
    ) async {
      final teardown = stubClipboard('');
      addTearDown(teardown);

      final controller = _FakeController(text: 'original');
      controller.selection = const TextSelection.collapsed(offset: 3);
      ({String text, TextSelection selection})? applied;
      final action = PasteAction(
        controller: controller,
        apply: (r) => applied = r,
      );

      action.invoke(const PasteIntent());
      await tester.pump();

      expect(applied, isNull, reason: 'empty clipboard → no-op');
    });
  });

  // =========================================================================
  // M6 — DismissChromeIntent / DismissChromeAction
  //      (TASK-14, FR-M6-22, §5.1-g)
  // =========================================================================

  // -------------------------------------------------------------------------
  // DismissChromeIntent — type identity
  // -------------------------------------------------------------------------
  group('DismissChromeIntent — type identity', () {
    test('DismissChromeIntent is a concrete Intent subclass', () {
      expect(const DismissChromeIntent(), isA<Intent>());
    });

    test(
      'DismissChromeIntent const constructor produces identical instances',
      () {
        expect(
          identical(const DismissChromeIntent(), const DismissChromeIntent()),
          isTrue,
        );
      },
    );

    test(
      'DismissChromeIntent is distinct from PasteIntent and all M4 intents',
      () {
        expect(
          const DismissChromeIntent().runtimeType,
          isNot(equals(const PasteIntent().runtimeType)),
        );
        expect(
          const DismissChromeIntent().runtimeType,
          isNot(equals(const CloseFindIntent().runtimeType)),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // DismissChromeAction — calls the onDismiss callback
  //
  // Design: explicit-dependency pattern (VoidCallback), identical to
  // CloseFindAction. No WidgetRef / Riverpod import; the callback binds to
  // ref.read(chromeVisibilityProvider.notifier).onTextChanged() at the
  // BufferScreen wiring site (TASK-12), setting visibility to false.
  // -------------------------------------------------------------------------
  group('DismissChromeAction (FR-M6-22)', () {
    test('is enabled for DismissChromeIntent', () {
      int callCount = 0;
      final action = DismissChromeAction(onDismiss: () => callCount++);
      expect(action.isEnabled(const DismissChromeIntent()), isTrue);
    });

    test('calls onDismiss callback exactly once per invoke', () {
      int callCount = 0;
      final action = DismissChromeAction(onDismiss: () => callCount++);
      action.invoke(const DismissChromeIntent());
      expect(callCount, 1);
    });

    test('calls onDismiss a second time on second invoke', () {
      int callCount = 0;
      final action = DismissChromeAction(onDismiss: () => callCount++);
      action.invoke(const DismissChromeIntent());
      action.invoke(const DismissChromeIntent());
      expect(callCount, 2);
    });

    test('does NOT require WidgetRef — VoidCallback only', () {
      // DismissChromeAction only holds the VoidCallback; its construction
      // does not require a notifier.
      bool dismissed = false;
      final action = DismissChromeAction(onDismiss: () => dismissed = true);
      action.invoke(const DismissChromeIntent());
      expect(dismissed, isTrue);
    });
  });

  // =========================================================================
  // M6 regression — existing M4 intents unchanged after TASK-14 additions
  // =========================================================================
  group('M4 intents unchanged after M6 additions (regression)', () {
    test('CloseFindIntent still concrete Intent subclass', () {
      expect(const CloseFindIntent(), isA<Intent>());
    });

    test('OpenFindIntent still concrete Intent subclass', () {
      expect(const OpenFindIntent(), isA<Intent>());
    });

    test('CloseFindAction still invokes close callback', () {
      int closeCount = 0;
      final action = CloseFindAction(close: () => closeCount++);
      action.invoke(const CloseFindIntent());
      expect(closeCount, 1);
    });

    test('all M4 intent types are distinct from M6 intent types', () {
      final m4Types = [
        const OpenFindIntent().runtimeType,
        const FindNextIntent().runtimeType,
        const FindPrevIntent().runtimeType,
        const ToggleReplaceIntent().runtimeType,
        const CloseFindIntent().runtimeType,
      ];
      final m6Types = [
        const PasteIntent().runtimeType,
        const DismissChromeIntent().runtimeType,
      ];
      for (final m4 in m4Types) {
        for (final m6 in m6Types) {
          expect(
            m4,
            isNot(equals(m6)),
            reason: '$m4 must be distinct from $m6',
          );
        }
      }
    });
  });
}
