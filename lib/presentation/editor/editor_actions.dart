// EditorActions — TASK-04 (M3 Text Editor) + TASK-06 (M4 Find/Replace)
//               + TASK-14 (M6 PasteIntent / DismissChromeIntent).
//
// Defines the Intent/Action pairs for the three editor keyboard commands
// (M3), the five find/replace keyboard commands (M4), and the two M6
// accelerator pairs (paste + chrome dismiss), plus the chrome-independent
// callback surface for indent/outdent (FR-15).
//
// Design: custom Action<T> subclasses (not CallbackAction) so each action
// carries an explicit dependency pair — either (controller, apply) for
// editor operations or (callback) for find/chrome operations — rather than a
// generic void Function(T) callback. This keeps every action testable
// without a widget tree and makes the delegation pathway unambiguous at
// the call site in BufferScreen (TASK-07 / TASK-12).
//
// Find Actions (M4) and chrome Actions (M6) take VoidCallback / named-callback
// dependencies that bind to provider verb methods at the BufferScreen wiring
// site. They do NOT import any provider or WidgetRef — all provider coupling
// lives in buffer_screen.dart (single wiring layer, FR-21 / FR-M6-22).
//
// This file holds NO visible widget chrome. The kDebugMode debug affordance
// and the Shortcuts key maps live in buffer_screen.dart (TASK-05 / TASK-07 /
// TASK-12).
//
// Spec refs: FR-08, FR-14, FR-15, §5.4(c), §4.1 (M3)
//            FR-21, §5.3 intents (M4)
//            FR-M6-20, FR-M6-21, FR-M6-22, EC-11, §5.1-g (M6)

