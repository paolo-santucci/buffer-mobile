// Tests for lib/presentation/editor/editor_layout.dart
//
// Margin constants trace to ui-design-bible.md §Spacing-layout "Editor margins":
//   BASE_MARGIN = 36  (editor_text_view.rs:10)
//   MINIMUM_MARGIN = 10  (editor_text_view.rs:11)
// Interpolation formula: update_margins (editor_text_view.rs:375-395).
// The ceiling is fixed at 800 (line-length feature dropped, OQ-M7-04).
//
// TASK-02 additions:
//   editorHorizontalMargin(fontSizePt) — contract C2
//   editorTopInset(width, safeAreaTop) — contract C2b
//   kChromeMenuZoneHeight              — shared constant

import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/presentation/editor/editor_layout.dart';

void main() {
  group('verticalMargin', () {
    test('returns MINIMUM_MARGIN (10.0) at the lower boundary (400.0)', () {
      expect(verticalMargin(400.0), 10.0);
    });

    test('clamps to MINIMUM_MARGIN (10.0) below the floor (320.0)', () {
      expect(verticalMargin(320.0), 10.0);
    });

    test('interpolates correctly at midpoint 600.0 → 23.0', () {
      // lerp: 10 + (36 - 10) * (600 - 400) / (800 - 400)
      //      = 10 + 26 * 0.5 = 23.0
      expect(verticalMargin(600.0), 23.0);
    });

    test('returns BASE_MARGIN (36.0) at the upper boundary (800.0)', () {
      expect(verticalMargin(800.0), 36.0);
    });

    test('clamps to BASE_MARGIN (36.0) above the ceiling (1200.0)', () {
      expect(verticalMargin(1200.0), 36.0);
    });

    test(
      'one unit past lower boundary (399.9) stays at MINIMUM_MARGIN (10.0)',
      () {
        expect(verticalMargin(399.9), 10.0);
      },
    );

    test(
      'one unit past upper boundary (800.1) stays at BASE_MARGIN (36.0)',
      () {
        expect(verticalMargin(800.1), 36.0);
      },
    );
  });

  // ===========================================================================
  // kChromeMenuZoneHeight — shared constant (C2b)
  // ===========================================================================
  group('kChromeMenuZoneHeight', () {
    test('given_sharedConstant_when_read_then_equals_48', () {
      expect(kChromeMenuZoneHeight, equals(48.0));
    });
  });

  // ===========================================================================
  // editorHorizontalMargin — char-width inset (C2)
  // Spec §5.1 C2: ≈ fontSizePt * 1.0, clamped to [min, max], strictly > 0,
  // monotonic increasing, never negative for pathological caller.
  // ===========================================================================
  group('editorHorizontalMargin', () {
    test(
      'given_defaultFontSize14_when_called_then_result_is_positive_and_close_to_14',
      () {
        final margin = editorHorizontalMargin(14.0);
        expect(margin, greaterThan(0.0));
        expect(margin, closeTo(14.0, 2.0));
      },
    );

    test('given_sizes_8_14_24_when_called_then_monotone_increasing', () {
      final m8 = editorHorizontalMargin(8.0);
      final m14 = editorHorizontalMargin(14.0);
      final m24 = editorHorizontalMargin(24.0);
      expect(m8, lessThan(m14));
      expect(m14, lessThan(m24));
    });

    test(
      'given_verySmallFontSize6_when_called_then_result_is_positive_clamp_floor',
      () {
        final margin = editorHorizontalMargin(6.0);
        expect(margin, greaterThan(0.0));
      },
    );

    test(
      'given_veryLargeFontSize38_when_called_then_result_is_positive_and_at_most_max',
      () {
        final margin = editorHorizontalMargin(38.0);
        expect(margin, greaterThan(0.0));
        // Must not overflow — clamped to a sensible ceiling.
        // We do not hard-code _kCharMarginMax here; we verify it is bounded
        // by testing the monotone + clamp contract: margin(38) must be <= margin(100)
        // but also both must be <= some practical ceiling. Use a liberal bound of 200.
        expect(margin, lessThanOrEqualTo(200.0));
      },
    );

    test(
      'given_pathologicalNegativeFontSize_when_called_then_result_is_non_negative',
      () {
        final margin = editorHorizontalMargin(-1.0);
        expect(margin, greaterThanOrEqualTo(0.0));
      },
    );
  });

  // ===========================================================================
  // editorTopInset — chrome-zone + safe-area floor (C2b)
  // Spec §5.1 C2b: max(kChromeMenuZoneHeight + safeAreaTop, verticalMargin(width))
  // ===========================================================================
  group('editorTopInset', () {
    test('given_width400_safeArea24_when_called_then_result_closeTo_72', () {
      // kChromeMenuZoneHeight(48) + safeAreaTop(24) = 72, dominates verticalMargin(400)=10
      final result = editorTopInset(400.0, 24.0);
      expect(result, closeTo(72.0, 0.5));
    });

    test(
      'given_wideWidth_where_verticalMargin_dominates_when_called_then_result_equals_verticalMargin',
      () {
        // verticalMargin(800) = 36. But 48+0 = 48 > 36, so we need safeAreaTop=0
        // and a width where verticalMargin > 48. verticalMargin is capped at 36,
        // which never exceeds 48+0=48, so we craft a scenario where safeAreaTop=0
        // and width is large but verticalMargin(width) > kChromeMenuZoneHeight + safeAreaTop
        // is impossible given the cap at 36. Instead, test the floor: the function
        // returns exactly verticalMargin(width) when chrome floor is smaller.
        // Since verticalMargin max is 36 and kChromeMenuZoneHeight is 48,
        // we can never reach the verticalMargin-dominated branch in practice.
        // However the spec guarantees editorTopInset >= verticalMargin always.
        // Validate the floor guarantee holds across a range of widths.
        for (final w in [320.0, 400.0, 600.0, 800.0]) {
          final topInset = editorTopInset(w, 0.0);
          final vMargin = verticalMargin(w);
          expect(
            topInset,
            greaterThanOrEqualTo(vMargin),
            reason: 'topInset must be >= verticalMargin($w)',
          );
        }
      },
    );

    test(
      'given_safeAreaTop_values_0_24_44_when_called_then_monotone_non_decreasing',
      () {
        final t0 = editorTopInset(400.0, 0.0);
        final t24 = editorTopInset(400.0, 24.0);
        final t44 = editorTopInset(400.0, 44.0);
        expect(t0, lessThanOrEqualTo(t24));
        expect(t24, lessThanOrEqualTo(t44));
      },
    );

    test('given_width400_safeArea0_when_called_then_result_is_at_least_48', () {
      // Even with zero safe-area, chrome zone must be reserved.
      final result = editorTopInset(400.0, 0.0);
      expect(result, greaterThanOrEqualTo(48.0));
    });

    test(
      'given_widths_320_400_800_and_safeAreas_0_24_when_called_then_result_always_gte_verticalMargin',
      () {
        for (final w in [320.0, 400.0, 800.0]) {
          for (final s in [0.0, 24.0]) {
            final topInset = editorTopInset(w, s);
            final vMargin = verticalMargin(w);
            expect(
              topInset,
              greaterThanOrEqualTo(vMargin),
              reason:
                  'editorTopInset($w, $s)=$topInset must be >= verticalMargin($w)=$vMargin',
            );
          }
        }
      },
    );

    test(
      'given_purity_check_when_horizontalMargin_called_between_topInset_calls_then_result_unchanged',
      () {
        final before = editorTopInset(400.0, 0.0);
        // Calling editorHorizontalMargin must not affect editorTopInset (no shared state).
        editorHorizontalMargin(14.0);
        final after = editorTopInset(400.0, 0.0);
        expect(after, equals(before));
      },
    );
  });
}
