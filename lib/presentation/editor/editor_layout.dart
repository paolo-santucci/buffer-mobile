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
// G5 — chrome-spacing gap constants (TASK-01)
//
// Three independently named constants so per-axis tuning is safe.
// Each traces to spec §TASK-01 / ui-design-bible.md §Spacing-layout "chrome gaps".
// ---------------------------------------------------------------------------

/// Gap added above the first text row, between the menu/share pill and the
/// editor text area (spec §TASK-01 kChromeTopGap).
const double kChromeTopGap = 16.0;

/// Gap added below the last visible text row, between the editor text and the
/// bottom toolbar (spec §TASK-01 kChromeBottomGap).
/// Appears as an explicit term inside [editorBottomInset]'s `max(...)` —
/// never summed onto the result (anti-additive contract, NFR-02).
const double kChromeBottomGap = 16.0;

/// Horizontal gap between the editor text column and the chrome overlays
/// (spec §TASK-01 kChromeSideMargin).
const double kChromeSideMargin = 16.0;

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

/// Static bottom inset (logical px) for the editor's OUTER `Padding` (spec FR-22).
///
/// Guarantees the last visible text row clears whichever of the bottom-chrome
/// zone, the breathing gap, the responsive vertical margin, or the software
/// keyboard is tallest — then adds the system bottom safe-area:
///
/// ```
/// editorBottomInset(width, keyboardInset, safeAreaBottom)
///   = max( kChromeMenuZoneHeight, kChromeBottomGap,
///          verticalMargin(width), keyboardInset )
///     + safeAreaBottom
/// ```
///
/// [kChromeBottomGap] is an explicit term inside the `max(...)` — never summed
/// onto the result. In practice it is dominated by [kChromeMenuZoneHeight] (48 > 16),
/// but it has an auditable home here so per-axis tuning is safe (TASK-01).
///
/// Anti-additive contract: when the keyboard dominates the result is
/// `keyboardInset + safeAreaBottom`, never `kChromeMenuZoneHeight + keyboardInset
/// + safeAreaBottom`. The `max` picks one dominant value; they are never summed.
///
/// Observable contract:
///   - `result >= kChromeMenuZoneHeight + safeAreaBottom` always (floor guarantee).
///   - `result >= kChromeBottomGap + safeAreaBottom` always (gap floor).
///   - `result >= verticalMargin(width) + safeAreaBottom` always (responsive floor).
///   - Monotonic non-decreasing in both [keyboardInset] and [safeAreaBottom].
///   - `keyboardInset == 0` still reserves at least [kChromeMenuZoneHeight].
///   - Pure: no side effects; repeated calls with identical args return identical results.
///
/// Applying this inset to the editor's `Padding` widget is Wave 3 (TASK-11).
double editorBottomInset(
  double width,
  double keyboardInset,
  double safeAreaBottom,
) {
  return max(
        max(kChromeMenuZoneHeight, kChromeBottomGap),
        max(verticalMargin(width), keyboardInset),
      ) +
      safeAreaBottom;
}

/// Bottom inset (logical px) for the floating bottom morph slot's Positioned
/// (toolbar / find+replace box). Lifts the slot above the soft keyboard.
///
/// Anti-additive (mirror of [editorBottomInset]): keyboard inset and the resting
/// chrome gap are mutually exclusive — compose with `max(...)`, NEVER `+`. Only
/// [safeAreaBottom] is genuinely additive.
///
/// ```
/// chromeSlotBottomInset(keyboardInset, safeAreaBottom)
///   = max(kChromeBottomGap, keyboardInset) + safeAreaBottom
/// ```
///
/// Observable contract:
///   - `keyboardInset == 0` → result == `kChromeBottomGap + safeAreaBottom` (resting).
///   - `keyboardInset == kChromeBottomGap` (tie) → NOT doubled; == `kChromeBottomGap + safeAreaBottom`.
///   - keyboard dominates → result == `keyboardInset + safeAreaBottom`
///     (NEVER `kChromeBottomGap + keyboardInset + safeAreaBottom`).
///   - Monotonic non-decreasing in both [keyboardInset] and [safeAreaBottom].
///   - Pure: identical args → identical result; no Flutter dependency.
double chromeSlotBottomInset(double keyboardInset, double safeAreaBottom) {
  return max(kChromeBottomGap, keyboardInset) + safeAreaBottom;
}

/// Static top inset (logical px) for the editor's OUTER `Padding` (spec §5.1 C2b).
///
/// Guarantees the first visible text row clears the M6 chrome menu button
/// (which sits at `top:0`) plus the system top safe-area, and is never less
/// than the M7 responsive vertical margin (FR-06b floor), plus an explicit
/// breathing gap [kChromeTopGap] above the text:
///
/// ```
/// editorTopInset(width, safeAreaTop)
///   = max( kChromeMenuZoneHeight + safeAreaTop , verticalMargin(width) )
///     + kChromeTopGap
/// ```
///
/// Intentionally does NOT depend on chrome visibility (OQ-16 decision): the
/// reservation is unconditional so the first text row never jumps when the
/// M6 chrome auto-hides/re-shows (stable baseline over reclaimed space).
///
/// Observable contract:
///   - `result >= verticalMargin(width) + kChromeTopGap` always (FR-06b floor).
///   - `result >= kChromeMenuZoneHeight + safeAreaTop + kChromeTopGap` always (NFR-10).
///   - Monotonic strictly increasing in [safeAreaTop] (bump is additive).
///   - `safeAreaTop == 0` still reserves at least `kChromeMenuZoneHeight + kChromeTopGap`.
double editorTopInset(double width, double safeAreaTop) {
  final chromeFloor = kChromeMenuZoneHeight + safeAreaTop;
  final m7Vertical = verticalMargin(width);
  return max(chromeFloor, m7Vertical) + kChromeTopGap;
}