import 'package:foglietto/presentation/editor/editor_controller.dart';
import 'package:flutter/services.dart';
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
/// On a **list line** (when [EditorController.continueListOnNewline] returns
/// non-null): applies the continuation atomically via [apply] and consumes the
/// key event, preventing the default `\n` insertion by `EditableText` (which
/// would produce a double newline).
///
/// On a **non-list line** (null result): explicitly inserts a literal `\n` at
/// the current caret via [apply] and consumes the key event. Consuming the key
/// on this branch prevents `EditableText` from also inserting `\n` (avoiding a
/// double-newline). The insertion is device-reliable: the action owns the write
/// rather than delegating to `EditableText`'s default behaviour, which is
/// unavailable in the widget-test key-event path (C-06 compliance).
///
/// The soft-keyboard IME path — where a physical `\n` arrives as a controller
/// delta rather than a key event — is NOT affected. It routes through the
/// `_onControllerChanged` literal-`\n` change-path in buffer_screen.dart
/// (§(a)/(b)), which remains intact and reachable (C-02, C-03).
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

  /// Always returns `true`: the action handles the key in every case.
  ///
  /// On the **list branch**, consuming the key prevents `EditableText` from
  /// inserting a duplicate `\n` after the continuation prefix.
  /// On the **non-list branch**, consuming the key prevents `EditableText`
  /// from inserting a second `\n` after the action has already written one
  /// via [apply].
  @override
  bool consumesKey(ContinueListIntent intent) => true;

  @override
  void invoke(ContinueListIntent intent) {
    final value = controller.value;
    final result = controller.continueListOnNewline(
      value.text,
      value.selection.baseOffset,
    );
    if (result != null) {
      // List branch: apply the continuation result (e.g. "- item\n- ").
      apply(result);
      return;
    }
    // Non-list branch: insert a literal '\n' at the collapsed caret.
    // The apply callback routes through _applyResult (buffer_screen.dart),
    // which sets _continuing so _onControllerChanged skips duplicate
    // detection — no double-newline, no spurious list-continuation attempt.
    final text = value.text;
    final offset = value.selection.baseOffset.clamp(0, text.length);
    final newText = '${text.substring(0, offset)}\n${text.substring(offset)}';
    final newOffset = offset + 1;
    apply((
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    ));
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

// ---------------------------------------------------------------------------
// M4 Find / Replace — Intents (TASK-06, FR-21, spec §5.3)
// ---------------------------------------------------------------------------
// All five intents are @immutable const-constructible value types, following
// the ContinueListIntent / IndentIntent / OutdentIntent template above.
// They carry no payload — the Actions supply the necessary dependencies.
// ---------------------------------------------------------------------------

/// Fired by Ctrl+F (§5.3, FR-21): open the search bar and auto-select the
/// first match at/after the current caret offset.
///
/// The paired [OpenFindAction] captures the caret from the controller and
/// calls [findProvider.startSearch(entryOffset)].
@immutable
class OpenFindIntent extends Intent {
  const OpenFindIntent();
}

/// Fired by Ctrl+G (§5.3, FR-21): advance to the next match with wrap-around.
///
/// The paired [FindNextAction] calls [findProvider.next()].
@immutable
class FindNextIntent extends Intent {
  const FindNextIntent();
}

/// Fired by Ctrl+Shift+G (§5.3, FR-21): move to the previous match with
/// wrap-around.
///
/// The paired [FindPrevAction] calls [findProvider.previous()].
@immutable
class FindPrevIntent extends Intent {
  const FindPrevIntent();
}

/// Fired by Ctrl+H (§5.3, FR-21): toggle the replace row in the search bar.
///
/// Replace-row visibility is a UI state owned by [FindSearchBar], NOT by the
/// find provider. The paired [ToggleReplaceAction] invokes a screen-supplied
/// [VoidCallback] that the search bar exposes.
@immutable
class ToggleReplaceIntent extends Intent {
  const ToggleReplaceIntent();
}

/// Fired by Esc (§5.3, FR-21): close the search bar and deactivate find state.
///
/// The paired [CloseFindAction] calls [findProvider.close()], which clears
/// the active flag, matches, and currentMatchIndex (FR-20).
@immutable
class CloseFindIntent extends Intent {
  const CloseFindIntent();
}

// ---------------------------------------------------------------------------
// M4 Find / Replace — Actions (TASK-06, FR-21, spec §5.3)
// ---------------------------------------------------------------------------
// Design: explicit-dependency pattern (matches the (controller, apply)
// template above). Each Action takes the minimum set of callbacks it needs:
//   - OpenFindAction: (controller, startSearch) — controller for caret offset
//   - FindNextAction: (next) — single VoidCallback
//   - FindPrevAction: (previous) — single VoidCallback
//   - ToggleReplaceAction: (onToggle) — single VoidCallback (not a provider verb)
//   - CloseFindAction: (close) — single VoidCallback
//
// None import findProvider, FindNotifier, or WidgetRef. The callbacks bind to
// findProvider verb methods at the BufferScreen wiring site (TASK-07), so all
// five Actions converge on the SAME findProvider verbs the on-screen buttons
// call (FR-21 single-path — no divergent second codepath). The callback
// abstraction also keeps each Action testable without a ProviderContainer.
// ---------------------------------------------------------------------------

/// Handles [OpenFindIntent].
///
/// Captures the current caret offset from [controller] and delegates to the
/// [startSearch] callback (wired to [findProvider.startSearch] in TASK-07).
///
/// PURE DELEGATION: does not mutate the controller or any find state.
class OpenFindAction extends Action<OpenFindIntent> {
  /// Creates an [OpenFindAction].
  ///
  /// [controller]  — the single [EditorController]; its
  ///                 `selection.baseOffset` is used as the entry offset.
  /// [startSearch] — callback bound to [findProvider.startSearch] at the
  ///                 BufferScreen wiring site (TASK-07). Must accept a named
  ///                 `entryOffset` parameter (mirroring the notifier verb).
  OpenFindAction({required this.controller, required this.startSearch});

  /// The single unified [EditorController].
  final EditorController controller;

  /// Callback bound to [findProvider.startSearch] in [BufferScreen].
  final void Function({required int entryOffset}) startSearch;

  @override
  void invoke(OpenFindIntent intent) {
    startSearch(entryOffset: controller.selection.baseOffset);
  }
}

/// Handles [FindNextIntent].
///
/// Delegates to [next] (wired to [findProvider.next()] in TASK-07).
/// Converges on the same provider verb as the Next button in [FindSearchBar]
/// (FR-21 single-path / EC-16).
class FindNextAction extends Action<FindNextIntent> {
  /// Creates a [FindNextAction].
  ///
  /// [next] — callback bound to [findProvider.next()] at the
  ///          BufferScreen wiring site (TASK-07).
  FindNextAction({required this.next});

  /// Callback bound to [findProvider.next()] in [BufferScreen].
  final VoidCallback next;

  @override
  void invoke(FindNextIntent intent) => next();
}

/// Handles [FindPrevIntent].
///
/// Delegates to [previous] (wired to [findProvider.previous()] in TASK-07).
/// Converges on the same provider verb as the Previous button in
/// [FindSearchBar] (FR-21 single-path / EC-16).
class FindPrevAction extends Action<FindPrevIntent> {
  /// Creates a [FindPrevAction].
  ///
  /// [previous] — callback bound to [findProvider.previous()] at the
  ///              BufferScreen wiring site (TASK-07).
  FindPrevAction({required this.previous});

  /// Callback bound to [findProvider.previous()] in [BufferScreen].
  final VoidCallback previous;

  @override
  void invoke(FindPrevIntent intent) => previous();
}

/// Handles [ToggleReplaceIntent].
///
/// Invokes [onToggle], a screen-supplied [VoidCallback] that controls the
/// replace-row visibility in [FindSearchBar]. Replace-row state is a UI
/// concern owned by the search bar widget, NOT by the find provider (spec §5.3
/// — toggle-replace is a UI-row concern; the model has no toggle verb).
class ToggleReplaceAction extends Action<ToggleReplaceIntent> {
  /// Creates a [ToggleReplaceAction].
  ///
  /// [onToggle] — callback supplied by [BufferScreen] that toggles the
  ///              replace row visibility in [FindSearchBar] (TASK-07).
  ToggleReplaceAction({required this.onToggle});

  /// Callback that toggles the replace-row visibility in [FindSearchBar].
  final VoidCallback onToggle;

  @override
  void invoke(ToggleReplaceIntent intent) => onToggle();
}

/// Handles [CloseFindIntent].
///
/// Delegates to [close] (wired to [findProvider.close()] in TASK-07), which
/// deactivates find state, clears highlighting, and allows [BufferScreen] to
/// restore editor focus without moving the caret (FR-20 / EC-15).
class CloseFindAction extends Action<CloseFindIntent> {
  /// Creates a [CloseFindAction].
  ///
  /// [close] — callback bound to [findProvider.close()] at the
  ///           BufferScreen wiring site (TASK-07).
  CloseFindAction({required this.close});

  /// Callback bound to [findProvider.close()] in [BufferScreen].
  final VoidCallback close;

  @override
  void invoke(CloseFindIntent intent) => close();
}

// ---------------------------------------------------------------------------
// M6 — Paste + DismissChrome Intents (TASK-14, FR-M6-20/22, §5.1-g)
// ---------------------------------------------------------------------------
// Two new intent/action pairs following the established custom-Action<T>
// dependency-pair pattern:
//
//   PasteIntent / PasteAction: reads Clipboard.getData(kTextPlain) async
//     and inserts the text at the current caret position, routing through
//     the single atomic-rewrite path (EditorApplyCallback) identical to the
//     M3 indent/outdent actions. Null or empty clipboard → no-op (EC-11).
//
//   DismissChromeIntent / DismissChromeAction: invokes a VoidCallback that
//     sets chromeVisibilityProvider to false at the BufferScreen wiring site
//     (TASK-12), following the CloseFindAction pattern.
//
// Neither class imports a Riverpod provider or WidgetRef — all provider
// coupling lives in buffer_screen.dart (single wiring layer, FR-M6-22).
// ---------------------------------------------------------------------------

/// Fired by Ctrl+V (or the system paste key) to paste the system clipboard
/// into the editor at the current caret position (FR-M6-20, §5.1-g).
///
/// The paired [PasteAction] reads [Clipboard.getData] and routes the insert
/// through the supplied [EditorApplyCallback] (same atomic-rewrite path as
/// indent/outdent). Null or empty clipboard → no-op, no exception (EC-11).
@immutable
class PasteIntent extends Intent {
  const PasteIntent();
}

/// Fired by Esc when the find bar is closed and the chrome/menu is open
/// (FR-M6-22, §5.1-g, D7). The Esc binding-precedence logic lives in
/// TASK-12 (BufferScreen); this intent is what it dispatches when the chrome
/// dismiss branch is taken.
@immutable
class DismissChromeIntent extends Intent {
  const DismissChromeIntent();
}

/// Handles [PasteIntent].
///
/// Reads [Clipboard.getData] (platform channel, stubbed in tests) and
/// inserts the clipboard text at the current caret offset via [apply]
/// (the same [EditorApplyCallback] path the M3 indent/outdent actions use).
///
/// **Insert semantics:** the clipboard text is inserted at
/// `controller.selection.baseOffset` (collapsed caret). The resulting
/// selection is a collapsed caret at `offset + clipboardText.length`.
///
/// **No-op cases (EC-11):** if [Clipboard.getData] returns null (clipboard
/// empty) or the returned text is empty, [apply] is NOT called and the
/// controller is left unchanged — no exception, no empty insert.
///
/// PURE DELEGATION: this action does NOT mutate the controller. The atomic
/// [TextEditingValue] assignment is performed by the [apply] callback (owned
/// by [BufferScreen], TASK-12).
class PasteAction extends Action<PasteIntent> {
  /// Creates a [PasteAction].
  ///
  /// [controller] — the single [EditorController] instance, used to read
  ///                the current text and caret offset.
  /// [apply]      — the BufferScreen-supplied callback that applies the
  ///                paste result atomically under a re-entrancy guard.
  PasteAction({required this.controller, required this.apply});

  /// The single unified [EditorController].
  final EditorController controller;

  /// The apply callback supplied by [BufferScreen].
  final EditorApplyCallback apply;

  @override
  Object? invoke(PasteIntent intent) {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final clipText = data?.text;
      if (clipText == null || clipText.isEmpty) return; // EC-11 no-op

      final text = controller.value.text;
      final offset = controller.value.selection.baseOffset.clamp(
        0,
        text.length,
      );
      final newText =
          text.substring(0, offset) + clipText + text.substring(offset);
      final newOffset = offset + clipText.length;

      apply((
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      ));
    });
    return null;
  }
}

