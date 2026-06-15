// SP-20260615 TASK-08: LineNumberGutter — wrap-aware visual-row line-number
// gutter.
//
// Spec refs: FR-14, FR-15, FR-16, NFR-06, NFR-09
// Contract: C7 (spec §5.1), gutter metrics strategy (spec §5.2)
//
// Design:
//   - StatefulWidget with four constructor inputs: scrollController,
//     editorContext, textStyle, strutStyle. NO EditorController, NO
//     persistence (NFR-09 ephemerality).
//   - Subscribes to [scrollController]; on offset change calls [setState]
//     which rebuilds the paint layer (FR-16 scroll sync).
//   - Rebuilds on textStyle/strutStyle change because [BufferScreen.build]
//     passes them from the reactive settings provider — any font-size/strut
//     change re-creates the widget via BuilderContext rebuild (FR-16 M7 sync).
//   - Locates [RenderEditable] via the same element-walk as [_scrollToMatch]
//     in buffer_screen.dart. Element-walk starts from [editorContext] and
//     finds the first [EditableTextState].
//   - Enumerates VISUAL rows via [getBoxesForSelection] over each logical
//     line's full selection. Each [TextBox] returned represents one visual
//     (soft-wrapped) row and receives the NEXT sequential integer starting
//     from 1 (FR-15: one number per visual row, not per logical line).
//   - Viewport-bounded: only enumerates logical lines whose box tops fall
//     inside the visible range [scrollOffset, scrollOffset + viewportHeight]
//     to keep per-frame work O(visible rows), not O(buffer) (NFR-06).
//   - Guards all error paths: empty boxes, null EditableTextState, pre-layout
//     RenderEditable all result in an empty row list with no exception (EC-10).
//   - Empty buffer (text == ''): produces a single row numbered 1 (EC-01).
//   - Uses a [CustomPainter] for the number painting — no Text widgets, no
//     allocations per row outside paint. Keeps the widget tree minimal.
//   - Sits INSIDE the outer [Padding] on the LEADING edge as a [Row] sibling
//     of the text column (spec §5.2 step 5). Width is computed from the
//     maximum digit count × digit advance + small horizontal padding.
//
// <!-- CANON GAP: line-number-gutter anatomy/styling tokens/RTL rule absent
//      from ui-design-bible (OQ-08/OQ-14); dimmed-secondary ~0.58-opacity
//      onSurface number colour + surface background + leading-edge placement
//      pending bible note -->

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ---------------------------------------------------------------------------
// LineNumberGutter
// ---------------------------------------------------------------------------

/// A wrap-aware line-number gutter that renders one sequential integer per
/// **visual row** of the adjacent editor [TextField].
///
/// Constructor takes only [scrollController], [editorContext], [textStyle],
/// and [strutStyle] — no [EditorController], no persistence (NFR-09).
///
/// Mount inside [BufferScreen]'s outer [Padding] on the leading edge as a
/// [Row] child so its top origin equals [editorTopInset] (FR-06a coupling).
///
/// The [editorContext] must be a [BuildContext] whose element subtree contains
/// the editor's [EditableText] (i.e. the [BufferScreen] context, the same one
/// used by [_scrollToMatch]).
class LineNumberGutter extends StatefulWidget {
  const LineNumberGutter({
    super.key,
    required this.scrollController,
    required this.editorContext,
    required this.textStyle,
    required this.strutStyle,
    this.textListenable,
  });

  /// The shared [ScrollController] attached to the editor [TextField].
  ///
  /// The gutter subscribes to this controller and repaints on every offset
  /// change so row numbers track the scroll position (FR-16 scroll sync).
  final ScrollController scrollController;

  /// The [BuildContext] whose subtree contains the editor's [EditableText].
  ///
  /// Used by the element-walk that locates [EditableTextState] /
  /// [RenderEditable] — identical to the walk in [BufferScreen._scrollToMatch].
  final BuildContext editorContext;

  /// The editor's current [TextStyle] (font size, family, height).
  ///
  /// Passed from [BufferScreen.build] so any font-size/strut change (M7
  /// pinch-zoom) triggers a rebuild and re-query of [RenderEditable] boxes.
  final TextStyle textStyle;

