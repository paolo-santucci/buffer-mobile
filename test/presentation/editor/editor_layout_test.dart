// Tests for lib/presentation/editor/editor_layout.dart
//
// Margin constants trace to ui-design-bible.md §Spacing-layout "Editor margins":
//   BASE_MARGIN = 36  (editor_text_view.rs:10)
//   MINIMUM_MARGIN = 10  (editor_text_view.rs:11)
// Interpolation formula: update_margins (editor_text_view.rs:375-395).
// The ceiling is fixed at 800 (line-length feature dropped, OQ-M7-04).

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
}