/// Handles [DismissChromeIntent].
///
/// Invokes [onDismiss], a screen-supplied [VoidCallback] that hides the
/// auto-hiding chrome overlay by setting [chromeVisibilityProvider] to
/// false at the [BufferScreen] wiring site (TASK-12). The Esc-precedence
/// logic — when to dispatch this intent vs [CloseFindIntent] — lives in
/// TASK-12's Shortcuts map; this action only executes the dismiss.
///
/// Design: identical explicit-dependency pattern as [CloseFindAction];
/// no Riverpod provider or WidgetRef imported.
class DismissChromeAction extends Action<DismissChromeIntent> {
  /// Creates a [DismissChromeAction].
  ///
  /// [onDismiss] — callback supplied by [BufferScreen] that hides the chrome
  ///              (wired to [chromeVisibilityProvider.notifier.onTextChanged]
  ///              or equivalent in TASK-12).
  DismissChromeAction({required this.onDismiss});

  /// Callback that hides the chrome overlay.
  final VoidCallback onDismiss;

  @override
  void invoke(DismissChromeIntent intent) => onDismiss();
}

// ---------------------------------------------------------------------------
// SP-20260617 TASK-03 — CopyIntent / CopyAction (FR-08, FR-09, NFR-08)
// ---------------------------------------------------------------------------
// CopyAction reads the current selection from the controller and writes to
// the system clipboard via Clipboard.setData.  When the selection is
// collapsed or baseOffset == -1 (no focus), the payload is the whole-buffer
// text returned by the [readBufferText] callback — never controller.text,
// which may lag one frame behind the Riverpod bufferProvider state (NFR-08).
//
// Contract invariants:
//   EC-10 — this action NEVER mutates controller.value, selection, or composing.
//   apply/_applyResult — NEVER called from this action (read-only, C2).
//   onCopied — fires only when the written payload is non-empty.
//
// Provider wiring of [readBufferText] and [onCopied] is deferred to Wave 3
// (TASK-11); this is a pure code seam with zero widget dependencies.
// ---------------------------------------------------------------------------

