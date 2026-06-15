// Layout pure-logic for the editor column. No widgets — callable seam only.
//
// Margin constants trace to ui-design-bible.md §Spacing-layout "Editor margins"
// (update_margins formula, editor_text_view.rs:375-395):
//   BASE_MARGIN = 36   — editor_text_view.rs:10
//   MINIMUM_MARGIN = 10 — editor_text_view.rs:11
// The ceiling is fixed at 800 (line-length feature dropped, OQ-M7-04).
//
// TASK-02 additions (spec §5.1 C2/C2b):
//   kChromeMenuZoneHeight — shared constant (replaces _kMinTapTarget in
//     chrome_overlay.dart so the reserved top inset and the real button box
//     can never drift). Canon: ui-design-bible.md §Components.2 ≥48dp rule.
//   editorHorizontalMargin(fontSizePt) — char-width horizontal inset (C2).
//   editorTopInset(width, safeAreaTop) — chrome-zone + safe-area floor (C2b).

import 'dart:math' show max;
import 'dart:ui' show lerpDouble;

const double _kMinimumMargin = 10.0;
const double _kBaseMargin = 36.0;
const double _kFloor = 400.0;
const double _kCeiling = 800.0;

// ---------------------------------------------------------------------------
// C2 — horizontal char-width inset
//
// Derivation: average Latin advance ≈ 0.5 × fontSize (em).
// Two characters ⇒ 0.5 em/char × 2 chars = 1.0 em = fontSizePt × 1.0.
// ---------------------------------------------------------------------------

/// Scale factor: 2 chars × 0.5 em/char = 1.0 em per side.
const double _kCharMarginEms = 1.0;

/// Minimum horizontal inset — ensures a visible margin even at the smallest
/// zoom slot (font-size ≈ 8 sp). Canon floor: same as [_kMinimumMargin].
const double _kCharMarginMin = 8.0;

/// Maximum horizontal inset — prevents the margin from flooding the text
/// column at extreme zoom (font-size > 38 sp clamped here at ~38 px).
const double _kCharMarginMax = 38.0;

// ---------------------------------------------------------------------------
// C2b — shared chrome-zone height constant
//
// Single source of truth for the M6 chrome hamburger/menu button box height.
// ChromeOverlay's SizedBox is sized from this constant (TASK-02 repoint) so
// the reserved top inset (editorTopInset) and the real button box stay coupled.
//
// Canon: ui-design-bible.md §Components.2 "Promote targets to ≥48dp".
// ---------------------------------------------------------------------------

/// Height (and width) of the M6 chrome hamburger/menu button box, in logical px.
///
/// Equals the ≥48dp Material tap-target minimum.
/// `ChromeOverlay` sizes its `SizedBox` from this constant so the reserved
/// top inset and the real button box never drift apart (spec C2b, NFR-10).
const double kChromeMenuZoneHeight = 48.0;

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

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

/// Horizontal editor inset in logical px, ≈ 2 character advances of the
/// current font (spec §5.1 C2).
///
/// Derivation: average Latin advance ≈ 0.5 × fontSize (em);
/// two characters ⇒ `fontSizePt × 1.0`. Clamped to
/// `[_kCharMarginMin, _kCharMarginMax]` so extreme zoom slots cannot starve
/// or flood the text column.
///
/// Invariants (observable contract C2):
///   - Strictly > 0 for all finite inputs (FR-04).
///   - Monotonic increasing in [fontSizePt] in the unclamped range (FR-07).
///   - ≥ 0 for pathological (negative) inputs — the clamp floor guards it.
double editorHorizontalMargin(double fontSizePt) {
  final raw = fontSizePt * _kCharMarginEms;
  if (raw < _kCharMarginMin) return _kCharMarginMin;
  if (raw > _kCharMarginMax) return _kCharMarginMax;
  return raw;
}

/// Static top inset (logical px) for the editor's OUTER `Padding` (spec §5.1 C2b).
///
/// Guarantees the first visible text row clears the M6 chrome menu button
/// (which sits at `top:0`) plus the system top safe-area, and is never less
/// than the M7 responsive vertical margin (FR-06b floor):
///
/// ```
/// editorTopInset(width, safeAreaTop)
///   = max( kChromeMenuZoneHeight + safeAreaTop , verticalMargin(width) )
/// ```
///
/// Intentionally does NOT depend on chrome visibility (OQ-16 decision): the
/// reservation is unconditional so the first text row never jumps when the
/// M6 chrome auto-hides/re-shows (stable baseline over reclaimed space).
///
/// Observable contract:
///   - `result >= verticalMargin(width)` always (FR-06b floor).
///   - `result >= kChromeMenuZoneHeight + safeAreaTop` always (NFR-10).
///   - Monotonic non-decreasing in [safeAreaTop].
///   - `safeAreaTop == 0` still reserves at least [kChromeMenuZoneHeight].
double editorTopInset(double width, double safeAreaTop) {
  final chromeFloor = kChromeMenuZoneHeight + safeAreaTop;
  final m7Vertical = verticalMargin(width);
  return max(chromeFloor, m7Vertical);
}
