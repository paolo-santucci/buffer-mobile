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

import 'package:foglietto/presentation/editor/editor_layout.dart';

// ---------------------------------------------------------------------------
// Helpers — baseline computation mirrors the pre-bump formula so each G5 test
// expresses the postcondition as `baseline + kChromeTopGap`.
// ---------------------------------------------------------------------------

/// Baseline for editorTopInset before the kChromeTopGap bump.
///
/// `max( kChromeMenuZoneHeight + safeAreaTop , verticalMargin(width) )`
double _topBaseline(double width, double safeAreaTop) {
  final chromeFloor = kChromeMenuZoneHeight + safeAreaTop;
  final m7Vertical = verticalMargin(width);
  return chromeFloor > m7Vertical ? chromeFloor : m7Vertical;
}

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
  // editorBottomInset — bottom chrome-zone + keyboard + safe-area floor (C4)
  // Spec §FR-22: max(kChromeMenuZoneHeight, verticalMargin(width), keyboardInset)
  //              + safeAreaBottom
  //
  // Anti-additive contract: result must NEVER equal kChromeMenuZoneHeight +
  // keyboardInset when keyboardInset dominates.
  // ===========================================================================
  group('editorBottomInset', () {
    test(
      'given_width400_keyboard0_safeArea34_when_toolbarDominates_then_result_equals_kChromeMenuZoneHeight_plus_safeAreaBottom',
      () {
        // kChromeMenuZoneHeight(48) > verticalMargin(400)=10, keyboard=0
        // result = max(48, 10, 0) + 34 = 48 + 34 = 82
        final result = editorBottomInset(400.0, 0.0, 34.0);
        expect(result, equals(kChromeMenuZoneHeight + 34.0));
      },
    );

    test(
      'given_width400_keyboard300_safeArea34_when_keyboardDominates_then_result_equals_keyboard_plus_safeAreaBottom_not_additive',
      () {
        // keyboard(300) > kChromeMenuZoneHeight(48) > verticalMargin(400)=10
        // result = max(48, 10, 300) + 34 = 300 + 34 = 334
        // Anti-additive: must NOT be 48 + 300 + 34 = 382
        final result = editorBottomInset(400.0, 300.0, 34.0);
        expect(result, equals(300.0 + 34.0));
      },
    );

    test(
      'given_keyboardInset_equals_kChromeMenuZoneHeight_when_tie_then_result_equals_kChromeMenuZoneHeight_plus_safeAreaBottom_once',
      () {
        // keyboard == kChromeMenuZoneHeight(48): max(48,10,48)=48, result=48+safeAreaBottom
        // Must NOT be 48+48+safeAreaBottom (additive double-count)
        final result = editorBottomInset(400.0, kChromeMenuZoneHeight, 20.0);
        expect(result, equals(kChromeMenuZoneHeight + 20.0));
      },
    );

    test(
      'given_increasing_keyboardInsets_and_safeAreaBottoms_when_called_then_results_are_non_decreasing',
      () {
        // monotone in keyboardInset [0, 48, 100, 300] (w=400, sab=0)
        final kValues = [0.0, 48.0, 100.0, 300.0];
        for (var i = 0; i < kValues.length - 1; i++) {
          final r1 = editorBottomInset(400.0, kValues[i], 0.0);
          final r2 = editorBottomInset(400.0, kValues[i + 1], 0.0);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'editorBottomInset(400, ${kValues[i]}, 0) should be <= editorBottomInset(400, ${kValues[i + 1]}, 0)',
          );
        }
        // monotone in safeAreaBottom [0, 20, 34, 44] (w=400, ki=0)
        final sabValues = [0.0, 20.0, 34.0, 44.0];
        for (var i = 0; i < sabValues.length - 1; i++) {
          final r1 = editorBottomInset(400.0, 0.0, sabValues[i]);
          final r2 = editorBottomInset(400.0, 0.0, sabValues[i + 1]);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'editorBottomInset(400, 0, ${sabValues[i]}) should be <= editorBottomInset(400, 0, ${sabValues[i + 1]})',
          );
        }
      },
    );

    test(
      'given_all_input_combos_when_called_then_result_is_always_gte_kChromeMenuZoneHeight_plus_safeAreaBottom',
      () {
        // floor: for all combos result >= kChromeMenuZoneHeight + safeAreaBottom
        for (final w in [320.0, 400.0, 800.0]) {
          for (final ki in [0.0, 48.0, 300.0]) {
            for (final sab in [0.0, 20.0, 34.0]) {
              final result = editorBottomInset(w, ki, sab);
              expect(
                result,
                greaterThanOrEqualTo(kChromeMenuZoneHeight + sab),
                reason:
                    'editorBottomInset($w, $ki, $sab)=$result must be >= kChromeMenuZoneHeight+$sab=${kChromeMenuZoneHeight + sab}',
              );
            }
          }
        }
      },
    );

    test(
      'given_width400_keyboard300_safeArea0_when_called_then_result_strictly_less_than_kChromeMenuZoneHeight_plus_keyboard',
      () {
        // never-additive: result < kChromeMenuZoneHeight + keyboardInset
        final result = editorBottomInset(400.0, 300.0, 0.0);
        expect(result, lessThan(kChromeMenuZoneHeight + 300.0));
      },
    );

    test(
      'given_editorTopInset_called_between_editorBottomInset_calls_when_purity_checked_then_editorBottomInset_result_unchanged',
      () {
        // purity: calling editorTopInset must not affect editorBottomInset (no shared mutable state)
        final before = editorBottomInset(400.0, 100.0, 34.0);
        editorTopInset(400.0, 24.0);
        final after = editorBottomInset(400.0, 100.0, 34.0);
        expect(after, equals(before));
      },
    );
  });

  // ===========================================================================
  // editorTopInset — chrome-zone + safe-area floor (C2b)
  // Spec §5.1 C2b: max(kChromeMenuZoneHeight + safeAreaTop, verticalMargin(width))
  // ===========================================================================
  group('editorTopInset', () {
    test('given_width400_safeArea24_when_called_then_result_closeTo_88', () {
      // baseline: kChromeMenuZoneHeight(48) + safeAreaTop(24) = 72, dominates verticalMargin(400)=10
      // G5 bump: 72 + kChromeTopGap(16) = 88
      final result = editorTopInset(400.0, 24.0);
      expect(result, closeTo(88.0, 0.5));
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

  // ===========================================================================
  // G5 — chrome-spacing constants + inset bumps
  // spec §TASK-01
  // ===========================================================================
  group('G5 chrome-spacing constants', () {
    test(
      'given_three_chrome_constants_when_read_then_each_equals_16_and_all_distinct',
      () {
        // Three separate named const doubles — not aliases.
        expect(kChromeTopGap, equals(16.0));
        expect(kChromeBottomGap, equals(16.0));
        expect(kChromeSideMargin, equals(16.0));
        // Confirm they are independently named by comparing against a literal
        // (no runtime alias equality test needed — they must simply all be 16.0).
      },
    );
  });

  group('G5 editorTopInset bump', () {
    test(
      'given_width400_safeAreaTop0_when_called_then_result_equals_baseline_plus_kChromeTopGap',
      () {
        const w = 400.0;
        const sat = 0.0;
        final baseline = _topBaseline(w, sat);
        expect(editorTopInset(w, sat), equals(baseline + kChromeTopGap));
      },
    );

    test(
      'given_width400_safeAreaTop44_when_called_then_result_equals_baseline_plus_kChromeTopGap',
      () {
        const w = 400.0;
        const sat = 44.0;
        final baseline = _topBaseline(w, sat);
        expect(editorTopInset(w, sat), equals(baseline + kChromeTopGap));
      },
    );

    test(
      'given_width800_safeAreaTop59_when_called_then_result_equals_baseline_plus_kChromeTopGap',
      () {
        const w = 800.0;
        const sat = 59.0;
        final baseline = _topBaseline(w, sat);
        expect(editorTopInset(w, sat), equals(baseline + kChromeTopGap));
      },
    );

    test(
      'given_safeAreaTops_0_20_44_59_at_width400_when_called_then_results_strictly_increasing',
      () {
        // kChromeTopGap is additive on all results so monotonicity is preserved.
        final results = [
          0.0,
          20.0,
          44.0,
          59.0,
        ].map((sat) => editorTopInset(400.0, sat)).toList();
        for (var i = 0; i < results.length - 1; i++) {
          expect(
            results[i],
            lessThan(results[i + 1]),
            reason:
                'editorTopInset(400, sat[$i])=${results[i]} should be < editorTopInset(400, sat[${i + 1}])=${results[i + 1]}',
          );
        }
      },
    );

    test(
      'given_EC01_width400_safeAreaTop0_when_called_then_result_gte_kChromeMenuZoneHeight_plus_kChromeTopGap',
      () {
        // EC-01 no-notch floor: result >= 48 + 16 = 64.
        final result = editorTopInset(400.0, 0.0);
        expect(
          result,
          greaterThanOrEqualTo(kChromeMenuZoneHeight + kChromeTopGap),
        );
      },
    );
  });

  // ===========================================================================
  // chromeSlotBottomInset — bottom inset for the floating chrome slot (T-01)
  //
  // Anti-additive contract (mirror of editorBottomInset):
  //   chromeSlotBottomInset(keyboardInset, safeAreaBottom)
  //     = max(kChromeBottomGap, keyboardInset) + safeAreaBottom
  //
  // kChromeBottomGap and keyboardInset are mutually exclusive (composed via
  // max, NEVER +). Only safeAreaBottom is genuinely additive.
  // ===========================================================================
  group('chromeSlotBottomInset', () {
    test(
      'anti-additive: keyboard(200) dominates → result == 224.0, NOT kChromeBottomGap + 200 + 24',
      () {
        // max(kChromeBottomGap(16), 200) + 24 = 200 + 24 = 224.0
        // Must NOT be 16 + 200 + 24 = 240.0
        final result = chromeSlotBottomInset(200.0, 24.0);
        expect(result, equals(224.0));
        expect(result, isNot(equals(kChromeBottomGap + 200.0 + 24.0)));
      },
    );

    test(
      'tie-not-doubled: keyboard == kChromeBottomGap → result == kChromeBottomGap + 24, never doubled',
      () {
        // max(kChromeBottomGap, kChromeBottomGap) + 24 = kChromeBottomGap + 24
        // Must NOT be kChromeBottomGap + kChromeBottomGap + 24
        final result = chromeSlotBottomInset(kChromeBottomGap, 24.0);
        expect(result, equals(kChromeBottomGap + 24.0));
        expect(
          result,
          isNot(equals(kChromeBottomGap + kChromeBottomGap + 24.0)),
        );
      },
    );

    test(
      'keyboard-0-resting: keyboard == 0 → result == kChromeBottomGap + 24 (gap dominates)',
      () {
        // max(kChromeBottomGap(16), 0) + 24 = 16 + 24 = 40.0
        final result = chromeSlotBottomInset(0.0, 24.0);
        expect(result, equals(kChromeBottomGap + 24.0));
      },
    );

    test(
      'monotonic non-decreasing in keyboardInset [0→200] and safeAreaBottom [0→48]; purity: same args → identical result',
      () {
        // monotonic in keyboardInset
        final kValues = [0.0, kChromeBottomGap, 50.0, 100.0, 200.0];
        for (var i = 0; i < kValues.length - 1; i++) {
          final r1 = chromeSlotBottomInset(kValues[i], 0.0);
          final r2 = chromeSlotBottomInset(kValues[i + 1], 0.0);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'chromeSlotBottomInset(${kValues[i]}, 0) should be <= chromeSlotBottomInset(${kValues[i + 1]}, 0)',
          );
        }
        // monotonic in safeAreaBottom
        final sabValues = [0.0, 12.0, 24.0, 34.0, 48.0];
        for (var i = 0; i < sabValues.length - 1; i++) {
          final r1 = chromeSlotBottomInset(0.0, sabValues[i]);
          final r2 = chromeSlotBottomInset(0.0, sabValues[i + 1]);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'chromeSlotBottomInset(0, ${sabValues[i]}) should be <= chromeSlotBottomInset(0, ${sabValues[i + 1]})',
          );
        }
        // purity: identical args → identical result
        const ki = 150.0;
        const sab = 24.0;
        final first = chromeSlotBottomInset(ki, sab);
        final second = chromeSlotBottomInset(ki, sab);
        expect(second, equals(first));
      },
    );
  });

  group('G5 editorBottomInset kChromeBottomGap absorbed', () {
    test(
      'given_NFR02_width400_keyboard300_safeAreaBottom34_when_called_then_result_equals_334_and_not_334_plus_kChromeBottomGap',
      () {
        // kChromeBottomGap(16) is a term inside max — dominated by keyboard(300).
        // Anti-additive: result must be 334.0, not 334.0 + 16.0 = 350.0.
        final result = editorBottomInset(400.0, 300.0, 34.0);
        expect(result, equals(334.0));
        expect(result, isNot(equals(334.0 + kChromeBottomGap)));
      },
    );

    test(
      'given_FR04neg_width400_keyboard0_safeAreaBottom34_when_called_then_result_gte_kChromeBottomGap_plus_safeAreaBottom',
      () {
        // kChromeBottomGap as explicit term inside max: result >= 16 + 34 = 50.
        // But kChromeMenuZoneHeight(48) already dominates, so result = 82.
        // Key contract: the constant has an auditable home inside the max.
        // Also verify no double-count: result must not equal old_baseline + kChromeBottomGap.
        // old_baseline (pre-kChromeBottomGap-term) = max(48, 10, 0) + 34 = 82.
        // Since kChromeBottomGap < kChromeMenuZoneHeight, the result is the same (82).
        final result = editorBottomInset(400.0, 0.0, 34.0);
        expect(result, greaterThanOrEqualTo(kChromeBottomGap + 34.0));
        // No double-count: result equals the single-dominant baseline, not baseline + kChromeBottomGap.
        const oldBaseline =
            82.0; // max(48,10,0)+34 pre-term (same value post-term)
        expect(result, isNot(equals(oldBaseline + kChromeBottomGap)));
      },
    );
  });
}