/// Fired by the Copy toolbar button (§5.1-g, FR-08, FR-09).
///
/// The paired [CopyAction] reads the selection and writes to the clipboard.
/// When the selection is collapsed, the whole buffer is copied.
@immutable
class CopyIntent extends Intent {
  const CopyIntent();
}

/// Handles [CopyIntent].
///
/// Reads the controller's current selection and writes the selected text (or
/// the entire buffer when there is no selection) to the system clipboard.
///
/// **Whole-buffer path (OQ-09):** when the selection is collapsed
/// (`selection.isCollapsed == true`) or the controller has no focus
/// (`baseOffset == -1`), the payload is `readBufferText()`.  This callback
/// must return the authoritative buffer content directly from the Riverpod
/// [bufferProvider], not from `controller.text`, which may lag one frame
/// (NFR-08).
///
/// **Selection path:** when a non-collapsed range is selected, the payload is
/// `controller.value.text.substring(start, end)`.
///
/// **onCopied:** the supplied [VoidCallback] is invoked after
/// [Clipboard.setData] **only** when the written payload is non-empty.
/// Provider wiring is the caller's responsibility (TASK-11, Wave 3).
///
/// PURE READ: this action never mutates [controller.value], [.selection], or
/// [.composing] (EC-10 invariant).  It does not call [apply] or
/// `_applyResult`.
class CopyAction extends Action<CopyIntent> {
  /// Creates a [CopyAction].
  ///
  /// [controller]     — the single [EditorController] instance; its
  ///                    [value.text] and [value.selection] are read.
  /// [readBufferText] — callback that returns the authoritative buffer text
  ///                    (wired to [bufferProvider] in TASK-11); used as the
  ///                    whole-buffer payload to avoid the one-frame lag of
  ///                    [controller.text] (NFR-08).
  /// [onCopied]       — callback invoked after a non-empty payload is written
  ///                    to the clipboard (wired to a toast/haptic in TASK-11).
  CopyAction({
    required this.controller,
    required this.readBufferText,
    required this.onCopied,
  });

