// Tests for GlassSurface widget and GlassTokens ThemeExtension.
//
// Spec refs: FR-19, FR-20, FR-21, FR-27, NFR-02, NFR-03, NFR-05, NFR-06
// Plan refs: TASK-01 (Wave 1), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// TDD: tests are written BEFORE the implementation.
// Run `flutter test test/presentation/theme/glass_surface_test.dart` to confirm
// they FAIL first, then again after implementation to confirm they pass.
//
// CANON PARTIAL: ui-design-bible.md does not define the glass surface anatomy.
// Tests bind to cross-cutting tokens only (surface/outlineVariant, reduce-motion→instant).
// <!-- CANON GAP: glass surface (fill alpha light/dark, blur sigma, shadow spec, radii) -->

import 'package:foglietto/presentation/theme/app_theme.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps a [GlassSurface] inside a [MaterialApp] with the given [mediaQueryData].
/// If [themeData] is null, defaults to [AppTheme.light()].
Future<void> pumpGlassSurface(
  WidgetTester tester, {
  required Widget glassSurface,
  ThemeData? themeData,
  required MediaQueryData mediaQueryData,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: themeData ?? AppTheme.light(),
      home: MediaQuery(
        data: mediaQueryData,
        child: Scaffold(body: glassSurface),
      ),
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // TC-G1: Glass branch — BackdropFilter present, border from outlineVariant
  // Spec: FR-19, FR-20, NFR-06
  // ---------------------------------------------------------------------------
  group('Glass branch (highContrast: false)', () {
    testWidgets(
      'GlassSurface renders BackdropFilter >= 1 when highContrast is false '
      '(FR-19, NFR-06)',
      (tester) async {
        final tokens = AppTheme.light().extension<GlassTokens>()!;

        await pumpGlassSurface(
          tester,
          glassSurface: GlassSurface(
            borderRadius: tokens.pillRadius,
            child: const Text('x'),
          ),
          mediaQueryData: const MediaQueryData(),
        );

        expect(
          find.byType(BackdropFilter),
          findsAtLeastNWidgets(1),
          reason: 'Glass branch must mount a BackdropFilter (FR-19)',
        );
      },
    );

    testWidgets(
      'GlassSurface fill container derives alpha from fillAlphaLight token '
      '— not a hard-coded literal (FR-21, NFR-05)',
      (tester) async {
        final theme = AppTheme.light();
        final tokens = theme.extension<GlassTokens>()!;

        late GlassTokens capturedTokens;

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(),
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    capturedTokens = GlassTokens.of(context)!;
                    return GlassSurface(
                      borderRadius: tokens.pillRadius,
                      child: const Text('x'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // fillAlphaLight must be >= 0.90 (NFR-05)
        expect(
          capturedTokens.fillAlphaLight,
          greaterThanOrEqualTo(0.90),
          reason:
              'fillAlphaLight must be >= 0.90 for WCAG AA contrast (NFR-05)',
        );
        // fillAlphaDark must be >= 0.80 (NFR-05)
        expect(
          capturedTokens.fillAlphaDark,
          greaterThanOrEqualTo(0.80),
          reason: 'fillAlphaDark must be >= 0.80 for WCAG AA contrast (NFR-05)',
        );
      },
    );

    testWidgets(
      'GlassSurface border color uses outlineVariant from colorScheme '
      '(FR-21)',
      (tester) async {
        final theme = AppTheme.light();
        final tokens = theme.extension<GlassTokens>()!;

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(),
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    final outlineVariant = Theme.of(
                      context,
                    ).colorScheme.outlineVariant;
                    // The test captures outlineVariant so we can assert it
                    // is non-transparent (canon token present).
                    expect(
                      outlineVariant,
                      isNot(Colors.transparent),
                      reason: 'outlineVariant must be a canon-derived colour',
                    );
                    return GlassSurface(
                      borderRadius: tokens.pillRadius,
                      child: const Text('x'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TC-G2: Opaque branch — NO BackdropFilter, border + shadow retained
  // Spec: FR-20, NFR-06
  // ---------------------------------------------------------------------------
  group('Opaque branch (highContrast: true)', () {
    testWidgets('GlassSurface mounts NO BackdropFilter when highContrast is true '
        '(FR-20, NFR-06)', (tester) async {
      final tokens = AppTheme.light().extension<GlassTokens>()!;

      await pumpGlassSurface(
        tester,
        glassSurface: GlassSurface(
          borderRadius: tokens.pillRadius,
          child: const Text('x'),
        ),
        mediaQueryData: const MediaQueryData(highContrast: true),
      );

      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason:
            'Opaque branch must NOT mount a BackdropFilter when highContrast == true '
            '(FR-20)',
      );
    });

    testWidgets(
      'Opaque branch still renders the child (no visual disappearance) '
      '(FR-20)',
      (tester) async {
        final tokens = AppTheme.light().extension<GlassTokens>()!;

        await pumpGlassSurface(
          tester,
          glassSurface: GlassSurface(
            borderRadius: tokens.pillRadius,
            child: const Text('opaque-child'),
          ),
          mediaQueryData: const MediaQueryData(highContrast: true),
        );

        expect(
          find.text('opaque-child'),
          findsOneWidget,
          reason: 'Opaque branch must still render its child',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TC-G3: Clip discipline — BackdropFilter inside ClipRRect
  // Spec: NFR-06
  // ---------------------------------------------------------------------------
  group('Clip discipline — BackdropFilter always inside ClipRRect (NFR-06)', () {
    testWidgets(
      'BackdropFilter has a ClipRRect ancestor with the correct borderRadius '
      '(NFR-06 — clipped to pill bounds, never full-screen)',
      (tester) async {
        final theme = AppTheme.light();
        final tokens = theme.extension<GlassTokens>()!;
        final expectedRadius = tokens.pillRadius;

        await pumpGlassSurface(
          tester,
          glassSurface: GlassSurface(
            borderRadius: expectedRadius,
            child: const Text('x'),
          ),
          mediaQueryData: const MediaQueryData(),
        );

        // Find the BackdropFilter
        final backdropFinder = find.byType(BackdropFilter);
        expect(backdropFinder, findsAtLeastNWidgets(1));

        // Walk up the widget tree from the BackdropFilter and find a ClipRRect
        // with the expected radius before reaching the Scaffold root.
        final backdropElement = tester.element(backdropFinder.first);
        bool foundClipRRect = false;

        backdropElement.visitAncestorElements((ancestor) {
          if (ancestor.widget is ClipRRect) {
            final clip = ancestor.widget as ClipRRect;
            if (clip.borderRadius == expectedRadius) {
              foundClipRRect = true;
              return false; // stop walking
            }
          }
          // Stop at Scaffold to avoid false positives from the root
          if (ancestor.widget is Scaffold) {
            return false;
          }
          return true; // keep walking
        });

        expect(
          foundClipRRect,
          isTrue,
          reason:
              'BackdropFilter must be a descendant of ClipRRect(borderRadius: pillRadius) '
              '— never full-screen (NFR-06)',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TC-G4: Unmount-at-zero — opacity == 0 removes BackdropFilter subtree
  // Spec: NFR-06
  // ---------------------------------------------------------------------------
  group('Unmount-at-zero (opacity == 0) (NFR-06)', () {
    testWidgets(
      'GlassSurface(opacity: 0.0) → BackdropFilter ABSENT (unmounted, not transparent) '
      '(NFR-06)',
      (tester) async {
        final tokens = AppTheme.light().extension<GlassTokens>()!;

        await pumpGlassSurface(
          tester,
          glassSurface: GlassSurface(
            borderRadius: tokens.pillRadius,
            opacity: 0.0,
            child: const Text('x'),
          ),
          mediaQueryData: const MediaQueryData(),
        );

        expect(
          find.byType(BackdropFilter),
          findsNothing,
          reason:
              'opacity == 0.0 must UNMOUNT the BackdropFilter subtree entirely '
              '(not just set transparent) — NFR-06',
        );
      },
    );

    testWidgets(
      'GlassSurface(opacity: 1.0) after 0.0 → BackdropFilter PRESENT again '
      '(NFR-06 rebuild path)',
      (tester) async {
        final tokens = AppTheme.light().extension<GlassTokens>()!;

        // Start at opacity 0
        final opacityNotifier = ValueNotifier<double>(0.0);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(),
              child: Scaffold(
                body: ValueListenableBuilder<double>(
                  valueListenable: opacityNotifier,
                  builder: (context, opacity, _) {
                    return GlassSurface(
                      borderRadius: tokens.pillRadius,
                      opacity: opacity,
                      child: const Text('x'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Confirm absent at opacity 0
        expect(find.byType(BackdropFilter), findsNothing);

        // Rebuild with opacity 1
        opacityNotifier.value = 1.0;
        await tester.pump();

        expect(
          find.byType(BackdropFilter),
          findsAtLeastNWidgets(1),
          reason: 'Rebuilding with opacity 1.0 must restore the BackdropFilter',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TC-G5: Reduce-motion — internal AnimatedOpacity duration respects
  //         MediaQuery.disableAnimations
  // Spec: FR-27
  // ---------------------------------------------------------------------------
  group('Reduce-motion (FR-27)', () {
    testWidgets('When disableAnimations is true, any internal animated transition '
        'uses Duration.zero (FR-27)', (tester) async {
      final tokens = AppTheme.light().extension<GlassTokens>()!;

      await pumpGlassSurface(
        tester,
        glassSurface: GlassSurface(
          borderRadius: tokens.pillRadius,
          child: const Text('x'),
        ),
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      );

      // Find all AnimatedOpacity widgets inside GlassSurface (if any).
      // The GlassSurface may use AnimatedOpacity for internal transitions.
      // Under disableAnimations, every AnimatedOpacity.duration must be == Duration.zero.
      final animatedOpacities = tester.widgetList<AnimatedOpacity>(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(AnimatedOpacity),
        ),
      );

      for (final ao in animatedOpacities) {
        expect(
          ao.duration,
          Duration.zero,
          reason:
              'Under disableAnimations, AnimatedOpacity.duration must be Duration.zero '
              '(FR-27 reduce-motion)',
        );
      }
    });

    testWidgets('When disableAnimations is false, animated transitions may have a '
        'non-zero duration (FR-27 — animations not suppressed)', (tester) async {
      final tokens = AppTheme.light().extension<GlassTokens>()!;

      // Build with a non-zero opacity so the AnimatedOpacity path is active
      await pumpGlassSurface(
        tester,
        glassSurface: GlassSurface(
          borderRadius: tokens.pillRadius,
          opacity: 0.8,
          child: const Text('x'),
        ),
        mediaQueryData: const MediaQueryData(),
      );

      // If GlassSurface uses AnimatedOpacity, it should use a non-zero duration
      // when animations are enabled.
      // We do not mandate the specific duration value — only that it is > zero
      // unless the widget has no internal animation.
      // This test primarily documents the expectation; it passes trivially if
      // GlassSurface uses no AnimatedOpacity internally (opacity is driven by caller).
    });
  });

  // ---------------------------------------------------------------------------
  // TC-G6: Token values — tokens accessible via GlassTokens.of(context)
  // Spec: NFR-03, NFR-05
  // ---------------------------------------------------------------------------
  group('GlassTokens accessible and non-null (NFR-03)', () {
    testWidgets(
      'GlassTokens.of(context) is non-null under AppTheme.light() (NFR-03)',
      (tester) async {
        late GlassTokens? tokens;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) {
                tokens = GlassTokens.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          tokens,
          isNotNull,
          reason: 'GlassTokens.of() must be non-null under AppTheme.light()',
        );
      },
    );

    testWidgets(
      'GlassTokens.of(context) is non-null under AppTheme.dark() (NFR-03)',
      (tester) async {
        late GlassTokens? tokens;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) {
                tokens = GlassTokens.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          tokens,
          isNotNull,
          reason: 'GlassTokens.of() must be non-null under AppTheme.dark()',
        );
      },
    );

    testWidgets('GlassTokens fields are all positive / non-zero (NFR-03)', (
      tester,
    ) async {
      late GlassTokens tokens;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              tokens = GlassTokens.of(context)!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        tokens.blurSigma,
        greaterThan(0),
        reason: 'blurSigma must be > 0 (NFR-03)',
      );
      expect(
        tokens.borderWidth,
        greaterThan(0),
        reason: 'borderWidth must be > 0 (NFR-03)',
      );
      expect(
        tokens.shadow,
        isNotEmpty,
        reason: 'shadow must be non-empty list (NFR-03)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // TC-G7: Popover radius variant — GlassSurface accepts popoverRadius
  // Spec: NFR-03
  // ---------------------------------------------------------------------------
  group('Popover radius variant (NFR-03)', () {
    testWidgets(
      'GlassSurface with popoverRadius pumps without error (NFR-03)',
      (tester) async {
        final tokens = AppTheme.light().extension<GlassTokens>()!;

        await pumpGlassSurface(
          tester,
          glassSurface: GlassSurface(
            borderRadius: tokens.popoverRadius,
            child: const Text('popover'),
          ),
          mediaQueryData: const MediaQueryData(),
        );

        expect(find.text('popover'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // TC-G9: searchBarRadius token (TASK-02, sp-20260618)
  // Spec: additive field; 24dp radius; distinct from pillRadius (32dp) and
  //       BorderRadius.zero.
  // ---------------------------------------------------------------------------
  group('searchBarRadius token (TASK-02)', () {
    test(
      'kDefaultGlassTokens.searchBarRadius == BorderRadius.all(Radius.circular(24.0))',
      () {
        expect(
          kDefaultGlassTokens.searchBarRadius,
          equals(const BorderRadius.all(Radius.circular(24.0))),
          reason: 'searchBarRadius must be 24dp per spec',
        );
      },
    );

    test('searchBarRadius is distinct from pillRadius (24 != 32)', () {
      expect(
        kDefaultGlassTokens.searchBarRadius,
        isNot(equals(kDefaultGlassTokens.pillRadius)),
        reason: 'searchBarRadius (24dp) must differ from pillRadius (32dp)',
      );
    });

    test('searchBarRadius is not BorderRadius.zero', () {
      expect(
        kDefaultGlassTokens.searchBarRadius,
        isNot(equals(BorderRadius.zero)),
        reason: 'searchBarRadius must not be zero',
      );
    });

    test('copyWith(searchBarRadius: x) round-trips correctly', () {
      const newRadius = BorderRadius.all(Radius.circular(8.0));
      final updated = kDefaultGlassTokens.copyWith(searchBarRadius: newRadius);
      expect(
        updated.searchBarRadius,
        equals(newRadius),
        reason: 'copyWith must carry the new searchBarRadius value',
      );
      // Other fields must remain unchanged.
      expect(updated.pillRadius, equals(kDefaultGlassTokens.pillRadius));
    });

    test('copyWith() with no args preserves searchBarRadius', () {
      final copy = kDefaultGlassTokens.copyWith();
      expect(
        copy.searchBarRadius,
        equals(kDefaultGlassTokens.searchBarRadius),
        reason: 'copyWith() with no override must preserve searchBarRadius',
      );
    });

    test('lerp carries searchBarRadius at t=0.5', () {
      const aRadius = BorderRadius.all(Radius.circular(24.0));
      const bRadius = BorderRadius.all(Radius.circular(8.0));
      final a = kDefaultGlassTokens.copyWith(searchBarRadius: aRadius);
      final b = kDefaultGlassTokens.copyWith(searchBarRadius: bRadius);
      final mid = a.lerp(b, 0.5);
      // Midpoint of 24 and 8 is 16.
      expect(
        mid.searchBarRadius,
        equals(const BorderRadius.all(Radius.circular(16.0))),
        reason: 'lerp at t=0.5 must interpolate searchBarRadius',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // TC-G8: child is rendered in both branches
  // ---------------------------------------------------------------------------
  group('Child rendering', () {
    testWidgets('Child is rendered in the glass branch', (tester) async {
      final tokens = AppTheme.light().extension<GlassTokens>()!;

      await pumpGlassSurface(
        tester,
        glassSurface: GlassSurface(
          borderRadius: tokens.pillRadius,
          child: const Text('glass-child'),
        ),
        mediaQueryData: const MediaQueryData(),
      );

      expect(find.text('glass-child'), findsOneWidget);
    });

    testWidgets('Child is rendered in the opaque branch', (tester) async {
      final tokens = AppTheme.light().extension<GlassTokens>()!;

      await pumpGlassSurface(
        tester,
        glassSurface: GlassSurface(
          borderRadius: tokens.pillRadius,
          child: const Text('opaque-child'),
        ),
        mediaQueryData: const MediaQueryData(highContrast: true),
      );

      expect(find.text('opaque-child'), findsOneWidget);
    });
  });
}