  /// The editor's current [StrutStyle] (EC-M7-11 paired invariant).
  ///
  /// Must stay paired with [textStyle] so gutter row heights match the
  /// editor's actual rendered line heights.
  final StrutStyle strutStyle;

  /// Optional read-only change source for the editor's text (FR-16).
  ///
  /// Typed as [Listenable] (not the controller) so the gutter can *observe*
  /// text changes but can never mutate the buffer — preserving the read-only,
  /// no-write-path contract (NFR-09 ephemerality). [BufferScreen] passes its
  /// editor controller here.
  ///
  /// Without this, the gutter only recomputes on scroll / widget rebuild, so
  /// typing that does not scroll (or rebuild the screen) leaves the row numbers
  /// stale — or, on the first keyboard-driven relayout, culled to nothing.
  /// When the listenable notifies, a coalesced post-frame recompute runs.
  final Listenable? textListenable;

  @override
  State<LineNumberGutter> createState() => LineNumberGutterState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// State for [LineNumberGutter].
///
/// Exposed as a named public class (not `_State`) so widget tests can
/// access it via `tester.state<LineNumberGutterState>(...)` and read
/// [rowNumbersForTest] (OQ-11 testability seam).
class LineNumberGutterState extends State<LineNumberGutter> {
  // The list of visual-row numbers currently painted.
  // Rebuilt on scroll and on widget rebuild (font/strut change).
  List<int> _rowNumbers = const [];

  // The list of corresponding y-offsets in widget-local space.
  // Parallel to _rowNumbers: _rowTops[i] is the paint top for _rowNumbers[i].
  List<double> _rowTops = const [];

  // ---------------------------------------------------------------------------
  // @visibleForTesting accessors (OQ-11)
  // ---------------------------------------------------------------------------

  /// The sequential row numbers currently visible in the gutter.
  ///
  /// Returns a snapshot at the last repaint. Empty when pre-layout or when
  /// [RenderEditable] is not yet available (EC-10).
  @visibleForTesting
  List<int> get rowNumbersForTest => List<int>.unmodifiable(_rowNumbers);

