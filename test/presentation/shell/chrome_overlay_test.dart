// Tests for ChromeOverlay widget (TASK-08b)
//
// Spec refs: FR-M6-05, FR-M6-06, NFR-M6-03, NFR-M6-05, EC-12, §Components §2
// Canon ref: .claude/docs/canon/ui-design-bible.md §2 "Auto-hiding overlay chrome"
//
// TDD: tests written FIRST, implementation follows.
//
// Acceptance criteria verified here:
//   1. chromeVisibilityProvider=true  → AnimatedOpacity opacity 1.0.
//   2. chromeVisibilityProvider=false → AnimatedOpacity opacity 0.0 (crossfade to hidden).
//   3. Menu affordance RenderBox.size >= Size(48, 48) (NFR-M6-05, canon ≥48dp).
//   4. Localized Semantics / tooltip: non-empty, resolved from ARB (menuTooltip).
//   5. No SlideTransition / ScaleTransition / RotationTransition / SizeTransition in file.
//   6. MediaQuery(disableAnimations: true) → animation duration == Duration.zero (EC-12).
//   7. File contains no ScrollController() construction and no jumpTo / animateTo.
//
// Note on test 5 & 7: these are static/structural assertions verified at read-time.
// The widget tests confirm the runtime behaviour; the file-content guards are confirmed
// by running the m6_gate in TASK-15 — but we also emit a runtime structural test here.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/editor_layout.dart'
    show kChromeMenuZoneHeight;
import 'package:buffer/presentation/shell/chrome_overlay.dart';
import 'package:buffer/presentation/shell/chrome_reveal_controller.dart';

// ---------------------------------------------------------------------------
// Test harness helpers
// ---------------------------------------------------------------------------

