// EditorActions — TASK-04 (M3 Text Editor).
//
// Defines the Intent/Action pairs for the three editor keyboard commands and
// the chrome-independent callback surface for indent/outdent (FR-15).
//
// Design: custom Action<T> subclasses (not CallbackAction) so each action
// carries an explicit (controller, apply) pair rather than a generic
// void Function(T) callback. This matches the spec's "SUPPLIED apply
// callback" pattern, keeps actions testable without a widget tree, and
// makes the apply pathway unambiguous at the call site in BufferScreen.
//
// This file holds NO visible widget chrome. The kDebugMode debug affordance
// and the Shortcuts key map live in buffer_screen.dart (TASK-05).
//
// Spec refs: FR-08, FR-14, FR-15, §5.4(c), §4.1

import 'package:buffer/presentation/editor/editor_controller.dart';
import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// Apply callback typedef
// ---------------------------------------------------------------------------

/// The callback type supplied by [BufferScreen] to each action.
///
/// The action invokes the corresponding [EditorController] delegation method
/// and forwards its result to this callback. [BufferScreen] applies the
/// result atomically via a re-entrancy-guarded [TextEditingValue] assignment
/// (TASK-05). The action itself never mutates the controller.
typedef EditorApplyCallback =
    void Function(({String text, TextSelection selection}) result);

// ---------------------------------------------------------------------------
// Intents
// ---------------------------------------------------------------------------

/// Fired by the hardware Return / KP_Enter / ISO_Enter key (§5.4c, FR-08).
///
/// The paired [EditorContinueListAction] calls
/// [EditorController.continueListOnNewline] and forwards the result to the
/// supplied apply callback only when the result is non-null.
@immutable
class ContinueListIntent extends Intent {
  const ContinueListIntent();
}

/// Fired by the hardware Tab key (§5.4c, FR-14).
///
/// The paired [EditorIndentAction] calls [EditorController.indentSelection]
/// and forwards the result to the supplied apply callback.
@immutable
class IndentIntent extends Intent {
  const IndentIntent();
}

/// Fired by the hardware Shift+Tab / ISO_Left_Tab key (§5.4c, FR-14).
///
/// The paired [EditorOutdentAction] calls [EditorController.outdentSelection]
/// and forwards the result to the supplied apply callback.
@immutable
class OutdentIntent extends Intent {
  const OutdentIntent();
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// Handles [ContinueListIntent].
///
/// Invokes [EditorController.continueListOnNewline] using the controller's
/// current text and collapsed caret offset, then calls [apply] ONLY when the
/// result is non-null. When the result is null the plain `\n` already
/// inserted by the text field is left in place.
///
/// PURE DELEGATION: this action does NOT mutate the controller. The atomic
/// [TextEditingValue] assignment is performed by the [apply] callback (owned
/// by [BufferScreen]).
class EditorContinueListAction extends Action<ContinueListIntent> {
  /// Creates an [EditorContinueListAction].
  ///
  /// [controller] — the single [EditorController] instance.
  /// [apply]      — the BufferScreen-supplied callback that applies the
  ///                continuation result atomically under a re-entrancy guard.
  EditorContinueListAction({required this.controller, required this.apply});

  /// The single unified [EditorController].
  final EditorController controller;

  /// The apply callback supplied by [BufferScreen].
  final EditorApplyCallback apply;

  @override
  void invoke(ContinueListIntent intent) {
    final result = controller.continueListOnNewline(
      controller.value.text,
      controller.value.selection.baseOffset,
    );
    if (result != null) {
      apply(result);
    }
    // When result is null the plain \n stays; apply is NOT called.
  }
}

/// Handles [IndentIntent].
///
/// Invokes [EditorController.indentSelection] and forwards the result to
/// [apply] unconditionally (indent always produces a result).
class EditorIndentAction extends Action<IndentIntent> {
  /// Creates an [EditorIndentAction].
  EditorIndentAction({required this.controller, required this.apply});

  /// The single unified [EditorController].
  final EditorController controller;

  /// The apply callback supplied by [BufferScreen].
  final EditorApplyCallback apply;

  @override
  void invoke(IndentIntent intent) {
    apply(controller.indentSelection());
  }
}

/// Handles [OutdentIntent].
///
/// Invokes [EditorController.outdentSelection] and forwards the result to
/// [apply] unconditionally.
class EditorOutdentAction extends Action<OutdentIntent> {
  /// Creates an [EditorOutdentAction].
  EditorOutdentAction({required this.controller, required this.apply});

  /// The single unified [EditorController].
  final EditorController controller;

  /// The apply callback supplied by [BufferScreen].
  final EditorApplyCallback apply;

  @override
  void invoke(OutdentIntent intent) {
    apply(controller.outdentSelection());
  }
}

// ---------------------------------------------------------------------------
// Chrome-independent callback surface (FR-15)
// ---------------------------------------------------------------------------

/// Exposes [onIndent] and [onOutdent] as plain [VoidCallback]s so any
/// future M6 chrome host can invoke indent/outdent with NO key event and NO
/// visible button in the widget tree (FR-15, OQ-02).
///
/// Both callbacks route through the same [EditorController] delegation
/// methods used by [EditorIndentAction] / [EditorOutdentAction] — the
/// path is identical whether triggered by a hardware key, a debug button,
/// or a future M6 toolbar.
///
/// This class holds NO widget state. Construct it alongside the actions and
/// pass [onIndent]/[onOutdent] to whatever chrome host needs them.
class EditorActionCallbacks {
  /// Creates an [EditorActionCallbacks] surface.
  ///
  /// [controller] — the single [EditorController] instance.
  /// [apply]      — the BufferScreen-supplied callback that applies the
  ///                result atomically.
  EditorActionCallbacks({
    required EditorController controller,
    required EditorApplyCallback apply,
  }) : onIndent = _makeIndent(controller, apply),
       onOutdent = _makeOutdent(controller, apply);

  /// Invokes [EditorController.indentSelection] and applies the result via
  /// the supplied callback. Callable with no visible button or key event.
  final VoidCallback onIndent;

  /// Invokes [EditorController.outdentSelection] and applies the result via
  /// the supplied callback. Callable with no visible button or key event.
  final VoidCallback onOutdent;

  static VoidCallback _makeIndent(
    EditorController controller,
    EditorApplyCallback apply,
  ) =>
      () => apply(controller.indentSelection());

  static VoidCallback _makeOutdent(
    EditorController controller,
    EditorApplyCallback apply,
  ) =>
      () => apply(controller.outdentSelection());
}