  /// The single unified [EditorController].
  final EditorController controller;

  /// Returns the authoritative buffer text (bypasses the controller lag).
  final String Function() readBufferText;

  /// Invoked after a non-empty clipboard write (toast / haptic hook).
  final VoidCallback onCopied;

  @override
  Object? invoke(CopyIntent intent) {
    final value = controller.value;
    final selection = value.selection;

    final String payload;
    if (selection.isCollapsed || selection.baseOffset == -1) {
      // No selection (collapsed caret or unfocused): copy the whole buffer.
      payload = readBufferText();
    } else {
      // Range selected: copy only the selected substring.
      final start = selection.start;
      final end = selection.end;
      payload = value.text.substring(start, end);
    }

    Clipboard.setData(ClipboardData(text: payload));
    if (payload.isNotEmpty) onCopied();
    return null;
  }
}

// ---------------------------------------------------------------------------
// SP-20260617 TASK-04 — PasteAtEndIntent / PasteAtEndAction (FR-10, NFR-07)
// ---------------------------------------------------------------------------
// PasteAtEndAction mirrors the existing [PasteAction] shape but resolves an
// absent caret (baseOffset == -1) to END rather than to the START (offset 0).
// It routes through the same [EditorApplyCallback] path so it inherits the
// echo-guard + BUG-004 equality short-circuit from [BufferScreen._applyResult].
//
// The existing Ctrl+V [PasteAction] (START fallback) is FROZEN (NFR-07) —
// this is a distinct, independently-registered sibling.  Both can coexist in
// the same Actions widget without cross-contamination.
//
// Contract invariants:
//   null / empty clipboard — no-op; [apply] and [onPasted] are NOT called.
//   apply — always called through [EditorApplyCallback]; never direct mutation.
//   onPasted — fires only on a successful (non-empty) paste.
// ---------------------------------------------------------------------------

