// Tests for ShareOverlay widget (TASK-07)
//
// Spec refs: FR-01, FR-02, FR-03, FR-05, FR-17, NFR-02, NFR-03,
//            EC-01, EC-11, EC-12, EC-14, §5.1.5
// Canon ref: .claude/docs/canon/ui-design-bible.md §Components §2
//            "Auto-hiding overlay chrome", §Accessibility, §Motion
//
// TDD: tests written FIRST (red phase), implementation follows.
//
// Acceptance criteria verified here:
//   1.  chromeVisibilityProvider=true  → AnimatedOpacity opacity 1.0  (FR-02)
//   2.  chromeVisibilityProvider=false → AnimatedOpacity opacity 0.0  (FR-02)
//   3.  Rendered IconButton RenderBox.size ≥ 48×48 dp in every state  (FR-03, NFR-02)
//   4.  EN locale → find.byTooltip('Share') ≥1 + non-empty Semantics  (FR-17, NFR-02)
//   5.  IT locale override → tooltip resolves to 'Condividi'           (FR-17, EC-14)
//   6.  No SlideTransition/Scale/Rotation/SizeTransition descendant    (NFR-03)
//   7.  disableAnimations:true  → AnimatedOpacity.duration == Duration.zero (EC-11, NFR-03)
//   7b. disableAnimations:false → duration > Duration.zero
//   8.  enabled:false → onPressed == null AND ≥48dp AND tap → 0 calls (FR-05, EC-01)
//   9.  enabled:true  → tap invokes onShareTap exactly once            (FR-04 surface, FR-05)
//   10. Source scan: `left: 0`, `bottomRight`, `kChromeMenuZoneHeight`,
//       no `right:` in Positioned, no ScrollController/jumpTo/animateTo,
//       no SlideTransition/ScaleTransition                              (FR-01, FR-03, NFR-03)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/editor_layout.dart'
    show kChromeMenuZoneHeight;
import 'package:buffer/presentation/shell/chrome_reveal_controller.dart';
import 'package:buffer/presentation/shell/share_overlay.dart';

// ---------------------------------------------------------------------------
// Test harness helpers
// ---------------------------------------------------------------------------