  /// The shared [ScrollController] injected via the constructor.
  ///
  /// Exposed for tests that need to check whether it has clients and animate
  /// it to verify scroll-sync behaviour (FR-16).
  @visibleForTesting
  ScrollController get scrollControllerForTest => widget.scrollController;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  // Coalesces multiple change events (scroll bursts, keystrokes) into a single
  // recompute per frame, always deferred to AFTER layout (NFR-06 / disappear fix).
  bool _recomputeScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onSourceChanged);
    widget.textListenable?.addListener(_onSourceChanged);
    // First box-walk runs post-frame so RenderEditable is laid out.
    _scheduleRecompute();
  }

  @override
  void didUpdateWidget(LineNumberGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      oldWidget.scrollController.removeListener(_onSourceChanged);
      widget.scrollController.addListener(_onSourceChanged);
    }
    if (!identical(oldWidget.textListenable, widget.textListenable)) {
      oldWidget.textListenable?.removeListener(_onSourceChanged);
      widget.textListenable?.addListener(_onSourceChanged);
    }
    // textStyle / strutStyle change → new line heights → re-query boxes.
    // editorContext change is extremely rare but handled. Always post-frame so
    // the query reads the relaid-out RenderEditable, not a transient mid-build
    // state (which would cull every row and blank the gutter).
    _scheduleRecompute();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onSourceChanged);
    widget.textListenable?.removeListener(_onSourceChanged);
    super.dispose();
  }

  /// Scroll offset OR editor text changed — schedule a coalesced recompute.
  void _onSourceChanged() => _scheduleRecompute();

  /// Queues a single post-frame [_recomputeRows]. Coalesces a burst of change
  /// notifications (rapid scroll / fast typing) into one box-walk per frame,
  /// and guarantees the walk runs after layout so [getBoxesForSelection] and
  /// `context.size` are valid (fixes numbers vanishing on first keystroke).
  void _scheduleRecompute() {
    if (_recomputeScheduled) return;
    _recomputeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recomputeScheduled = false;
      if (mounted) _recomputeRows();
    });
  }

  // ---------------------------------------------------------------------------
  // Box-walk and row enumeration
  // ---------------------------------------------------------------------------

  /// Recomputes the list of visible row numbers by walking the RenderEditable.
  ///
  /// Called after every scroll event and widget rebuild.
  ///
  /// **Algorithm (spec §5.2 steps 1–4 + 8):**
  ///
  /// 1. Locate `EditableTextState` via element-walk from [widget.editorContext].
  /// 2. Read the full text from `renderEditable.text`.
  /// 3. Split on `\n` into logical lines.
  /// 4. For each logical line, call `getBoxesForSelection` to get one
  ///    `TextBox` per visual (soft-wrapped) row.
  /// 5. Assign sequential integers starting from 1 across all visual rows.
  /// 6. Viewport-clip: only include rows whose box top falls in
  ///    `[scrollOffset - lineHeightEstimate, scrollOffset + viewportHeight]`
  ///    (one lineHeight slack below ensures the first visible row is included
  ///    even if its top is just above the scroll offset).
  ///
  /// **EC-01** (empty buffer): produces `[1]` with top `0.0`.
  ///
  /// **EC-10** (pre-layout / headless): empty box list → `_rowNumbers = []`,
  ///   `_rowTops = []`, no exception.
  void _recomputeRows() {
    if (!mounted) return;

    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;

    // Locate the RenderEditable via element-walk (identical to _scrollToMatch).
    EditableTextState? edState;
    try {
      void visitElement(Element el) {
        if (edState != null) return;
        if (el is StatefulElement && el.state is EditableTextState) {
          edState = el.state as EditableTextState;
          return;
        }
        el.visitChildren(visitElement);
      }

      widget.editorContext.visitChildElements(visitElement);
    } catch (_) {
      // Element tree unavailable — pre-layout or headless.
    }

    if (edState == null) {
      // EC-10: no EditableTextState → empty list, no throw.
      _applyRows(const [], const []);
      return;
    }

    final ro = edState!.renderEditable;

    // Read the full plain text via the render object's text span.
    // InlineSpan.toPlainText() is the public, stable API for this.
    final String fullText = ro.text?.toPlainText() ?? '';

    // EC-01: empty buffer → single row number 1 at top 0.
    if (fullText.isEmpty) {
      _applyRows([1], [0.0 - scrollOffset]);
      return;
    }

    // Viewport bounds for culling (NFR-06 O(viewport/lineHeight)).
    // We estimate line height from strutStyle / textStyle.
    final double estimatedLineHeight = _estimateLineHeight();
    final double viewportHeight = context.size?.height ?? double.infinity;

    // Walk logical lines and enumerate visual rows.
    final rowNums = <int>[];
    final rowTops = <double>[];
    int sequentialRow = 1;
    int charOffset = 0;

    final logicalLines = fullText.split('\n');
    for (int lineIdx = 0; lineIdx < logicalLines.length; lineIdx++) {
      final line = logicalLines[lineIdx];
      final lineLength = line.length;

      // The selection covering this entire logical line.
      // For an empty line (lineLength == 0), the selection is collapsed.
      final sel = TextSelection(
        baseOffset: charOffset,
        extentOffset: charOffset + lineLength,
      );

      List<TextBox> boxes;
      try {
        boxes = ro.getBoxesForSelection(sel);
      } catch (_) {
        // Guard: getBoxesForSelection may throw before layout completes (EC-10).
        boxes = const [];
      }

      if (boxes.isEmpty) {
        // Empty logical line or pre-layout: create a synthetic row using
        // an estimated y position based on the sequential row count so far.
        // This handles empty lines between paragraphs correctly.
        final estimatedTop =
            (sequentialRow - 1) * estimatedLineHeight - scrollOffset;

        // Viewport culling — skip rows above the viewport.
        if (estimatedTop >= -estimatedLineHeight &&
            estimatedTop <= viewportHeight + estimatedLineHeight) {
          rowNums.add(sequentialRow);
          rowTops.add(estimatedTop);
        }
        sequentialRow++;
      } else {
        // Each TextBox is one visual (soft-wrapped) row (FR-15).
        for (final box in boxes) {
          final paintTop = box.top - scrollOffset;

          // Viewport culling (NFR-06): skip rows outside visible range.
          if (paintTop < -estimatedLineHeight) {
            sequentialRow++;
          } else if (paintTop > viewportHeight + estimatedLineHeight) {
            // Rows beyond the viewport bottom — stop processing this line.
            // Remaining logical lines will also be off-screen (ascending tops).
            sequentialRow++;
          } else {
            rowNums.add(sequentialRow);
            rowTops.add(paintTop);
            sequentialRow++;
          }
        }
      }

      // Advance char offset past the line AND the '\n' separator.
      charOffset += lineLength;
      if (lineIdx < logicalLines.length - 1) {
        charOffset += 1; // the '\n' character
      }
    }

    _applyRows(rowNums, rowTops);
  }

  void _applyRows(List<int> nums, List<double> tops) {
    setState(() {
      _rowNumbers = nums;
      _rowTops = tops;
    });
  }

  /// Estimates line height from [widget.strutStyle] / [widget.textStyle].
  ///
  /// Used for viewport culling when [getBoxesForSelection] boxes are absent
  /// (e.g. empty logical lines, pre-layout).
  double _estimateLineHeight() {
    final fontSize =
        widget.strutStyle.fontSize ?? widget.textStyle.fontSize ?? 14.0;
    final height = widget.strutStyle.height ?? widget.textStyle.height ?? 1.4;
    return fontSize * height;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Gutter number colour: dimmed onSurface (~0.58 opacity, analogous to the
    // 0.58-opacity match-count label in ui-design-bible §Components.4).
    // <!-- CANON GAP: no dedicated line-number-gutter token in ui-design-bible
    //      (OQ-08); using 0.58-opacity onSurface as a mobile-port approximation.
    //      Pending bible note for RTL + token naming (OQ-14). -->
    final numberColor = colorScheme.onSurface.withValues(alpha: 0.58);

    // Number text style mirrors the editor's font family and size for
    // alignment accuracy, but at slightly smaller size and dimmed colour.
    final numberStyle = widget.textStyle.copyWith(
      color: numberColor,
      fontSize: (widget.textStyle.fontSize ?? 14.0) * 0.8,
      height: null, // let the painter control vertical placement
    );

    // Compute the gutter width from the digit count of the largest row number.
    final maxNum = _rowNumbers.isEmpty ? 1 : _rowNumbers.last + 10;
    final digitCount = maxNum.toString().length;
    final digitWidth = (widget.textStyle.fontSize ?? 14.0) * 0.6;
    final gutterWidth = digitCount * digitWidth + 8.0; // 4px padding each side

    return SizedBox(
      width: gutterWidth,
      child: ClipRect(
        child: CustomPaint(
          painter: _GutterPainter(
            rowNumbers: _rowNumbers,
            rowTops: _rowTops,
            style: numberStyle,
            gutterWidth: gutterWidth,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GutterPainter
// ---------------------------------------------------------------------------

/// [CustomPainter] that draws right-aligned row numbers in the gutter.
///
/// Each number is drawn at the corresponding `_rowTops[i]` y coordinate.
/// This avoids allocating [Text] widgets per row and keeps the paint path
/// O(visible rows) (NFR-06).
class _GutterPainter extends CustomPainter {
  _GutterPainter({
    required this.rowNumbers,
    required this.rowTops,
    required this.style,
    required this.gutterWidth,
  });

  final List<int> rowNumbers;
  final List<double> rowTops;
  final TextStyle style;
  final double gutterWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (rowNumbers.isEmpty) return;

    for (int i = 0; i < rowNumbers.length; i++) {
      final num = rowNumbers[i];
      final top = rowTops[i];

      // Skip numbers that have scrolled above the visible area.
      if (top + 24.0 < 0) continue;
      if (top > size.height) break;

      final tp = TextPainter(
        text: TextSpan(text: '$num', style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: gutterWidth - 4.0);

      // Right-align within the gutter with 4px right padding.
      final x = gutterWidth - tp.width - 4.0;
      tp.paint(canvas, Offset(x, top));
    }
  }

  @override
  bool shouldRepaint(_GutterPainter oldDelegate) {
    // Repaint only when data changes — avoids unnecessary work (NFR-06).
    return oldDelegate.rowNumbers != rowNumbers ||
        oldDelegate.rowTops != rowTops ||
        oldDelegate.style != style ||
        oldDelegate.gutterWidth != gutterWidth;
  }
}
