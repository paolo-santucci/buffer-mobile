// Tests for ChromeOverlay → RETIRED (TASK-06)
//
// chrome_overlay.dart has been deleted and superseded by ChromePill.
// See lib/presentation/shell/chrome_pill.dart and
//     test/presentation/shell/chrome_pill_test.dart.
//
// Spec refs: FR-01, NFR-03 (twin-mirror retirement)
// Plan refs: sp-20260617-liquid-glass-floating-chrome-plan.md TASK-06
//
// OLD → NEW migration (spec §7.1):
//
//   OLD assertions in this file                  NEW location
//   ─────────────────────────────────────────    ──────────────────────────────
//   right: 0 top-end Positioned placement       ChromePill is Positioned(top:0, right:0)
//                                                → chrome_pill_test §9 layerLink (CompositedTransformTarget)
//   bottomLeft: Radius.circular(8) radius       Superseded by GlassSurface(pillRadius)
//                                                → chrome_pill_test §4 glass surface
//   chromeVisibilityProvider auto-hide          AnimatedOpacity + IgnorePointer in ChromePill
//                                                → chrome_pill_test §3 auto-hide
//   ≥48dp tap target                            Both buttons ≥48dp in ChromePill
//                                                → chrome_pill_test §5 accessibility
//   menuTooltip Semantics                       menuTooltip on overflow … button in ChromePill
//                                                → chrome_pill_test §5 accessibility
//   no ScrollController/jumpTo/animateTo        Structural invariant still holds in ChromePill
//                                                → chrome_pill_test (no banned transitions)
//   kChromeMenuZoneHeight coupling (C2b)        Constant still exported from editor_layout.dart;
//                                                ChromePill uses _kButtonSize (48dp) directly
//                                                → test still verifies kChromeMenuZoneHeight == 48
//
// The NEW assertions below confirm:
//   1. chrome_overlay.dart is ABSENT (retirement confirmed).
//   2. ChromePill file EXISTS (replacement confirmed).
//   3. kChromeMenuZoneHeight == 48.0 (constant value preserved, coupling unbroken).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/presentation/editor/editor_layout.dart'
    show kChromeMenuZoneHeight;

void main() {
  // =========================================================================
  // Retirement confirmation: chrome_overlay.dart must be absent
  // =========================================================================
  group('ChromeOverlay — RETIRED (TASK-06)', () {
    test('given_project_when_inspected_then_chrome_overlay_dart_is_absent', () {
      const oldPath = 'lib/presentation/shell/chrome_overlay.dart';
      expect(
        File(oldPath).existsSync(),
        isFalse,
        reason:
            'chrome_overlay.dart must be deleted — superseded by ChromePill '
            '(TASK-06, spec §4.1 twin-mirror retirement). '
            'All former assertions have been retargeted to '
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
    // and still equals 48dp — the coupling invariant is preserved even
    // though ChromePill now uses its own _kButtonSize (48.0) internally.
    test(
      'given_sharedConstant_when_read_then_kChromeMenuZoneHeight_equals_48',
      () {
        expect(
          kChromeMenuZoneHeight,
          equals(48.0),
          reason:
              'kChromeMenuZoneHeight must still equal 48.0 after ChromeOverlay '
              'retirement — consumers that read it for layout arithmetic '
              '(e.g. editorTopInset) must not be broken (C2b)',
        );
      },
    );
  });
}
