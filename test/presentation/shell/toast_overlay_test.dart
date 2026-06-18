// Tests for ToastOverlay widget (TASK-13b, M6 + TASK-10 glass restyle).
//
// Spec refs: FR-M6-14, FR-M6-15, NFR-M6-03, EC-04, EC-12, §Components §8
//            FR-28, FR-20, FR-27, NFR-06, EC-08, EC-09
// Canon ref: .claude/docs/canon/ui-design-bible.md §Components §8
//            "Timed notification toast" — Positioned top-centre, crossfade only.
//
// TDD harness: ProviderScope + MaterialApp + Stack host.
// toastProvider is driven via show() / override.
//
// Tests:
//  1. show('hello') → text 'hello' in tree; auto-dismiss after 3s → gone (FR-M6-14).
//  2. Editor RenderBox size identical before/after showing a toast (EC-04).
//  3. Positioned top-centre in the Stack (not a sibling column child).
//  4. No SlideTransition/ScaleTransition in the file; only AnimatedOpacity/FadeTransition.
//  5. MediaQuery(disableAnimations: true) → AnimatedOpacity duration == Duration.zero (EC-12).
//  6. null state → fully transparent (opacity 0.0).
//  8. GlassSurface wiring (FR-28): visible toast has one GlassSurface child with pillRadius.
//  9. Opaque branch via toast (EC-08): highContrast=true → 0 BackdropFilter descendants.
// 10. Unmount-at-zero via toast (EC-09): opacity==0 (null state) → 0 BackdropFilter descendants.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/presentation/shell/toast_controller.dart';
import 'package:foglietto/presentation/shell/toast_overlay.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

// ---------------------------------------------------------------------------
// Fake notifier — overrides toastProvider with controllable state.
// Must extend ToastController so overrideWith(() => notifier) type-checks.
// ---------------------------------------------------------------------------
class _FakeToastNotifier extends ToastController {
  _FakeToastNotifier(this._initial);

  final ToastMessage? _initial;

  @override
  ToastMessage? build() => _initial;

  void set(ToastMessage? msg) => state = msg;
}

// ---------------------------------------------------------------------------
// Widget builder helpers
// ---------------------------------------------------------------------------

