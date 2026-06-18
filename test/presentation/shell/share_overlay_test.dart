// Tests for ShareOverlay → RETIRED (TASK-06)
//
// share_overlay.dart has been deleted and superseded by ChromePill.
// See lib/presentation/shell/chrome_pill.dart and
//     test/presentation/shell/chrome_pill_test.dart.
//
// Spec refs: FR-01, FR-02, FR-03, NFR-03 (twin-mirror retirement)
// Plan refs: sp-20260617-liquid-glass-floating-chrome-plan.md TASK-06
//
// OLD → NEW migration (spec §7.1):
//
//   OLD assertion in this file (gate-10)           NEW location / status
//   ──────────────────────────────────────────     ─────────────────────────────────────────
//   left: 0 (Positioned, delta 1)                 REMOVED — ChromePill is Positioned(right:0).
//                                                  The twin-mirror "left+right" split is retired.
//                                                  → chrome_pill_test §9 layerLink (Positioned top-right)
//   bottomRight: Radius.circular(8) (delta 2)     Superseded by GlassSurface(pillRadius — fully rounded).
//                                                  → chrome_pill_test §4 glass surface
//   Icons.ios_share (delta 3)                     Still used in ChromePill share button (CANON GAP OQ-10).
//                                                  → chrome_pill_test §5 accessibility (Tooltip "Share")
//   enabled gate → onPressed == null              Moved to ChromePill: bufferProvider text empty/whitespace
//                                                  → onPressed null (FR-03).
//                                                  → chrome_pill_test §1 share-enable gate
//   enabled:false tap → 0 calls                   → chrome_pill_test §2 EC-01
//   chromeVisibilityProvider auto-hide             → chrome_pill_test §3 auto-hide
//   ≥48dp in all states                           → chrome_pill_test §5 accessibility
//   kChromeMenuZoneHeight reference               kChromeMenuZoneHeight constant still == 48.0
//   no ScrollController/jumpTo/animateTo          → chrome_pill_test (no banned transitions)
//   Tooltip "Share" / "Condividi"                 → chrome_pill_test §5 accessibility
//
// The NEW assertions below confirm:
//   1. share_overlay.dart is ABSENT (retirement confirmed).
//   2. ChromePill file EXISTS (replacement confirmed).
//   3. kChromeMenuZoneHeight == 48.0 (constant preserved).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/presentation/editor/editor_layout.dart'
    show kChromeMenuZoneHeight;

void main() {
  // =========================================================================
  // Retirement confirmation: share_overlay.dart must be absent
  // =========================================================================
  group('ShareOverlay — RETIRED (TASK-06)', () {
    test('given_project_when_inspected_then_share_overlay_dart_is_absent', () {
      const oldPath = 'lib/presentation/shell/share_overlay.dart';
      expect(
        File(oldPath).existsSync(),
        isFalse,
        reason:
            'share_overlay.dart must be deleted — superseded by ChromePill '
            '(TASK-06, spec §4.1 twin-mirror retirement). '
            'The gate-10 "left: 0" assertion is removed; the twin-mirror '
            '"left+right" invariant is retired entirely. '
            'All former assertions retargeted to '
            'test/presentation/shell/chrome_pill_test.dart.',
      );
    });

    test('given_project_when_inspected_then_chrome_pill_dart_exists', () {
      const newPath = 'lib/presentation/shell/chrome_pill.dart';
      expect(
        File(newPath).existsSync(),
        isTrue,
        reason:
            'chrome_pill.dart must exist — the replacement for '
            'chrome_overlay.dart + share_overlay.dart (TASK-06)',
      );
    });

    // kChromeMenuZoneHeight is still exported from editor_layout.dart
    // and still equals 48dp — consumers that call editorTopInset() are unbroken.
    test(
      'given_sharedConstant_when_read_then_kChromeMenuZoneHeight_equals_48',
      () {
        expect(
          kChromeMenuZoneHeight,
          equals(48.0),
          reason:
              'kChromeMenuZoneHeight must still equal 48.0 after ShareOverlay '
              'retirement (C2b coupling invariant)',
        );
      },
    );
  });
}