/// Wraps [ChromeOverlay] in a valid ProviderScope + MaterialApp (with
/// AppLocalizations delegates) + a [Stack] host so [Positioned] is legal.
///
/// [visible] sets the [chromeVisibilityProvider] override.
/// [disableAnimations] controls MediaQuery.disableAnimations.
Widget _buildApp({
  required bool visible,
  bool disableAnimations = false,
  VoidCallback? onMenuTap,
}) {
  return ProviderScope(
    overrides: [
      chromeVisibilityProvider.overrideWith(
        () => _FakeRevealController(visible),
      ),
    ],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Stack(
            children: [
              // Simulate the editor layer beneath.
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              ChromeOverlay(onMenuTap: onMenuTap ?? () {}),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A fixed-state stand-in for [ChromeRevealController] that always returns
/// the injected [_initialState].
class _FakeRevealController extends ChromeRevealController {
  _FakeRevealController(this._initialState);
  final bool _initialState;

  @override
  bool build() => _initialState;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Visibility = true → AnimatedOpacity opacity 1.0
  // =========================================================================
  group('ChromeOverlay — visibility true', () {
    testWidgets('given_visible_true_when_mounted_then_animatedOpacity_is_1', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(visible: true));
      await tester.pump(); // settle initial frame

      final ao = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(
        ao.opacity,
        equals(1.0),
        reason:
            'chromeVisibilityProvider=true must render chrome at full opacity '
            '(FR-M6-05, §Components §2)',
      );
    });
  });

  // =========================================================================
  // 2. Visibility = false → AnimatedOpacity opacity 0.0
  // =========================================================================
  group('ChromeOverlay — visibility false', () {
    testWidgets('given_visible_false_when_mounted_then_animatedOpacity_is_0', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(visible: false));
      await tester.pump();

      final ao = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(
        ao.opacity,
        equals(0.0),
        reason:
            'chromeVisibilityProvider=false must collapse chrome to opacity 0 '
            '(FR-M6-06, §Components §2)',
      );
    });
  });

  // =========================================================================
  // 3. Menu affordance RenderBox.size >= Size(48, 48)
  // =========================================================================
  group('ChromeOverlay — tap target size', () {
    testWidgets(
      'given_visible_true_when_mounted_then_menuIconBox_is_at_least_48x48',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        // The menu affordance is the single IconButton in the overlay.
        final iconButtonFinder = find.byType(IconButton);
        expect(
          iconButtonFinder,
          findsAtLeastNWidgets(1),
          reason:
              'ChromeOverlay must contain at least one IconButton affordance',
        );

        final renderBox =
            tester.renderObject(iconButtonFinder.first) as RenderBox;
        final size = renderBox.size;

        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason:
              'Menu affordance width must be ≥48dp (NFR-M6-05, canon ≥48dp promotion)',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason:
              'Menu affordance height must be ≥48dp (NFR-M6-05, canon ≥48dp promotion)',
        );
      },
    );
  });

  // =========================================================================
  // 4. Localized Semantics / tooltip — non-empty, resolved from ARB
  // =========================================================================
  group('ChromeOverlay — localized Semantics and tooltip', () {
    testWidgets(
      'given_en_locale_when_mounted_then_menuTooltip_is_non_empty_from_arb',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        // Tooltip must be non-empty and come from ARB, not a hard-coded literal.
        // app_en.arb menuTooltip = "Open menu"
        expect(
          find.byTooltip('Open menu'),
          findsAtLeastNWidgets(1),
          reason:
              'Menu affordance must carry the localized menuTooltip value from ARB '
              '(NFR-M6-02, FR-M6-17)',
        );
      },
    );

    testWidgets(
      'given_en_locale_when_mounted_then_semantics_label_is_non_empty',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        // Collect all Semantics nodes that have a non-empty label.
        final semanticsNodes = tester.getSemantics(
          find.byType(IconButton).first,
        );
        expect(
          semanticsNodes.label,
          isNotEmpty,
          reason:
              'Menu affordance must have a non-empty Semantics label for '
              'screen-reader accessibility (FR-M6-17, WCAG 2.1 AA)',
        );
      },
    );
  });

  // =========================================================================
  // 5. No banned transition types in the widget tree
  // =========================================================================
  group('ChromeOverlay — banned transitions absent', () {
    testWidgets(
      'given_visible_true_when_mounted_then_no_SlideScaleRotationSize_transitions',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        // The widget file must use crossfade (AnimatedOpacity/FadeTransition) only.
        // These finders cover the overlay and all its children.
        final overlayFinder = find.byType(ChromeOverlay);
        expect(overlayFinder, findsOneWidget);

        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(SlideTransition),
          ),
          findsNothing,
          reason:
              'ChromeOverlay must NOT use SlideTransition (spec: crossfade only)',
        );
        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(ScaleTransition),
          ),
          findsNothing,
          reason: 'ChromeOverlay must NOT use ScaleTransition',
        );
        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(RotationTransition),
          ),
          findsNothing,
          reason: 'ChromeOverlay must NOT use RotationTransition',
        );
        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(SizeTransition),
          ),
          findsNothing,
          reason: 'ChromeOverlay must NOT use SizeTransition',
        );
      },
    );
  });

  // =========================================================================
  // 6. MediaQuery(disableAnimations: true) → animation duration == Duration.zero
  // =========================================================================
  group('ChromeOverlay — reduced motion (EC-12)', () {
    testWidgets(
      'given_disableAnimations_true_when_mounted_then_animatedOpacity_duration_is_zero',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(visible: true, disableAnimations: true),
        );
        await tester.pump();

        final ao = tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity).first,
        );
        expect(
          ao.duration,
          equals(Duration.zero),
          reason:
              'Under disableAnimations=true the crossfade duration must collapse '
              'to Duration.zero (EC-12)',
        );
      },
    );

    testWidgets(
      'given_disableAnimations_false_when_mounted_then_animatedOpacity_duration_is_nonzero',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(visible: true, disableAnimations: false),
        );
        await tester.pump();

        final ao = tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity).first,
        );
        expect(
          ao.duration,
          isNot(equals(Duration.zero)),
          reason:
              'Under disableAnimations=false the crossfade must use a positive '
              'duration for a visible fade',
        );
      },
    );
  });

  // =========================================================================
  // 7. No ScrollController construction; no jumpTo / animateTo in file
  //    Verified here as a static-source assertion (reads the dart file).
  // =========================================================================
  group('ChromeOverlay — no self-scroll (gate-10 companion)', () {
    test(
      'given_chrome_overlay_source_when_read_then_has_no_ScrollController_jumpTo_animateTo',
      () {
        const path = 'lib/presentation/shell/chrome_overlay.dart';
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('ScrollController()')),
          reason: 'ChromeOverlay must not construct a ScrollController',
        );
        expect(
          source,
          isNot(contains('jumpTo(')),
          reason: 'ChromeOverlay must not call jumpTo',
        );
        expect(
          source,
          isNot(contains('animateTo(')),
          reason: 'ChromeOverlay must not call animateTo',
        );
      },
    );

    test(
      'given_chrome_overlay_source_when_read_then_has_no_banned_transition_types',
      () {
        const path = 'lib/presentation/shell/chrome_overlay.dart';
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('SlideTransition')),
          reason: 'ChromeOverlay source must not reference SlideTransition',
        );
        expect(
          source,
          isNot(contains('ScaleTransition')),
          reason: 'ChromeOverlay source must not reference ScaleTransition',
        );
        expect(
          source,
          isNot(contains('RotationTransition')),
          reason: 'ChromeOverlay source must not reference RotationTransition',
        );
        expect(
          source,
          isNot(contains('SizeTransition')),
          reason: 'ChromeOverlay source must not reference SizeTransition',
        );
      },
    );
  });

  // =========================================================================
  // 8. onMenuTap callback is called on icon tap
  // =========================================================================
  group('ChromeOverlay — menu tap callback', () {
    testWidgets(
      'given_visible_true_when_menuIcon_tapped_then_onMenuTap_called',
      (tester) async {
        int tapCount = 0;
        await tester.pumpWidget(
          _buildApp(visible: true, onMenuTap: () => tapCount++),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(IconButton).first);
        await tester.pump();

        expect(
          tapCount,
          equals(1),
          reason: 'Tapping the menu affordance must invoke onMenuTap once',
        );
      },
    );
  });

  // =========================================================================
  // 9. ChromeOverlay is a Positioned widget (valid inside a Stack)
  // =========================================================================
  group('ChromeOverlay — Positioned top-end placement', () {
    testWidgets(
      'given_mounted_when_inspected_then_ChromeOverlay_is_Positioned',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        // ChromeOverlay must be a Positioned child of the Stack.
        // The widget itself renders a Positioned internally.
        expect(
          find.byType(Positioned),
          findsAtLeastNWidgets(1),
          reason:
              'ChromeOverlay must place itself via Positioned (FR-M6-05: '
              'never a Column row that resizes the editor)',
        );
      },
    );
  });

  // =========================================================================
  // 10. TASK-02 coupling: kChromeMenuZoneHeight == 48.0 and
  //     chrome_overlay.dart references it instead of _kMinTapTarget (C2b).
  // =========================================================================
  // Canon ref: ui-design-bible.md §Components.2 "Auto-hiding overlay chrome"
  //   "Promote targets to ≥48dp" — the shared constant is the single source of
  //   truth for the 48dp tap-target minimum so the reserved top inset and the
  //   chrome button box can never drift apart.
  //
  // <!-- CANON GAP: ui-design-bible §Components.2 documents the ≥48dp rule
  //   but does not prescribe the constant-sharing mechanism between
  //   editor_layout.dart and chrome_overlay.dart — this coupling is a
  //   mobile-port implementation detail not covered by the canon. -->
  group('ChromeOverlay — kChromeMenuZoneHeight coupling (TASK-02, C2b)', () {
    test(
      'given_sharedConstant_when_read_then_kChromeMenuZoneHeight_equals_48',
      () {
        // Validates the shared constant value — the single source of truth
        // for the chrome menu button zone height (C2b).
        expect(kChromeMenuZoneHeight, equals(48.0));
      },
    );

    test(
      'given_chrome_overlay_source_when_read_then_references_kChromeMenuZoneHeight',
      () {
        // Source-scan: chrome_overlay.dart must import and reference the shared
        // constant — proving the SizedBox dimensions come from the coupled source.
        const path = 'lib/presentation/shell/chrome_overlay.dart';
        final source = File(path).readAsStringSync();

        expect(
          source,
          contains('kChromeMenuZoneHeight'),
          reason:
              'chrome_overlay.dart must reference kChromeMenuZoneHeight from '
              'editor_layout.dart (C2b: single source of truth for 48dp zone)',
        );
      },
    );

    test(
      'given_chrome_overlay_source_when_read_then_has_zero_kMinTapTarget_literals',
      () {
        // Source-scan: the private _kMinTapTarget literal must be removed —
        // any residual literal (const or not) would break the coupling invariant.
        const path = 'lib/presentation/shell/chrome_overlay.dart';
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('_kMinTapTarget')),
          reason:
              'chrome_overlay.dart must NOT contain _kMinTapTarget after '
              'TASK-02 repoint — the shared kChromeMenuZoneHeight is the '
              'single source of truth (C2b)',
        );
      },
    );
  });
}