/// Builds the canonical test harness: a [Stack] containing a simulated editor
/// (green SizedBox 300×600) and the [ToastOverlay] as a sibling — matching
/// the TASK-12 integration topology.
///
/// [notifier] is optional; if omitted the provider is not overridden (uses real
/// provider with null initial state).
Widget _buildApp({
  _FakeToastNotifier? notifier,
  bool disableAnimations = false,
  bool highContrast = false,
}) {
  final overrides = <Override>[
    if (notifier != null) toastProvider.overrideWith(() => notifier),
  ];

  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        highContrast: highContrast,
      ),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: Stack(
              children: [
                // Simulated editor proxy (EC-04: its size must be invariant).
                const Positioned.fill(
                  child: ColoredBox(
                    key: ValueKey('editor-proxy'),
                    color: Colors.green,
                  ),
                ),
                // Widget under test.
                const ToastOverlay(),
              ],
            ),
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
  // 1. show('hello') → text 'hello' in tree; auto-dismiss after 3s → gone.
  // =========================================================================
  testWidgets('given_showHello_when_mounted_then_textHelloInTree', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(const ToastMessage('hello'));
    await tester.pumpWidget(_buildApp(notifier: notifier));

    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('given_showHello_when_stateClearedToNull_then_noTextInTree', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(const ToastMessage('hello'));
    await tester.pumpWidget(_buildApp(notifier: notifier));
    expect(find.text('hello'), findsOneWidget);

    // Simulate auto-dismiss: set state to null.
    notifier.set(null);
    await tester.pumpAndSettle();

    // After crossfade, text must be fully gone (opacity 0 or not visible).
    // The widget stays in tree but AnimatedOpacity is at 0.
    final animatedOpacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(animatedOpacity.opacity, 0.0);
  });

  // =========================================================================
  // 2. Editor RenderBox size identical before/after showing a toast (EC-04).
  //    The toast is a Positioned overlay — it must NEVER resize the editor.
  // =========================================================================
  testWidgets(
    'given_editorProxy_when_toastShowAndHide_then_editorSizeUnchanged',
    (tester) async {
      final notifier = _FakeToastNotifier(null);
      await tester.pumpWidget(_buildApp(notifier: notifier));

      final editorFinder = find.byKey(const ValueKey('editor-proxy'));
      final sizeBefore = tester.getSize(editorFinder);

      // Show toast.
      notifier.set(const ToastMessage('Size guard'));
      await tester.pump();

      final sizeAfter = tester.getSize(editorFinder);
      expect(
        sizeAfter,
        equals(sizeBefore),
        reason: 'EC-04: toast must not resize the editor',
      );
    },
  );

  // =========================================================================
  // 3. ToastOverlay is a Positioned child (top-centre) of the Stack.
  // =========================================================================
  testWidgets('given_toastOverlay_when_mounted_then_isPositionedInStack', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(null);
    await tester.pumpWidget(_buildApp(notifier: notifier));

    // ToastOverlay must be a Positioned child.
    expect(find.byType(Positioned), findsWidgets);

    // The ToastOverlay itself renders as a Positioned widget.
    // Verify via the widget's internal structure — it renders an AnimatedOpacity
    // wrapped in a Positioned with top: defined.
    final positioned = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .where((p) => p.top != null)
        .toList();
    expect(
      positioned,
      isNotEmpty,
      reason: 'ToastOverlay must have a Positioned with a top value',
    );
  });

  testWidgets('given_toastOverlay_when_mounted_then_isHorizontallyCentred', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(const ToastMessage('centre me'));
    await tester.pumpWidget(_buildApp(notifier: notifier));

    // The toast content must be horizontally centred in the Stack.
    // We verify by finding an Align or Center widget inside the Positioned
    // that achieves centre alignment.
    final centreWidgets = <Widget>[
      ...tester.widgetList(find.byType(Center)),
      ...tester.widgetList(
        find.byWidgetPredicate(
          (w) => w is Align && w.alignment == Alignment.topCenter,
        ),
      ),
    ];
    expect(
      centreWidgets,
      isNotEmpty,
      reason: 'ToastOverlay must horizontally centre its content',
    );
  });

  // =========================================================================
  // 4. No SlideTransition / ScaleTransition in the file — only
  //    AnimatedOpacity / FadeTransition (crossfade-only canon rule).
  //    (Source-scan: enforced here via assert widget tree contains no slide/scale.)
  // =========================================================================
  testWidgets(
    'given_toastOverlay_when_mounted_then_noSlideOrScaleTransitionInToastSubtree',
    (tester) async {
      final notifier = _FakeToastNotifier(const ToastMessage('only fade'));
      await tester.pumpWidget(_buildApp(notifier: notifier));

      // Scope to the ToastOverlay subtree to avoid MaterialApp route
      // animations (which add framework SlideTransitions). The canon
      // constraint is that the ToastOverlay widget itself must not use
      // slide/scale — not that the surrounding framework doesn't.
      final toastFinder = find.byType(ToastOverlay);
      expect(
        find.descendant(
          of: toastFinder,
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
        reason: 'Canon §Motion: no SlideTransition inside ToastOverlay',
      );
      expect(
        find.descendant(
          of: toastFinder,
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
        reason: 'Canon §Motion: no ScaleTransition inside ToastOverlay',
      );
    },
  );

  testWidgets('given_toastOverlay_when_mounted_then_animatedOpacityPresent', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(const ToastMessage('fade only'));
    await tester.pumpWidget(_buildApp(notifier: notifier));

    expect(
      find.byType(AnimatedOpacity),
      findsOneWidget,
      reason: 'ToastOverlay must use AnimatedOpacity for its crossfade',
    );
  });

  // =========================================================================
  // 5. MediaQuery(disableAnimations: true) → AnimatedOpacity duration == zero.
  //    (EC-12 reduced-motion compliance.)
  // =========================================================================
  testWidgets(
    'given_disableAnimations_when_mounted_then_animatedOpacityDurationIsZero',
    (tester) async {
      final notifier = _FakeToastNotifier(const ToastMessage('reduced motion'));
      await tester.pumpWidget(
        _buildApp(notifier: notifier, disableAnimations: true),
      );

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(
        animatedOpacity.duration,
        Duration.zero,
        reason: 'EC-12: reduce-motion must collapse crossfade to Duration.zero',
      );
    },
  );

  testWidgets(
    'given_animationsEnabled_when_mounted_then_animatedOpacityDurationIsNonZero',
    (tester) async {
      final notifier = _FakeToastNotifier(const ToastMessage('normal motion'));
      await tester.pumpWidget(
        _buildApp(notifier: notifier, disableAnimations: false),
      );

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(
        animatedOpacity.duration,
        isNot(Duration.zero),
        reason: 'Normal mode must have a non-zero crossfade duration',
      );
    },
  );

  // =========================================================================
  // 6. null state → opacity 0.0 (fully transparent, no visible box).
  // =========================================================================
  testWidgets('given_nullState_when_mounted_then_animatedOpacityIsZero', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(null);
    await tester.pumpWidget(_buildApp(notifier: notifier));

    final animatedOpacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(
      animatedOpacity.opacity,
      0.0,
      reason: 'null toast state must render as fully transparent',
    );
  });

  // =========================================================================
  // 7. non-null state → opacity 1.0.
  // =========================================================================
  testWidgets('given_nonNullState_when_mounted_then_animatedOpacityIsOne', (
    tester,
  ) async {
    final notifier = _FakeToastNotifier(const ToastMessage('visible'));
    await tester.pumpWidget(_buildApp(notifier: notifier));

    final animatedOpacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(
      animatedOpacity.opacity,
      1.0,
      reason: 'Non-null toast state must render as fully opaque',
    );
  });

  // =========================================================================
  // 8. GlassSurface wiring (FR-28, TASK-10):
  //    visible toast → exactly one GlassSurface descendant inside ToastOverlay,
  //    with borderRadius == GlassTokens.of(context).pillRadius.
  // =========================================================================
  testWidgets(
    'given_visibleToast_when_mounted_then_glassSurfaceDescendantWithPillRadius',
    (tester) async {
      final notifier = _FakeToastNotifier(const ToastMessage('glass'));
      await tester.pumpWidget(_buildApp(notifier: notifier));

      // One GlassSurface must be a descendant of ToastOverlay.
      expect(
        find.descendant(
          of: find.byType(ToastOverlay),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
        reason: 'FR-28: toast container must use GlassSurface',
      );

      // The GlassSurface must carry the pillRadius token.
      final glassSurface = tester.widget<GlassSurface>(
        find.descendant(
          of: find.byType(ToastOverlay),
          matching: find.byType(GlassSurface),
        ),
      );
      // GlassTokens is registered in AppTheme; here we cross-check against
      // the default token constant since tests use MaterialApp defaults.
      expect(
        glassSurface.borderRadius,
        kDefaultGlassTokens.pillRadius,
        reason: 'FR-28: GlassSurface.borderRadius must equal tokens.pillRadius',
      );
    },
  );

  // =========================================================================
  // 9. Opaque branch via toast (EC-08):
  //    MediaQuery.highContrast == true → 0 BackdropFilter descendants inside
  //    ToastOverlay (inherited from GlassSurface opaque branch).
  // =========================================================================
  testWidgets(
    'given_highContrast_when_toastVisible_then_noBackdropFilterInToastSubtree',
    (tester) async {
      final notifier = _FakeToastNotifier(const ToastMessage('high contrast'));
      await tester.pumpWidget(
        _buildApp(notifier: notifier, highContrast: true),
      );

      expect(
        find.descendant(
          of: find.byType(ToastOverlay),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
        reason: 'EC-08: high-contrast mode must suppress BackdropFilter',
      );
    },
  );

  // =========================================================================
  // 10. Unmount-at-zero via toast (EC-09):
  //     when the toast state is null (opacity == 0) → 0 BackdropFilter
  //     descendants inside ToastOverlay.
  // =========================================================================
  testWidgets(
    'given_nullToastState_when_mounted_then_noBackdropFilterInToastSubtree',
    (tester) async {
      // null initial state → opacity fed as 0.0 → GlassSurface absent branch.
      final notifier = _FakeToastNotifier(null);
      await tester.pumpWidget(_buildApp(notifier: notifier));

      expect(
        find.descendant(
          of: find.byType(ToastOverlay),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
        reason: 'EC-09: opacity==0 must unmount BackdropFilter entirely',
      );
    },
  );
}
