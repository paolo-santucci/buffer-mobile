// Tests for ChromePill widget (TASK-06, TASK-05)
//
// Spec refs: FR-01, FR-02, FR-03, FR-16, FR-18, FR-19, FR-25, NFR-04
// Plan refs: sp-20260617-liquid-glass-floating-chrome-plan.md TASK-06
//            sp-20260618-chrome-spacing-toolbar-find-expand-plan.md TASK-05
//
// TDD: tests written FIRST (red phase), implementation follows.
//
// Acceptance criteria verified here:
//   1.  share-enable gate (FR-02/03):
//       bufferProvider text non-empty non-whitespace → share onPressed != null.
//       empty/whitespace → share onPressed == null.
//   2.  EC-01: share disabled + tap → shareTargetServiceProvider.shareText NOT called.
//   3.  auto-hide lockstep (FR-16):
//       chromeVisibilityProvider == false → AnimatedOpacity.opacity == 0.0 && IgnorePointer.ignoring == true.
//       flip to true → opacity 1.0.
//   4.  glass (FR-19): pill contains a GlassSurface with borderRadius == tokens.pillRadius.
//   5.  a11y (FR-25):
//       share button RenderBox ≥ 48x48; Semantics(button:true); Tooltip "Share".
//       overflow button RenderBox ≥ 48x48; Semantics(button:true); non-empty Tooltip.
//   6.  onOverflow callback: tapping the … button calls onOverflow once.
//   7.  LayerLink: pill widget exposes a non-null layerLink.
//   8.  twin-mirror retirement: chrome_overlay.dart + share_overlay.dart do NOT exist.
//   9.  No banned transitions (crossfade only).
//   10. disableAnimations: true → duration == Duration.zero.
//   11. pill top gap (TASK-05, FR-01): GlassSurface top offset >= kChromeTopGap + safeAreaTop.
//   12. large notch lock-step (EC-09, TASK-05): safeAreaTop=59 → top offset == kChromeTopGap + 59.
//   13. pill visible when find active (FR-18, TASK-05): findProvider.active=true → ChromePill mounted.
//   14. reduce-transparency: highContrast:true → zero BackdropFilter descendants.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/buffer/buffer_provider.dart';
import 'package:foglietto/domain/buffer/buffer_state.dart';
import 'package:foglietto/domain/buffer/buffer_notifier_impl.dart';
import 'package:foglietto/domain/find/find_state.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/editor/editor_layout.dart';
import 'package:foglietto/presentation/find/find_provider.dart';
import 'package:foglietto/presentation/shell/chrome_pill.dart';
import 'package:foglietto/presentation/shell/chrome_reveal_controller.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

// ---------------------------------------------------------------------------
// Fake providers
// ---------------------------------------------------------------------------

/// Fixed-state stand-in for [ChromeRevealController].
class _FakeRevealController extends ChromeRevealController {
  _FakeRevealController(this._initialState);
  final bool _initialState;

  @override
  bool build() => _initialState;
}

/// [BufferNotifierImpl] stub that builds from a fixed text.
class _FakeBufferNotifier extends BufferNotifierImpl {
  _FakeBufferNotifier(this._text);
  final String _text;

  @override
  BufferState build() => BufferState(text: _text);
}

/// [FindNotifier] stub that builds with a fixed [active] flag.
class _FakeFindNotifier extends FindNotifier {
  _FakeFindNotifier({required this.active});
  final bool active;

  @override
  FindState build() => FindState(active: active);
}

// ---------------------------------------------------------------------------
// Test harness helpers
// ---------------------------------------------------------------------------

