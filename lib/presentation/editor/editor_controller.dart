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
// Spec refs: FR-15, EC-07, EC-10, NFR-09

import 'package:flutter/material.dart';

/// The single [TextEditingController] subclass shared by the M3 text-editor
/// and the M4 find-replace feature.
///
/// In M1 this class ships the **shape and seams** only — no highlight painting,
/// no list-continuation logic. Concrete behaviour is added in M3 and M4 while
/// this file remains the sole [TextEditingController] descendant in the app.
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
  // List-continuation seam (EC-07, R-03)
  // ---------------------------------------------------------------------------

  /// Returns a new string with `"\n"` inserted at [caretOffset] inside
  /// [currentText].
  ///
  /// This is the single continuation function called for EVERY newline event —
  /// both the soft-keyboard Return key and the hardware Enter key (§5.3,
  /// R-03). M3 wires the call; M4 must not introduce a parallel path.
  ///
  /// PURE FUNCTION INVARIANT (EC-07):
  /// - No mutation of this controller's [text], [selection], or any other
  ///   field.
  /// - No side effects; safe to call from any context.
  ///
  /// M1 default: inserts a plain `"\n"` at [caretOffset] with no list-
  /// detection logic. M3 replaces the body with Markdown list-continuation.
  ///
  /// [currentText] — the string to insert into (need not equal [this.text]).
  /// [caretOffset] — the insertion point, in code-unit offset terms.
  String continueListOnNewline(String currentText, int caretOffset) {
    return '${currentText.substring(0, caretOffset)}\n${currentText.substring(caretOffset)}';
  }
}