/// Wraps [ShareOverlay] in a valid ProviderScope + MaterialApp (with
/// AppLocalizations delegates) + a [Stack] host so [Positioned] is legal.
///
/// [visible] sets the [chromeVisibilityProvider] override.
/// [enabled] is forwarded to [ShareOverlay].
/// [disableAnimations] controls MediaQuery.disableAnimations.
/// [onShareTap] is the share callback under test.
/// [locale] defaults to EN.
Widget _buildApp({
  required bool visible,
  bool enabled = true,
  bool disableAnimations = false,
  VoidCallback? onShareTap,
  Locale locale = const Locale('en'),
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
        locale: locale,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              ShareOverlay(enabled: enabled, onShareTap: onShareTap ?? () {}),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Fixed-state stand-in for [ChromeRevealController] (mirrors chrome_overlay_test).
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
  group('ShareOverlay — visibility true', () {
    testWidgets('given_visible_true_when_mounted_then_animatedOpacity_is_1', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(visible: true));
      await tester.pump();

      final ao = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );
      expect(
        ao.opacity,
        equals(1.0),
        reason:
            'chromeVisibilityProvider=true must render overlay at full opacity '
            '(FR-02, §Components §2)',
      );
    });
  });

  // =========================================================================
  // 2. Visibility = false → AnimatedOpacity opacity 0.0
  // =========================================================================
  group('ShareOverlay — visibility false', () {
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
            'chromeVisibilityProvider=false must collapse overlay to opacity 0 '
            '(FR-02, §Components §2)',
      );
    });
  });

  // =========================================================================
  // 3. Share affordance RenderBox.size >= Size(48, 48) — in every state
  // =========================================================================
  group('ShareOverlay — tap target size', () {
    testWidgets(
      'given_visible_enabled_when_mounted_then_iconButton_is_at_least_48x48',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, enabled: true));
        await tester.pumpAndSettle();

        final iconButtonFinder = find.byType(IconButton);
        expect(iconButtonFinder, findsAtLeastNWidgets(1));

        final renderBox =
            tester.renderObject(iconButtonFinder.first) as RenderBox;
        final size = renderBox.size;

        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason: 'Share affordance width must be ≥48dp (FR-03, NFR-02)',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason: 'Share affordance height must be ≥48dp (FR-03, NFR-02)',
        );
      },
    );

    testWidgets(
      'given_disabled_when_mounted_then_iconButton_still_at_least_48x48',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, enabled: false));
        await tester.pumpAndSettle();

        final iconButtonFinder = find.byType(IconButton);
        expect(iconButtonFinder, findsAtLeastNWidgets(1));

        final renderBox =
            tester.renderObject(iconButtonFinder.first) as RenderBox;
        final size = renderBox.size;

        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason: 'Disabled share button must retain ≥48dp width (FR-05)',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason: 'Disabled share button must retain ≥48dp height (FR-05)',
        );
      },
    );

    testWidgets(
      'given_visible_false_when_mounted_then_iconButton_still_at_least_48x48',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: false, enabled: true));
        await tester.pumpAndSettle();

        final iconButtonFinder = find.byType(IconButton);
        expect(iconButtonFinder, findsAtLeastNWidgets(1));

        final renderBox =
            tester.renderObject(iconButtonFinder.first) as RenderBox;
        final size = renderBox.size;

        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));
      },
    );
  });

  // =========================================================================
  // 4. Localized Semantics / tooltip — EN locale
  // =========================================================================
  group('ShareOverlay — localized Semantics and tooltip (EN)', () {
    testWidgets('given_en_locale_when_mounted_then_shareTooltip_is_Share', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(visible: true, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Share'),
        findsAtLeastNWidgets(1),
        reason:
            'Share affordance must carry the localized shareTooltip "Share" '
            '(FR-17, NFR-02)',
      );
    });

    testWidgets(
      'given_en_locale_when_mounted_then_semantics_label_is_non_empty',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(visible: true, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        final semanticsNode = tester.getSemantics(
          find.byType(IconButton).first,
        );
        expect(
          semanticsNode.label,
          isNotEmpty,
          reason:
              'Share affordance must have a non-empty Semantics label for '
              'screen-reader accessibility (FR-17, WCAG 2.1 AA)',
        );
      },
    );
  });

  // =========================================================================
  // 5. IT locale override → tooltip resolves to 'Condividi'
  // =========================================================================
  group('ShareOverlay — IT locale override (EC-14)', () {
    testWidgets('given_it_locale_when_mounted_then_shareTooltip_is_Condividi', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(visible: true, locale: const Locale('it')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Condividi'),
        findsAtLeastNWidgets(1),
        reason:
            'IT locale must resolve shareTooltip to "Condividi" (EC-14, FR-17)',
      );
    });
  });

  // =========================================================================
  // 6. No banned transition types in the widget tree
  // =========================================================================
  group('ShareOverlay — banned transitions absent', () {
    testWidgets(
      'given_visible_true_when_mounted_then_no_SlideScaleRotationSize_transitions',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        final overlayFinder = find.byType(ShareOverlay);
        expect(overlayFinder, findsOneWidget);

        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(SlideTransition),
          ),
          findsNothing,
          reason: 'ShareOverlay must NOT use SlideTransition (crossfade only)',
        );
        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(ScaleTransition),
          ),
          findsNothing,
          reason: 'ShareOverlay must NOT use ScaleTransition',
        );
        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(RotationTransition),
          ),
          findsNothing,
          reason: 'ShareOverlay must NOT use RotationTransition',
        );
        expect(
          find.descendant(
            of: overlayFinder,
            matching: find.byType(SizeTransition),
          ),
          findsNothing,
          reason: 'ShareOverlay must NOT use SizeTransition',
        );
      },
    );
  });

  // =========================================================================
  // 7. MediaQuery(disableAnimations) → duration control (EC-11, NFR-03)
  // =========================================================================
  group('ShareOverlay — reduced motion (EC-11)', () {
    testWidgets(
      'given_disableAnimations_true_when_mounted_then_duration_is_zero',
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
              'Under disableAnimations=true the crossfade duration must be '
              'Duration.zero (EC-11, NFR-03)',
        );
      },
    );

    testWidgets(
      'given_disableAnimations_false_when_mounted_then_duration_is_nonzero',
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
              'Under disableAnimations=false the fade must use a positive duration',
        );
      },
    );
  });

  // =========================================================================
  // 8. enabled:false → onPressed == null AND ≥48dp AND tap → 0 calls
  // =========================================================================
  group('ShareOverlay — disabled state (FR-05, EC-01)', () {
    testWidgets(
      'given_disabled_when_inspected_then_iconButton_onPressed_is_null',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, enabled: false));
        await tester.pumpAndSettle();

        final iconButton = tester.widget<IconButton>(
          find.byType(IconButton).first,
        );
        expect(
          iconButton.onPressed,
          isNull,
          reason:
              'Disabled ShareOverlay must set onPressed = null (FR-05, EC-01)',
        );
      },
    );

    testWidgets('given_disabled_when_tapped_then_onShareTap_never_invoked', (
      tester,
    ) async {
      int callCount = 0;
      await tester.pumpWidget(
        _buildApp(visible: true, enabled: false, onShareTap: () => callCount++),
      );
      await tester.pumpAndSettle();

      // Attempt tap — onPressed is null so nothing fires.
      await tester.tap(find.byType(IconButton).first, warnIfMissed: false);
      await tester.pump();

      expect(
        callCount,
        equals(0),
        reason: 'Disabled state must never invoke onShareTap (EC-01)',
      );
    });
  });

  // =========================================================================
  // 9. enabled:true → tap invokes onShareTap exactly once
  // =========================================================================
  group('ShareOverlay — enabled tap callback (FR-04 surface, FR-05)', () {
    testWidgets(
      'given_visible_and_enabled_when_tapped_then_onShareTap_called_once',
      (tester) async {
        int tapCount = 0;
        await tester.pumpWidget(
          _buildApp(visible: true, enabled: true, onShareTap: () => tapCount++),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(IconButton).first);
        await tester.pump();

        expect(
          tapCount,
          equals(1),
          reason:
              'Tapping the enabled share affordance must invoke onShareTap once',
        );
      },
    );
  });

  // =========================================================================
  // 10. Source-scan assertions (FR-01, FR-03, NFR-03)
  // =========================================================================
  group('ShareOverlay — source-scan (anatomy, no self-scroll)', () {
    const sourcePath = 'lib/presentation/shell/share_overlay.dart';

    test('given_source_when_read_then_has_left_0_not_right', () {
      final source = File(sourcePath).readAsStringSync();

      expect(
        source,
        contains('left: 0'),
        reason: 'ShareOverlay Positioned must use left: 0 (FR-01, delta 1)',
      );
      // 'right: 0' must not appear in a Positioned call within this file.
      // Allow 'right' in comments or other contexts via regex:
      // we check the positioned call pattern specifically.
      expect(
        RegExp(r'Positioned\s*\(').allMatches(source).every((m) {
          final callText = source.substring(m.start, m.start + 200);
          return !callText.contains('right:');
        }),
        isTrue,
        reason: 'Positioned call must not use right: (FR-01, delta 1)',
      );
    });

    test('given_source_when_read_then_has_bottomRight_not_bottomLeft', () {
      final source = File(sourcePath).readAsStringSync();

      expect(
        source,
        contains('bottomRight'),
        reason:
            'ShareOverlay Container radius must use bottomRight (FR-01, delta 3)',
      );
      expect(
        source,
        isNot(contains('bottomLeft')),
        reason:
            'ShareOverlay must not use bottomLeft radius (that is ChromeOverlay)',
      );
    });

    test('given_source_when_read_then_references_kChromeMenuZoneHeight', () {
      final source = File(sourcePath).readAsStringSync();

      expect(
        source,
        contains('kChromeMenuZoneHeight'),
        reason:
            'ShareOverlay must reference kChromeMenuZoneHeight (FR-03, coupling invariant)',
      );
    });

    test(
      'given_source_when_read_then_has_no_ScrollController_jumpTo_animateTo',
      () {
        final source = File(sourcePath).readAsStringSync();

        expect(
          source,
          isNot(contains('ScrollController()')),
          reason: 'ShareOverlay must not construct a ScrollController',
        );
        expect(
          source,
          isNot(contains('jumpTo(')),
          reason: 'ShareOverlay must not call jumpTo',
        );
        expect(
          source,
          isNot(contains('animateTo(')),
          reason: 'ShareOverlay must not call animateTo',
        );
      },
    );

    test('given_source_when_read_then_has_no_banned_transition_types', () {
      final source = File(sourcePath).readAsStringSync();

      expect(
        source,
        isNot(contains('SlideTransition')),
        reason: 'ShareOverlay source must not reference SlideTransition',
      );
      expect(
        source,
        isNot(contains('ScaleTransition')),
        reason: 'ShareOverlay source must not reference ScaleTransition',
      );
      expect(
        source,
        isNot(contains('RotationTransition')),
        reason: 'ShareOverlay source must not reference RotationTransition',
      );
      expect(
        source,
        isNot(contains('SizeTransition')),
        reason: 'ShareOverlay source must not reference SizeTransition',
      );
    });

    test('given_source_when_read_then_references_chromeVisibilityProvider', () {
      final source = File(sourcePath).readAsStringSync();

      expect(
        source,
        contains('chromeVisibilityProvider'),
        reason:
            'ShareOverlay must watch chromeVisibilityProvider (FR-02: same visibility source)',
      );
    });
  });

  // =========================================================================
  // 11. kChromeMenuZoneHeight == 48.0 (shared constant value)
  // =========================================================================
  group('ShareOverlay — kChromeMenuZoneHeight coupling', () {
    test(
      'given_sharedConstant_when_read_then_kChromeMenuZoneHeight_equals_48',
      () {
        expect(kChromeMenuZoneHeight, equals(48.0));
      },
    );
  });
}
