// Layout pure-logic for the editor column. No widgets — callable seam only.
//
// Margin constants trace to ui-design-bible.md §Spacing-layout "Editor margins"
// (update_margins formula, editor_text_view.rs:375-395):
//   BASE_MARGIN = 36   — editor_text_view.rs:10
//   MINIMUM_MARGIN = 10 — editor_text_view.rs:11
// The ceiling is fixed at 800 (line-length feature dropped, OQ-M7-04).

import 'dart:ui' show lerpDouble;

const double _kMinimumMargin = 10.0;
const double _kBaseMargin = 36.0;
const double _kFloor = 400.0;
const double _kCeiling = 800.0;

/// Returns the vertical margin in logical pixels for a given viewport [width].
///
/// - `width <= 400` → [_kMinimumMargin] (10.0)
/// - `400 < width < 800` → linear interpolation 10 → 36
/// - `width >= 800` → [_kBaseMargin] (36.0)
///
/// Consumed by TASK-12's `LayoutBuilder` inside `buffer_screen.dart`.
double verticalMargin(double width) {
  if (width <= _kFloor) return _kMinimumMargin;
  if (width >= _kCeiling) return _kBaseMargin;
  return lerpDouble(
    _kMinimumMargin,
    _kBaseMargin,
    (width - _kFloor) / (_kCeiling - _kFloor),
  )!;
}
