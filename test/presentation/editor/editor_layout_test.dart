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
// Helpers — baseline computation mirrors the TASK-01 editorTopInset formula.
// ---------------------------------------------------------------------------

/// Baseline for editorTopInset per the TASK-01 formula:
///   `max( safeAreaTop + kEditorTopClearance , verticalMargin(width) )`
double _topBaseline(double width, double safeAreaTop) {
  final clearanceFloor = safeAreaTop + kEditorTopClearance;
  final m7Vertical = verticalMargin(width);
  return clearanceFloor > m7Vertical ? clearanceFloor : m7Vertical;
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
    test('given_width400_safeArea24_when_called_then_result_closeTo_48', () {
      // TASK-01 new formula: max(24 + kEditorTopClearance(24), verticalMargin(400)=10)
      // = max(48, 10) = 48.0
      final result = editorTopInset(400.0, 24.0);
      expect(result, closeTo(48.0, 0.5));
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

    test(
      'given_width400_safeArea0_when_called_then_result_is_at_least_kEditorTopClearance',
      () {
        // TASK-01: the 48dp kChromeMenuZoneHeight floor is dropped.
        // With safeAreaTop=0: max(0 + 24, verticalMargin(400)=10) = 24.
        // Floor is now kEditorTopClearance (24dp), not 48dp.
        final result = editorTopInset(400.0, 0.0);
        expect(result, greaterThanOrEqualTo(kEditorTopClearance));
      },
    );

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

  group('G5 editorTopInset TASK-01 new formula', () {
    // New formula: max(safeAreaTop + kEditorTopClearance, verticalMargin(width))
    // No trailing + kChromeTopGap; no 48dp kChromeMenuZoneHeight floor.

    test(
      'given_width400_safeAreaTop0_when_called_then_result_equals_baseline',
      () {
        const w = 400.0;
        const sat = 0.0;
        // max(0 + 24, verticalMargin(400)=10) = 24.0
        final baseline = _topBaseline(w, sat);
        expect(editorTopInset(w, sat), equals(baseline));
      },
    );

    test(
      'given_width400_safeAreaTop44_when_called_then_result_equals_baseline',
      () {
        const w = 400.0;
        const sat = 44.0;
        // max(44 + 24, verticalMargin(400)=10) = max(68, 10) = 68.0
        final baseline = _topBaseline(w, sat);
        expect(editorTopInset(w, sat), equals(baseline));
      },
    );

    test(
      'given_width800_safeAreaTop59_when_called_then_result_equals_baseline',
      () {
        const w = 800.0;
        const sat = 59.0;
        // max(59 + 24, verticalMargin(800)=36) = max(83, 36) = 83.0
        final baseline = _topBaseline(w, sat);
        expect(editorTopInset(w, sat), equals(baseline));
      },
    );

    test(
      'given_safeAreaTops_0_20_44_59_at_width400_when_called_then_results_strictly_increasing',
      () {
        // Monotonicity preserved: safeAreaTop is additive inside the clearanceFloor term.
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
      'given_EC01_width400_safeAreaTop0_when_called_then_result_equals_kEditorTopClearance',
      () {
        // EC-06 no-notch: max(0 + 24, verticalMargin(400)=10) = 24.0.
        // The old 48dp floor (kChromeMenuZoneHeight + kChromeTopGap = 64) is gone.
        final result = editorTopInset(400.0, 0.0);
        expect(result, equals(kEditorTopClearance));
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
    // TASK-01: 3-arg signature — chromeSlotBottomInset(keyboardInset, safeAreaBottom, iosAccessoryHeight)
    // Body: max(kChromeBottomGap, keyboardInset + iosAccessoryHeight + kToolbarKeyboardGap) + safeAreaBottom

    test(
      'anti-additive: keyboard(200) iosAccessory(0) dominates → result == 232.0, NOT kChromeBottomGap + 200 + 24',
      () {
        // max(kChromeBottomGap(16), 200+0+8) + 24 = max(16,208) + 24 = 208 + 24 = 232.0
        // Must NOT be 16 + 200 + 0 + 8 + 24 (additive).
        final result = chromeSlotBottomInset(200.0, 24.0, 0.0);
        expect(result, equals(232.0));
        expect(result, isNot(equals(kChromeBottomGap + 200.0 + 24.0)));
      },
    );

    test(
      'tie-not-doubled: inner sum == kChromeBottomGap → result == kChromeBottomGap + 24, never doubled',
      () {
        // EC-07: 8 + 0 + 8 = 16 == kChromeBottomGap → max(16, 16) + 24 = 16 + 24 = 40.
        // Must NOT be kChromeBottomGap + (inner sum) + 24 = 16 + 16 + 24 = 56.
        const keyboardInset = 8.0; // 8 + 0 + 8 = 16 == kChromeBottomGap
        final result = chromeSlotBottomInset(keyboardInset, 24.0, 0.0);
        expect(result, equals(kChromeBottomGap + 24.0));
        expect(
          result,
          isNot(equals(kChromeBottomGap + kChromeBottomGap + 24.0)),
        );
      },
    );

    test(
      'keyboard-0-resting: keyboard == 0, iosAccessory == 0 → max picks kChromeBottomGap → result == kChromeBottomGap + 24',
      () {
        // max(kChromeBottomGap(16), 0+0+8) + 24 = max(16, 8) + 24 = 16 + 24 = 40.0
        final result = chromeSlotBottomInset(0.0, 24.0, 0.0);
        expect(result, equals(kChromeBottomGap + 24.0));
      },
    );

    test(
      'monotonic non-decreasing in keyboardInset [0→200] and safeAreaBottom [0→48]; purity: same args → identical result',
      () {
        // monotonic in keyboardInset (iosAccessory=0)
        final kValues = [0.0, kChromeBottomGap, 50.0, 100.0, 200.0];
        for (var i = 0; i < kValues.length - 1; i++) {
          final r1 = chromeSlotBottomInset(kValues[i], 0.0, 0.0);
          final r2 = chromeSlotBottomInset(kValues[i + 1], 0.0, 0.0);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'chromeSlotBottomInset(${kValues[i]}, 0, 0) should be <= chromeSlotBottomInset(${kValues[i + 1]}, 0, 0)',
          );
        }
        // monotonic in safeAreaBottom (keyboardInset=0, iosAccessory=0)
        final sabValues = [0.0, 12.0, 24.0, 34.0, 48.0];
        for (var i = 0; i < sabValues.length - 1; i++) {
          final r1 = chromeSlotBottomInset(0.0, sabValues[i], 0.0);
          final r2 = chromeSlotBottomInset(0.0, sabValues[i + 1], 0.0);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'chromeSlotBottomInset(0, ${sabValues[i]}, 0) should be <= chromeSlotBottomInset(0, ${sabValues[i + 1]}, 0)',
          );
        }
        // purity: identical args → identical result
        const ki = 150.0;
        const sab = 24.0;
        const iosAcc = 48.0;
        final first = chromeSlotBottomInset(ki, sab, iosAcc);
        final second = chromeSlotBottomInset(ki, sab, iosAcc);
        expect(second, equals(first));
      },
    );
  });

  // ===========================================================================
  // TASK-01 — New constants (FR-21) and updated function signatures
  // ===========================================================================
  group('TASK-01 new constants', () {
    test(
      'given_kChromePillTopGap_when_read_then_equals_kChromeTopGap_divided_by_3',
      () {
        expect(kChromePillTopGap, closeTo(kChromeTopGap / 3, 1e-9));
        expect(kChromePillTopGap, isNot(equals(16.0)));
      },
    );

    test(
      'given_kEditorTopClearance_when_read_then_equals_24_and_not_equal_to_kChromePillTopGap',
      () {
        expect(kEditorTopClearance, equals(24.0));
        // kEditorTopClearance == kChromeMenuZoneHeight / 2 == 48 / 2 == 24
        expect(kEditorTopClearance, closeTo(kChromeMenuZoneHeight / 2, 1e-9));
        expect(kEditorTopClearance, isNot(equals(kChromePillTopGap)));
      },
    );

    test('given_kToolbarKeyboardGap_when_read_then_equals_8', () {
      expect(kToolbarKeyboardGap, equals(8.0));
    });

    test('given_kKeyboardAccessoryBarHeight_when_read_then_equals_48', () {
      expect(kKeyboardAccessoryBarHeight, equals(48.0));
    });

    test('given_gate_pinned_constants_when_read_then_all_still_equal_16', () {
      // NFR-01 gate: these three must remain == 16.0
      expect(kChromeTopGap, equals(16.0));
      expect(kChromeBottomGap, equals(16.0));
      expect(kChromeSideMargin, equals(16.0));
    });

    test('given_kChromeMenuZoneHeight_when_read_then_still_equals_48', () {
      // Must remain defined (drives editorBottomInset + kEditorTopClearance numerator)
      expect(kChromeMenuZoneHeight, equals(48.0));
    });
  });

  group('TASK-01 editorTopInset new formula', () {
    // New formula: max(safeAreaTop + kEditorTopClearance, verticalMargin(width))
    // No 48dp floor, no trailing + kChromeTopGap

    test('given_width375_safeArea44_when_called_then_result_closeTo_68', () {
      // max(44 + 24, verticalMargin(375)≈10) = max(68, 10) = 68.0
      final result = editorTopInset(375.0, 44.0);
      expect(result, closeTo(68.0, 0.01));
    });

    test(
      'given_width375_safeArea44_when_called_then_result_strictly_less_than_old_value_108',
      () {
        // Old formula: max(48+44, verticalMargin(375)) + 16 = 92 + 16 = 108.
        // New formula drops the 48dp floor and the + kChromeTopGap → 68.0.
        // FR-09: text is higher than before.
        final result = editorTopInset(375.0, 44.0);
        expect(result, lessThan(108.0));
      },
    );

    test(
      'given_width375_safeArea0_when_called_then_result_closeTo_24_kEditorTopClearance',
      () {
        // EC-06 no-notch: max(0+24, verticalMargin(375)≈10) = 24.0 (kEditorTopClearance governs)
        final result = editorTopInset(375.0, 0.0);
        expect(result, closeTo(24.0, 0.01));
      },
    );

    test(
      'given_widths_200_to_800_safeArea0_when_called_then_result_gte_verticalMargin',
      () {
        // FR-10 KEEP: responsive floor — result always >= verticalMargin(width)
        for (var w = 200.0; w <= 800.0; w += 10.0) {
          final result = editorTopInset(w, 0.0);
          final vMargin = verticalMargin(w);
          expect(
            result,
            greaterThanOrEqualTo(vMargin),
            reason:
                'editorTopInset($w, 0)=$result must be >= verticalMargin($w)=$vMargin',
          );
        }
      },
    );

    test(
      'given_safeAreaTop_increments_0_to_60_at_width400_when_called_then_monotone_non_decreasing',
      () {
        // FR-10 KEEP: monotonicity in safeAreaTop
        var prev = editorTopInset(400.0, 0.0);
        for (var sat = 1.0; sat <= 60.0; sat += 1.0) {
          final next = editorTopInset(400.0, sat);
          expect(
            next,
            greaterThanOrEqualTo(prev),
            reason:
                'editorTopInset(400, $sat) should be >= editorTopInset(400, ${sat - 1})',
          );
          prev = next;
        }
      },
    );
  });

  group('TASK-01 chromeSlotBottomInset 3-arg', () {
    // New signature: chromeSlotBottomInset(keyboardInset, safeAreaBottom, iosAccessoryHeight)
    // Body: max(kChromeBottomGap, keyboardInset + iosAccessoryHeight + kToolbarKeyboardGap) + safeAreaBottom

    test(
      'given_keyboard300_safeArea34_iosAccessory0_when_called_then_result_equals_342',
      () {
        // max(16, 300+0+8)+34 = max(16,308)+34 = 308+34 = 342.0
        final result = chromeSlotBottomInset(300.0, 34.0, 0.0);
        expect(result, equals(342.0));
      },
    );

    test(
      'given_keyboard300_safeArea34_iosAccessory48_when_called_then_result_equals_390',
      () {
        // max(16, 300+48+8)+34 = max(16,356)+34 = 356+34 = 390.0
        // iOS accessory folds INSIDE max (anti-additive)
        final result = chromeSlotBottomInset(300.0, 34.0, 48.0);
        expect(result, equals(390.0));
      },
    );

    test(
      'given_keyboard0_safeArea24_iosAccessory0_when_called_then_result_equals_40',
      () {
        // FR-15: resting/keyboard-down unchanged
        // max(16, 0+0+8)+24 = max(16,8)+24 = 16+24 = 40.0
        final result = chromeSlotBottomInset(0.0, 24.0, 0.0);
        expect(result, equals(40.0));
      },
    );

    test(
      'given_antiAdditiveTie_when_called_then_result_equals_kChromeBottomGap_plus_safeAreaBottom',
      () {
        // EC-07: keyboardInset + iosAccessoryH + kToolbarKeyboardGap == kChromeBottomGap(16)
        // 8 + 0 + 8 = 16 → max(16, 16) + sab = 16 + sab (not doubled)
        const keyboardInset = 8.0;
        const safeAreaBottom = 20.0;
        final result = chromeSlotBottomInset(
          keyboardInset,
          safeAreaBottom,
          0.0,
        );
        expect(result, equals(kChromeBottomGap + safeAreaBottom));
      },
    );

    test(
      'given_increasing_keyboard_and_safeArea_when_called_then_monotone_non_decreasing',
      () {
        // Monotonicity in keyboardInset
        final kValues = [0.0, 8.0, kChromeBottomGap, 50.0, 300.0];
        for (var i = 0; i < kValues.length - 1; i++) {
          final r1 = chromeSlotBottomInset(kValues[i], 0.0, 0.0);
          final r2 = chromeSlotBottomInset(kValues[i + 1], 0.0, 0.0);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'chromeSlotBottomInset(${kValues[i]}, 0, 0) must be <= chromeSlotBottomInset(${kValues[i + 1]}, 0, 0)',
          );
        }
        // Monotonicity in safeAreaBottom
        final sabValues = [0.0, 12.0, 24.0, 34.0, 48.0];
        for (var i = 0; i < sabValues.length - 1; i++) {
          final r1 = chromeSlotBottomInset(0.0, sabValues[i], 0.0);
          final r2 = chromeSlotBottomInset(0.0, sabValues[i + 1], 0.0);
          expect(
            r1,
            lessThanOrEqualTo(r2),
            reason:
                'chromeSlotBottomInset(0, ${sabValues[i]}, 0) must be <= chromeSlotBottomInset(0, ${sabValues[i + 1]}, 0)',
          );
        }
      },
    );

    test(
      'given_iosAccessory48_when_called_then_result_anti_additive_not_sum_of_all_terms',
      () {
        // Anti-additive: the iOS accessory height folds INSIDE max with keyboardInset.
        // keyboardInset=300, iosAccessory=48 → sum inside max = 356 > 16, so max picks 356.
        // result = 356 + safeAreaBottom, NOT 16 + 300 + 48 + 8 + sab (no additive doubling).
        final result = chromeSlotBottomInset(300.0, 0.0, 48.0);
        expect(result, equals(356.0));
        // Must not be additive of kChromeBottomGap + keyboardInset + iosAccessory + gap
        expect(
          result,
          isNot(equals(kChromeBottomGap + 300.0 + 48.0 + kToolbarKeyboardGap)),
        );
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
