// EditorController — the single unified TextEditingController subclass shared
// by BOTH the M3 text-editor and the M4 find-replace feature.
//
// CONTRACT INVARIANTS (read before extending in M3/M4):
//
//  1. SINGLE CONTROLLER — no milestone may subclass TextEditingController
//     independently (FR-15, §5.3). All editor + find-replace behaviour routes
//     through THIS class.
//
//  2. SINGLE CONTINUATION PATH — every newline event (soft-keyboard Return AND
//     hardware Enter) calls [continueListOnNewline] and only that function for
//     list auto-continuation (EC-07, R-03). M3 wires the call; M4 must not
//     introduce a parallel path.
//
//  3. INVIOLABLE EPHEMERALITY — the buffer text held in this controller is
//     strictly in-memory. This class MUST NEVER write controller text to any
//     persistent store, schedule a save, or expose a persistence API. The sole
//     exception is the future recovery hook (M5) which writes via
//     BufferNotifier.updateText → the recovery repo — not via this controller
//     directly (NFR-09, R-01).
//
// Spec refs: FR-15, EC-07, EC-10, EC-26, NFR-09

import 'package:buffer/domain/editor/line_indent.dart';
import 'package:buffer/domain/editor/list_continuation.dart';
import 'package:flutter/material.dart';

/// The single [TextEditingController] subclass shared by the M3 text-editor
/// and the M4 find-replace feature.
///
/// In M1 this class shipped the **shape and seams** only — no highlight
/// painting, no list-continuation logic. M3 wires the continuation and
/// indent/outdent delegation surface; M4 adds highlight painting.
class EditorController extends TextEditingController {
  /// Creates an [EditorController].
  ///
  /// [text] is the optional initial content (forwarded to
  /// [TextEditingController]). No required arguments.
  EditorController({super.text});

  // ---------------------------------------------------------------------------
  // Find-replace seam — highlight ranges (M4 will paint these in buildTextSpan)
  // ---------------------------------------------------------------------------

  List<TextRange> _highlightRanges = const [];

  /// The set of text ranges to highlight in the editor (populated by M4
  /// find-replace). Defaults to an empty list before any search is active.
  ///
  /// INVARIANT (EC-10): the setter stores the value and MUST NOT mutate
  /// [selection]. Current-match identity is expressed as [currentMatchIndex]
  /// — a pure index — not as a selection change.
  List<TextRange> get highlightRanges => _highlightRanges;

  set highlightRanges(List<TextRange> ranges) {
    _highlightRanges = ranges;
    // Notify listeners so the text field repaints with updated highlight ranges
    // (M4 buildTextSpan reads this list). MUST NOT touch `selection` — EC-10.
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Find-replace seam — current match index
  // ---------------------------------------------------------------------------

  int? _currentMatchIndex;

  /// The index into [highlightRanges] that represents the "current" match.
  /// Defaults to `null` when no search is active or no match is selected.
  ///
  /// INVARIANT (EC-10): the setter stores the value and MUST NOT mutate
  /// [selection]. The rendering layer (M4 buildTextSpan override) uses this
  /// index to distinguish the focused match visually without moving the cursor.
  int? get currentMatchIndex => _currentMatchIndex;

  set currentMatchIndex(int? index) {
    _currentMatchIndex = index;
    // Notify listeners so M4 buildTextSpan can repaint the focused-match
    // highlight differently. MUST NOT touch `selection` — EC-10.
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Rendering seam — buildTextSpan (M4 will apply highlight spans here)
  // ---------------------------------------------------------------------------

  /// Builds the [TextSpan] rendered inside the text field.
  ///
  /// M1: delegates to [super.buildTextSpan] verbatim — no highlight painting
  /// yet. The seam exists so M4 can override this method in a coordinated way
  /// (or so the test can verify the delegation) without structural refactoring.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
  }

  // ---------------------------------------------------------------------------
  // List-continuation seam (EC-07, R-03) — M3 delegation surface
  // ---------------------------------------------------------------------------

  /// Delegates to [ListContinuation.process] and adapts the result to a
  /// Flutter-typed record.
  ///
  /// Returns `({String text, TextSelection selection})` when a list rule fires,
  /// where [TextSelection.isCollapsed] is `true` and
  /// [TextSelection.baseOffset] equals the caret returned by
  /// [ListContinuation.process]. Returns `null` when no continuation fires
  /// (caller inserts a plain `"\n"`).
  ///
  /// PURE DELEGATION (EC-07):
  /// - Does NOT mutate [text], [selection], or any other controller field.
  /// - Does NOT call [notifyListeners].
  /// - Does NOT touch [highlightRanges] or [currentMatchIndex] (EC-26).
  ///
  /// This is the single continuation entry point for EVERY newline event —
  /// both soft-keyboard Return and hardware Enter (§5.3, R-03, EC-07).
  ///
  /// [currentText] — the buffer text at the moment the newline fires
  ///                 (need not equal [this.text]).
  /// [caretOffset] — code-unit offset where the newline is being inserted.
  ({String text, TextSelection selection})? continueListOnNewline(
    String currentText,
    int caretOffset,
  ) {
    final result = ListContinuation.process(currentText, caretOffset);
    if (result == null) return null;
    return (
      text: result.text,
      selection: TextSelection.collapsed(offset: result.caret),
    );
  }

  // ---------------------------------------------------------------------------
  // Indent/outdent seam (EC-07, FR-11..FR-13, FR-15) — M3 delegation surface
  // ---------------------------------------------------------------------------

  /// Reads the controller's current [value.text] and [value.selection],
  /// delegates to [LineIndent.indent], and returns the adapted record.
  ///
  /// PURE DELEGATION (EC-07):
  /// - Does NOT mutate [value], [text], or [selection].
  /// - Does NOT call [notifyListeners].
  /// - Does NOT touch [highlightRanges] or [currentMatchIndex] (EC-26).
  ///
  /// The caller ([BufferScreen]) applies the returned record atomically.
  ({String text, TextSelection selection}) indentSelection() {
    final result = LineIndent.indent(
      value.text,
      value.selection.start,
      value.selection.end,
    );
    return (
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selStart,
        extentOffset: result.selExtent,
      ),
    );
  }

  /// Reads the controller's current [value.text] and [value.selection],
  /// delegates to [LineIndent.outdent], and returns the adapted record.
  ///
  /// PURE DELEGATION (EC-07):
  /// - Does NOT mutate [value], [text], or [selection].
  /// - Does NOT call [notifyListeners].
  /// - Does NOT touch [highlightRanges] or [currentMatchIndex] (EC-26).
  ///
  /// The caller ([BufferScreen]) applies the returned record atomically.
  ({String text, TextSelection selection}) outdentSelection() {
    final result = LineIndent.outdent(
      value.text,
      value.selection.start,
      value.selection.end,
    );
    return (
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selStart,
        extentOffset: result.selExtent,
      ),
    );
  }
}