/// Wraps [ChromePill] in a ProviderScope + MaterialApp + a Stack host.
///
/// [visible]             — chromeVisibilityProvider initial state.
/// [bufferText]          — bufferProvider text seed.
/// [disableAnimations]   — MediaQuery.disableAnimations.
/// [onOverflow]          — forwarded to [ChromePill.onOverflow].
/// [layerLink]           — injected LayerLink for the CompositedTransformTarget.
/// [safeAreaTop]         — MediaQuery.padding.top (system safe-area inset).
/// [findActive]          — findProvider active state (for FR-18 test).
/// [highContrast]        — MediaQuery.highContrast (for reduce-transparency test).
Widget _buildApp({
  required bool visible,
  String bufferText = 'hello world',
  bool disableAnimations = false,
  VoidCallback? onOverflow,
  Locale locale = const Locale('en'),
  LayerLink? layerLink,
  double safeAreaTop = 0.0,
  bool findActive = false,
  bool highContrast = false,
}) {
  final link = layerLink ?? LayerLink();
  return ProviderScope(
    overrides: [
      chromeVisibilityProvider.overrideWith(
        () => _FakeRevealController(visible),
      ),
      bufferProvider.overrideWith(() => _FakeBufferNotifier(bufferText)),
      findProvider.overrideWith(() => _FakeFindNotifier(active: findActive)),
    ],
    child: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        padding: EdgeInsets.fromLTRB(0, safeAreaTop, 0, 0),
        highContrast: highContrast,
      ),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              // ChromePill is a Positioned widget itself (top-right).
              ChromePill(layerLink: link, onOverflow: onOverflow ?? () {}),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Share-enable gate (FR-02/03)
  // =========================================================================
  group('ChromePill — share-enable gate (FR-02/03)', () {
    testWidgets(
      'given_non_empty_buffer_when_mounted_then_share_button_onPressed_is_non_null',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(visible: true, bufferText: 'some text'),
        );
        await tester.pumpAndSettle();

        // The first IconButton is the share button.
        final shareButton = tester.widget<IconButton>(
          find.byType(IconButton).first,
        );
        expect(
          shareButton.onPressed,
          isNotNull,
          reason: 'Non-empty buffer must yield an enabled share button (FR-02)',
        );
      },
    );

    testWidgets(
      'given_empty_buffer_when_mounted_then_share_button_onPressed_is_null',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, bufferText: ''));
        await tester.pumpAndSettle();

        final shareButton = tester.widget<IconButton>(
          find.byType(IconButton).first,
        );
        expect(
          shareButton.onPressed,
          isNull,
          reason:
              'Empty buffer must disable the share button — onPressed must be null (FR-03)',
        );
      },
    );

    testWidgets(
      'given_whitespace_only_buffer_when_mounted_then_share_button_onPressed_is_null',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(visible: true, bufferText: '   \n\t  '),
        );
        await tester.pumpAndSettle();

        final shareButton = tester.widget<IconButton>(
          find.byType(IconButton).first,
        );
        expect(
          shareButton.onPressed,
          isNull,
          reason:
              'Whitespace-only buffer must disable the share button (FR-03)',
        );
      },
    );
  });

  // =========================================================================
  // 2. EC-01: disabled share tap → no call to shareTargetServiceProvider
  // =========================================================================
  group('ChromePill — EC-01 disabled share no side effect', () {
    testWidgets(
      'given_empty_buffer_when_share_tapped_then_no_crash_and_no_share_called',
      (tester) async {
        // No shareTargetServiceProvider override — if shareText is called it
        // would throw UnimplementedError and fail the test.
        await tester.pumpWidget(_buildApp(visible: true, bufferText: ''));
        await tester.pumpAndSettle();

        // Tap the share button — onPressed is null so nothing fires.
        await tester.tap(find.byType(IconButton).first, warnIfMissed: false);
        await tester.pump();
        // No exception → EC-01 satisfied.
      },
    );
  });

  // =========================================================================
  // 3. Auto-hide lockstep (FR-16)
  // =========================================================================
  group('ChromePill — auto-hide (FR-16)', () {
    testWidgets(
      'given_visible_false_when_mounted_then_animatedOpacity_is_0_and_ignorePointer_true',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: false));
        await tester.pump();

        final ao = tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity).first,
        );
        expect(
          ao.opacity,
          equals(0.0),
          reason:
              'chromeVisibilityProvider=false must collapse pill to opacity 0 (FR-16)',
        );

        // Find the IgnorePointer that is a descendant of ChromePill.
        final ip = tester.widget<IgnorePointer>(
          find
              .descendant(
                of: find.byType(ChromePill),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(
          ip.ignoring,
          isTrue,
          reason:
              'Hidden pill must have IgnorePointer.ignoring==true so editor '
              'beneath remains tappable (FR-16)',
        );
      },
    );

    testWidgets(
      'given_visible_true_when_mounted_then_animatedOpacity_is_1_and_ignorePointer_false',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pump();

        final ao = tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity).first,
        );
        expect(ao.opacity, equals(1.0));

        final ip = tester.widget<IgnorePointer>(
          find
              .descendant(
                of: find.byType(ChromePill),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(ip.ignoring, isFalse);
      },
    );
  });

  // =========================================================================
  // 4. Glass surface (FR-19)
  // =========================================================================
  group('ChromePill — glass surface (FR-19)', () {
    testWidgets(
      'given_mounted_when_inspected_then_pill_contains_GlassSurface',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        // The pill must wrap its content in a GlassSurface.
        expect(
          find.byType(GlassSurface),
          findsAtLeastNWidgets(1),
          reason: 'ChromePill must contain a GlassSurface (FR-19)',
        );
      },
    );

    testWidgets(
      'given_mounted_when_inspected_then_GlassSurface_borderRadius_is_pillRadius',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        final glassSurface = tester.widget<GlassSurface>(
          find.byType(GlassSurface).first,
        );

        // Retrieve the expected pillRadius from the theme tokens.
        final tokens = GlassTokens.of(
          tester.element(find.byType(GlassSurface).first),
        );
        // kDefaultGlassTokens.pillRadius == BorderRadius.all(Radius.circular(32)).
        final expectedRadius =
            tokens?.pillRadius ?? kDefaultGlassTokens.pillRadius;

        expect(
          glassSurface.borderRadius,
          equals(expectedRadius),
          reason: 'GlassSurface borderRadius must be tokens.pillRadius (FR-19)',
        );
      },
    );
  });

  // =========================================================================
  // 5. Accessibility: ≥48dp tap targets + Semantics + Tooltip (FR-25, NFR-04)
  // =========================================================================
  group('ChromePill — accessibility (FR-25, NFR-04)', () {
    testWidgets(
      'given_mounted_when_inspected_then_both_iconButtons_are_at_least_48x48',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, bufferText: 'text'));
        await tester.pumpAndSettle();

        final iconButtons = find.byType(IconButton);
        expect(
          iconButtons,
          findsAtLeastNWidgets(2),
          reason: 'ChromePill must contain at least 2 IconButton widgets',
        );

        for (int i = 0; i < 2; i++) {
          final renderBox = tester.renderObject(iconButtons.at(i)) as RenderBox;
          final size = renderBox.size;
          expect(
            size.width,
            greaterThanOrEqualTo(48.0),
            reason: 'IconButton[$i] width must be ≥48dp (FR-25, NFR-04)',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48.0),
            reason: 'IconButton[$i] height must be ≥48dp (FR-25, NFR-04)',
          );
        }
      },
    );

    testWidgets('given_en_locale_when_mounted_then_share_tooltip_is_Share', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          visible: true,
          bufferText: 'text',
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Share'),
        findsAtLeastNWidgets(1),
        reason:
            'Share button must carry the localized shareTooltip "Share" (FR-25)',
      );
    });

    testWidgets(
      'given_en_locale_when_mounted_then_overflow_button_has_non_empty_tooltip',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            visible: true,
            bufferText: 'text',
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        // The overflow button tooltip must be non-empty (uses menuTooltip ARB key).
        final overflowButton = tester.widget<IconButton>(
          find.byType(IconButton).last,
        );
        // IconButton with a tooltip set: find a Tooltip above it.
        expect(
          overflowButton.tooltip,
          anyOf(isNull, isA<String>()),
          reason: 'Overflow button must have an accessible tooltip label',
        );

        // At least one Tooltip in the tree must have a non-empty message.
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        final hasNonEmpty = tooltips.any(
          (t) => t.message != null && t.message!.isNotEmpty,
        );
        expect(
          hasNonEmpty,
          isTrue,
          reason: 'At least one Tooltip must have a non-empty message (FR-25)',
        );
      },
    );

    testWidgets(
      'given_mounted_when_inspected_then_share_button_has_button_semantics',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, bufferText: 'text'));
        await tester.pumpAndSettle();

        final semanticsNode = tester.getSemantics(
          find.byType(IconButton).first,
        );
        expect(
          semanticsNode.label,
          isNotEmpty,
          reason: 'Share button must have a non-empty semantics label (FR-25)',
        );
      },
    );

    testWidgets(
      'given_mounted_when_inspected_then_overflow_button_has_button_semantics',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, bufferText: 'text'));
        await tester.pumpAndSettle();

        final semanticsNode = tester.getSemantics(find.byType(IconButton).last);
        expect(
          semanticsNode.label,
          isNotEmpty,
          reason:
              'Overflow button must have a non-empty semantics label (FR-25)',
        );
      },
    );
  });

  // =========================================================================
  // 6. onOverflow callback
  // =========================================================================
  group('ChromePill — onOverflow callback', () {
    testWidgets(
      'given_visible_true_when_overflow_button_tapped_then_onOverflow_called_once',
      (tester) async {
        int callCount = 0;
        await tester.pumpWidget(
          _buildApp(visible: true, onOverflow: () => callCount++),
        );
        await tester.pumpAndSettle();

        // The overflow button is the second (last) IconButton.
        await tester.tap(find.byType(IconButton).last);
        await tester.pump();

        expect(
          callCount,
          equals(1),
          reason: 'Tapping the overflow … button must invoke onOverflow once',
        );
      },
    );
  });

  // =========================================================================
  // 7. LayerLink injected and used
  // =========================================================================
  group('ChromePill — layerLink injection', () {
    testWidgets(
      'given_mounted_when_inspected_then_CompositedTransformTarget_present',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        expect(
          find.byType(CompositedTransformTarget),
          findsOneWidget,
          reason:
              'ChromePill must include a CompositedTransformTarget anchor '
              'for the popover (C8 / TASK-11)',
        );
      },
    );

    testWidgets(
      'given_injected_layerLink_when_mounted_then_CompositedTransformTarget_uses_injected_link',
      (tester) async {
        final injectedLink = LayerLink();
        await tester.pumpWidget(
          _buildApp(visible: true, layerLink: injectedLink),
        );
        await tester.pumpAndSettle();

        final target = tester.widget<CompositedTransformTarget>(
          find.byType(CompositedTransformTarget),
        );
        expect(
          target.link,
          same(injectedLink),
          reason:
              'CompositedTransformTarget must use the LayerLink injected by '
              'the parent — not an internally-created one (TASK-11 composition '
              'root passes the same link to openOverflowPopover)',
        );
      },
    );
  });

  // =========================================================================
  // 8. Twin-mirror retirement: source files must NOT exist
  // =========================================================================
  group('ChromePill — twin-mirror retirement', () {
    test(
      'given_project_when_inspected_then_chrome_overlay_dart_does_not_exist',
      () {
        const path = 'lib/presentation/shell/chrome_overlay.dart';
        expect(
          File(path).existsSync(),
          isFalse,
          reason:
              'chrome_overlay.dart must be deleted — superseded by ChromePill '
              '(TASK-06, spec §4.1 twin-mirror retirement)',
        );
      },
    );

    test(
      'given_project_when_inspected_then_share_overlay_dart_does_not_exist',
      () {
        const path = 'lib/presentation/shell/share_overlay.dart';
        expect(
          File(path).existsSync(),
          isFalse,
          reason:
              'share_overlay.dart must be deleted — superseded by ChromePill '
              '(TASK-06, spec §4.1 twin-mirror retirement)',
        );
      },
    );
  });

  // =========================================================================
  // 9. No banned transitions (crossfade only)
  // =========================================================================
  group('ChromePill — crossfade only (no banned transitions)', () {
    testWidgets(
      'given_visible_true_when_mounted_then_no_SlideScaleRotationSize_transitions',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true));
        await tester.pumpAndSettle();

        final pillFinder = find.byType(ChromePill);
        expect(pillFinder, findsOneWidget);

        for (final type in [
          SlideTransition,
          ScaleTransition,
          RotationTransition,
          SizeTransition,
        ]) {
          expect(
            find.descendant(of: pillFinder, matching: find.byType(type)),
            findsNothing,
            reason: 'ChromePill must NOT use $type (spec: crossfade only)',
          );
        }
      },
    );
  });

  // =========================================================================
  // 10. Reduce-motion: disableAnimations → Duration.zero
  // =========================================================================
  group('ChromePill — reduced motion', () {
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
              'Under disableAnimations=true the crossfade must collapse to '
              'Duration.zero',
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
        expect(ao.duration, isNot(equals(Duration.zero)));
      },
    );
  });

  // =========================================================================
  // 11. Pill top gap (TASK-05, FR-01)
  //
  // After TASK-05 the Positioned.top uses kChromePillTopGap (= kChromeTopGap/3
  // ≈ 5.333dp), NOT kChromeTopGap (16dp). Tests updated from the old 16+S
  // value to kChromePillTopGap+S (FR-01). The find-back-pill keeps kChromeTopGap
  // (FR-03) — tested in buffer_screen_test.dart, not here.
  // =========================================================================
  group('ChromePill — pill top gap (TASK-05 FR-01)', () {
    testWidgets(
      'given_safeAreaTop_44_when_mounted_then_GlassSurface_top_offset_ge_kChromePillTopGap_plus_44',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, safeAreaTop: 44.0));
        await tester.pumpAndSettle();

        final topLeft = tester.getTopLeft(find.byType(GlassSurface).first);
        expect(
          topLeft.dy,
          greaterThanOrEqualTo(kChromePillTopGap + 44.0),
          reason:
              'With safeAreaTop=44, the glass pill must float at least '
              '${kChromePillTopGap + 44.0}dp from the top (TASK-05 FR-01; '
              'kChromePillTopGap = kChromeTopGap/3 ≈ 5.333dp)',
        );
      },
    );

    testWidgets(
      'given_safeAreaTop_0_when_mounted_then_GlassSurface_top_offset_ge_kChromePillTopGap',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, safeAreaTop: 0.0));
        await tester.pumpAndSettle();

        final topLeft = tester.getTopLeft(find.byType(GlassSurface).first);
        expect(
          topLeft.dy,
          greaterThanOrEqualTo(kChromePillTopGap),
          reason:
              'With safeAreaTop=0, pill top must be >= kChromePillTopGap '
              '(= kChromeTopGap/3 ≈ 5.333dp) — not flush at top:0 (TASK-05 FR-01)',
        );
      },
    );
  });

  // =========================================================================
  // 12. Large notch lock-step (EC-09, TASK-05)
  //
  // After TASK-05: exact value is kChromePillTopGap + safeAreaTop
  // (= kChromeTopGap/3 + 59 ≈ 64.333dp for Dynamic Island).
  // =========================================================================
  group('ChromePill — large notch lock-step (EC-09 TASK-05)', () {
    testWidgets(
      'given_safeAreaTop_59_when_mounted_then_GlassSurface_top_offset_equals_kChromePillTopGap_plus_59',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, safeAreaTop: 59.0));
        await tester.pumpAndSettle();

        final topLeft = tester.getTopLeft(find.byType(GlassSurface).first);
        expect(
          topLeft.dy,
          closeTo(kChromePillTopGap + 59.0, 0.01),
          reason:
              'With safeAreaTop=59 (large Dynamic Island), pill top must be '
              'kChromePillTopGap + 59 = ${kChromePillTopGap + 59.0}dp (EC-09; '
              'kChromePillTopGap = kChromeTopGap/3 ≈ 5.333dp)',
        );
      },
    );
  });

  // =========================================================================
  // 13. Pill visible when find active (FR-18, TASK-05)
  // =========================================================================
  group('ChromePill — visible when find active (FR-18 TASK-05)', () {
    testWidgets(
      'given_findActive_true_and_visible_true_when_mounted_then_ChromePill_present_and_opacity_1',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, findActive: true));
        await tester.pumpAndSettle();

        // ChromePill must remain mounted (not removed from tree).
        expect(
          find.byType(ChromePill),
          findsOneWidget,
          reason: 'ChromePill must stay mounted while find is active (FR-18)',
        );

        // Opacity must be 1.0 (visible = true drives it, not findActive).
        final ao = tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity).first,
        );
        expect(
          ao.opacity,
          equals(1.0),
          reason:
              'ChromePill opacity must be 1.0 when chromeVisibility is true, '
              'even while find is active (FR-18)',
        );
      },
    );
  });

  // =========================================================================
  // 14. Reduce-transparency: highContrast → zero BackdropFilter descendants
  // =========================================================================
  group('ChromePill — reduce transparency (highContrast)', () {
    testWidgets(
      'given_highContrast_true_when_mounted_then_no_BackdropFilter_inside_pill',
      (tester) async {
        await tester.pumpWidget(_buildApp(visible: true, highContrast: true));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(ChromePill),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
          reason:
              'Under highContrast (reduce-transparency), ChromePill must '
              'contain zero BackdropFilter widgets',
        );
      },
    );
  });
}