/// Fired by the Paste toolbar button (§5.1-g, FR-10).
///
/// The paired [PasteAtEndAction] reads the clipboard and inserts the text at
/// the current caret, falling back to END when there is no caret (contrast
/// with [PasteAction] which falls back to the START / offset 0).
@immutable
class PasteAtEndIntent extends Intent {
  const PasteAtEndIntent();
}

/// Handles [PasteAtEndIntent].
///
/// Reads [Clipboard.getData] (platform channel, stubbed in tests) and inserts
/// the clipboard text at the current caret offset via [apply].
///
/// **Insert semantics — END fallback:** the insert offset is
/// `controller.selection.baseOffset`.  When `baseOffset < 0` (no focus /
/// unset), the offset resolves to `controller.value.text.length` (end of
/// buffer), not 0 — this is the key behavioral difference from [PasteAction].
/// When `baseOffset >= 0`, it is clamped to `[0, text.length]`.
///
/// **No-op cases (EC-15b):** if [Clipboard.getData] returns null or the
/// returned text is empty, [apply] and [onPasted] are NOT called and the
/// controller is left unchanged — no exception, no empty insert.
///
/// Routes through [apply] (the same [EditorApplyCallback] path as
/// [EditorIndentAction] and [PasteAction]) so the atomic rewrite inherits
/// the re-entrancy echo-guard and BUG-004 equality short-circuit from
/// [BufferScreen._applyResult].
///
/// PURE DELEGATION: this action does NOT mutate the controller directly.
class PasteAtEndAction extends Action<PasteAtEndIntent> {
  /// Creates a [PasteAtEndAction].
  ///
  /// [controller] — the single [EditorController] instance, used to read
  ///                the current text and caret offset.
  /// [apply]      — the BufferScreen-supplied callback that applies the
  ///                paste result atomically under a re-entrancy guard.
  /// [onPasted]   — callback invoked after a successful (non-empty) paste
  ///                (wired to a haptic / toast in TASK-11).
  PasteAtEndAction({
    required this.controller,
    required this.apply,
    required this.onPasted,
  });

  /// The single unified [EditorController].
  final EditorController controller;

  /// The apply callback supplied by [BufferScreen].
  final EditorApplyCallback apply;

  /// Invoked after a successful paste (haptic / toast hook).
  final VoidCallback onPasted;

  @override
  Object? invoke(PasteAtEndIntent intent) {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final clipText = data?.text;
      if (clipText == null || clipText.isEmpty) return; // EC-15b no-op

      final text = controller.value.text;
      final base = controller.value.selection.baseOffset;
      // END fallback: unset caret (base < 0) resolves to end of text.
      final offset = base < 0 ? text.length : base.clamp(0, text.length);

      final newText =
          text.substring(0, offset) + clipText + text.substring(offset);
      final newOffset = offset + clipText.length;

      apply((
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      ));
      onPasted();
    });
    return null;
  }
}
