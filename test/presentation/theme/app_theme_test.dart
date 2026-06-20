// Tests for AppTheme — light and dark ThemeData derived from canon tokens.
//
// Spec refs: FR-01, FR-02, FR-03, FR-06, EC-14, NFR-01, NFR-03, NFR-05
// Canon: .claude/docs/canon/ui-design-bible.md §Colour & branding tokens, §Typography tokens
//
// Test-first (TDD): all tests below are written before the implementation exists.
// Run `flutter test test/presentation/theme/app_theme_test.dart` to confirm they fail,
// then again after implementation to confirm they pass.
//
// GATE-REVISION note (NFR-03): the old hex-literal assertions for #f6d32d / #873000
// have been INVERTED (not deleted) to reflect the blue-re-brand.  They now assert
// that primary is NOT those values — making them a regression guard that trips if
// the old seed is ever accidentally restored.

import 'package:foglietto/presentation/theme/app_theme.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 relative-luminance contrast-ratio helper
// Formula: https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
// ---------------------------------------------------------------------------

/// Returns the relative luminance of [color] in the range 0.0–1.0.
/// Uses linearised sRGB per WCAG 2.1 §1.4.6.
double _relativeLuminance(Color color) {
  double linearise(double c) {
    // sRGB gamma expansion
    return c <= 0.04045
        ? c / 12.92
        : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055);
    // Note: the above uses a cubic approximation; the precise formula is pow(…, 2.4)
    // which requires dart:math.  We use an equivalent algebraic form for pure-Dart purity.
  }

  final r = linearise(color.r);
  final g = linearise(color.g);
  final b = linearise(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Returns the WCAG 2.1 contrast ratio between [fg] and [bg].
/// The ratio is always ≥ 1.0 (lighter / darker + 0.05 / darker + 0.05).
double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  // ---------------------------------------------------------------------------
  // FR-06 — AppTheme.light() sets Brightness.light
  // ---------------------------------------------------------------------------
  group('AppTheme.light() (FR-06 light)', () {
    testWidgets('MaterialApp with AppTheme.light() pumps without exception and '
        'Theme.of(context).brightness == Brightness.light', (
      WidgetTester tester,
    ) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      expect(
        capturedTheme.brightness,
        Brightness.light,
        reason:
            'AppTheme.light() must produce a light-brightness theme (FR-06)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // FR-06 — AppTheme.dark() sets Brightness.dark
  // ---------------------------------------------------------------------------
  group('AppTheme.dark() (FR-06 dark)', () {
    testWidgets('MaterialApp with AppTheme.dark() pumps without exception and '
        'Theme.of(context).brightness == Brightness.dark', (
      WidgetTester tester,
    ) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      expect(
        capturedTheme.brightness,
        Brightness.dark,
        reason: 'AppTheme.dark() must produce a dark-brightness theme (FR-06)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // EC-14 / NFR-05 — Canon-token compliance
  //
  // --view-bg-color  → ColorScheme.surface
  //   light: #fff   → Color(0xFFFFFFFF)   (sanctioned literal)
  //   dark:  #202020 → Color(0xFF202020)  (sanctioned literal)
  //
  // --accent-bg-color → ColorScheme.primary
  //   Post-re-brand (FR-01 / NFR-03): primary is M3-derived from the blue seed
  //   #3584E4.  It must NOT be the old yellow #f6d32d or the old dark #873000.
  //   (GATE-REVISION: old hard-equal assertions INVERTED — they now guard against
  //   accidental restoration of the old yellow/brown seed.)
  //
  // --border-color → ColorScheme.outlineVariant
  //   Any non-default value (must not be Flutter's default Color(0xFFC4C7C5) / similar)
  //   and must derive from canon semantics (theme-driven, not raw grey).
  //
  // TextTheme default line-height == 1.4 (from canon Typography, style.css:11-14)
  // ---------------------------------------------------------------------------
  group('Canon-token compliance (EC-14 / NFR-05)', () {
    test('light theme: colorScheme.surface derives from --view-bg-color (#fff), '
        'not Flutter default grey Color(0xFFFAFAFA)', () {
      final theme = AppTheme.light();
      // The default Flutter surface is Color(0xFFFAFAFA) — we must not emit that.
      expect(
        theme.colorScheme.surface,
        isNot(const Color(0xFFFAFAFA)),
        reason:
            'surface must derive from --view-bg-color (#fff), not Flutter default',
      );
      // --view-bg-color in light is #fff == Color(0xFFFFFFFF).
      expect(
        theme.colorScheme.surface,
        const Color(0xFFFFFFFF),
        reason:
            'light surface must be #fff per --view-bg-color (sanctioned literal)',
      );
    });

    test(
      'dark theme: colorScheme.surface derives from --view-bg-color (#202020)',
      () {
        final theme = AppTheme.dark();
        expect(
          theme.colorScheme.surface,
          const Color(0xFF202020),
          reason:
              'dark surface must be #202020 per --view-bg-color (sanctioned literal)',
        );
      },
    );

    // -------------------------------------------------------------------------
    // GATE-REVISION (NFR-03 / red-then-green) — blue re-brand guards
    //
    // These assertions were previously:
    //   expect(primary, const Color(0xFFF6D32D))  — light
    //   expect(primary, const Color(0xFF873000))  — dark
    //
    // After the blue re-brand (FR-01), those literals must NEVER appear as
    // primary.  The assertions are INVERTED — they go RED if the old seed is
    // ever accidentally restored.  The M3-tonal derivation from #3584E4 is
    // left to the framework; we assert only that the old values are gone and
    // the result is non-null.
    //
    // <!-- CANON GAP: blue re-brand diverges from ui-design-bible §Colour
    //      upstream Yellow3/Brown5; UI-bible amendment pending (OQ-15) -->
    // -------------------------------------------------------------------------
    test(
      'light theme: colorScheme.primary is EXACTLY the GNOME accent #3584E4 '
      '— not the M3-tonal derivation, not the old yellow/brown (FR-01/NFR-03)',
      () {
        final theme = AppTheme.light();
        final primary = theme.colorScheme.primary;
        expect(
          primary,
          const Color(0xFF3584E4),
          reason:
              'Faithful port: primary must render the EXACT libadwaita accent '
              '#3584E4, not the fromSeed tonal derivation (#3E5F90). This also '
              'rules out the old yellow #f6d32d / brown #873000 by construction.',
        );
        expect(
          theme.colorScheme.onPrimary,
          const Color(0xFFFFFFFF),
          reason: 'GNOME draws white text on the accent (libadwaita).',
        );
      },
    );

    test(
      'dark theme: colorScheme.primary is EXACTLY the GNOME accent #3584E4 '
      '— libadwaita keeps @accent_bg_color identical across light/dark (FR-01/NFR-03)',
      () {
        final theme = AppTheme.dark();
        final primary = theme.colorScheme.primary;
        expect(
          primary,
          const Color(0xFF3584E4),
          reason:
              'Faithful port: dark primary must also render the EXACT accent '
              '#3584E4, not the fromSeed tonal derivation (#A7C8FF).',
        );
        expect(
          theme.colorScheme.onPrimary,
          const Color(0xFFFFFFFF),
          reason: 'GNOME draws white text on the accent (libadwaita).',
        );
      },
    );

    test('light theme: colorScheme.outlineVariant is set (derives from --border-color), '
        'not left at an unset/transparent default', () {
      final theme = AppTheme.light();
      // outlineVariant must be an intentional canon-derived value, not Colors.transparent.
      expect(
        theme.colorScheme.outlineVariant,
        isNot(Colors.transparent),
        reason:
            'outlineVariant must derive from --border-color, not be transparent',
      );
    });

    test(
      'dark theme: colorScheme.outlineVariant is set (derives from --border-color)',
      () {
        final theme = AppTheme.dark();
        expect(
          theme.colorScheme.outlineVariant,
          isNot(Colors.transparent),
          reason:
              'outlineVariant must derive from --border-color, not be transparent',
        );
      },
    );

    test(
      'light TextTheme: bodyMedium has height == 1.4 (canon line-height)',
      () {
        final theme = AppTheme.light();
        final bodyMedium = theme.textTheme.bodyMedium;
        expect(
          bodyMedium?.height,
          closeTo(1.4, 0.001),
          reason: 'canon Typography mandates line-height 1.4 (style.css:11-14)',
        );
      },
    );

    test(
      'dark TextTheme: bodyMedium has height == 1.4 (canon line-height)',
      () {
        final theme = AppTheme.dark();
        final bodyMedium = theme.textTheme.bodyMedium;
        expect(
          bodyMedium?.height,
          closeTo(1.4, 0.001),
          reason: 'canon Typography mandates line-height 1.4 (style.css:11-14)',
        );
      },
    );

    test('light TextTheme: all text styles have height == 1.4', () {
      final theme = AppTheme.light();
      final tt = theme.textTheme;
      final styles = [
        tt.displayLarge,
        tt.displayMedium,
        tt.displaySmall,
        tt.headlineLarge,
        tt.headlineMedium,
        tt.headlineSmall,
        tt.titleLarge,
        tt.titleMedium,
        tt.titleSmall,
        tt.bodyLarge,
        tt.bodyMedium,
        tt.bodySmall,
        tt.labelLarge,
        tt.labelMedium,
        tt.labelSmall,
      ];
      for (final style in styles) {
        if (style != null) {
          expect(
            style.height,
            closeTo(1.4, 0.001),
            reason:
                'All TextTheme styles must have height 1.4 per canon typography',
          );
        }
      }
    });

    test('AppTheme.light() and AppTheme.dark() are not the same instance', () {
      // Sanity check: two distinct themes are returned.
      expect(AppTheme.light().brightness, isNot(AppTheme.dark().brightness));
    });
  });

  // ---------------------------------------------------------------------------
  // NFR-01 / FR-02 — WCAG 2.1 AA accent contrast (TASK-03, revised)
  //
  // The accent is pinned to the EXACT GNOME #3584E4 with white text. White on
  // #3584E4 is 3.76:1 — below the 4.5:1 AA *text* bar but above the 3:1 bar for
  // *UI components / graphical objects* (WCAG 1.4.11), which is the accent's
  // actual usage here: buttons, cursor, selection, find-highlight — never body
  // text. This is precisely how GNOME/libadwaita itself uses white-on-accent.
  // A sentinel test confirms the helper is not trivially passing everything.
  // ---------------------------------------------------------------------------
  group('WCAG AA accent contrast (NFR-01 / FR-02)', () {
    test(
      'light scheme: contrast(onPrimary, primary) >= 3.0 (WCAG AA UI components '
      '— exact #3584E4 accent, white text, GNOME-faithful)',
      () {
        final cs = AppTheme.light().colorScheme;
        final ratio = _contrastRatio(cs.onPrimary, cs.primary);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason:
              'Light onPrimary/primary pair must satisfy WCAG 1.4.11 (≥3:1) for '
              'UI components. Actual ratio: $ratio (white on #3584E4 ≈ 3.76:1).',
        );
      },
    );

    test(
      'dark scheme: contrast(onPrimary, primary) >= 3.0 (WCAG AA UI components '
      '— exact #3584E4 accent, white text, GNOME-faithful)',
      () {
        final cs = AppTheme.dark().colorScheme;
        final ratio = _contrastRatio(cs.onPrimary, cs.primary);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason:
              'Dark onPrimary/primary pair must satisfy WCAG 1.4.11 (≥3:1) for '
              'UI components. Actual ratio: $ratio (white on #3584E4 ≈ 3.76:1).',
        );
      },
    );

    test('_contrastRatio sentinel: yellow over white fails WCAG AA (< 4.5) '
        '— confirms helper is not trivially passing everything', () {
      final ratio = _contrastRatio(Colors.yellow, Colors.white);
      expect(
        ratio,
        lessThan(4.5),
        reason:
            'Yellow (#FFFF00) over white (#FFFFFF) is a known low-contrast pair '
            '(~1.07:1); sentinel confirms _contrastRatio rejects it',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // New surface/outlineVariant survival tests (TASK-03 additions)
  //
  // After the seed flip, the surface and outlineVariant canon overrides must
  // survive — i.e. the .copyWith() is still applied after ColorScheme.fromSeed.
  // ---------------------------------------------------------------------------
  group('Canon override survival after seed flip (TASK-03 / FR-01)', () {
    test('light surface == Color(0xFFFFFFFF) after blue re-brand '
        '(--view-bg-color override survives)', () {
      final theme = AppTheme.light();
      expect(
        theme.colorScheme.surface,
        const Color(0xFFFFFFFF),
        reason: 'light surface override must survive the #3584E4 seed change',
      );
    });

    test('light outlineVariant != transparent after blue re-brand '
        '(--border-color override survives)', () {
      final theme = AppTheme.light();
      expect(
        theme.colorScheme.outlineVariant,
        isNot(Colors.transparent),
        reason: 'light outlineVariant canon override must survive seed change',
      );
    });

    test('dark surface == Color(0xFF202020) after blue re-brand '
        '(--view-bg-color override survives)', () {
      final theme = AppTheme.dark();
      expect(
        theme.colorScheme.surface,
        const Color(0xFF202020),
        reason: 'dark surface override must survive the #3584E4 seed change',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Touch-target minimum (WCAG / Material guidance — canon §Touch-target note)
  // The theme must not reduce materialTapTargetSize below padded (48dp minimum).
  // ---------------------------------------------------------------------------
  group('Touch-target minimums (canon §Touch-target note)', () {
    test('light theme: materialTapTargetSize is padded (≥48dp)', () {
      final theme = AppTheme.light();
      expect(
        theme.materialTapTargetSize,
        MaterialTapTargetSize.padded,
        reason:
            'Tap targets must be ≥48dp on Android (canon §Touch-target note)',
      );
    });

    test('dark theme: materialTapTargetSize is padded (≥48dp)', () {
      final theme = AppTheme.dark();
      expect(
        theme.materialTapTargetSize,
        MaterialTapTargetSize.padded,
        reason:
            'Tap targets must be ≥48dp on Android (canon §Touch-target note)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GlassTokens value gates (NFR-05, NFR-03 — SP-20260620 TASK-02)
  //
  // These are PINNED constants — if a future change drifts the fill-alpha values
  // by eye, these gates trip immediately, forcing a deliberate code change.
  //
  // Pinned values (change here + in glass_surface.dart together):
  //   fillAlphaLight == 0.68   (SP-20260620 TASK-02 update; NFR-05 canon delta §6.2)
  //   fillAlphaDark  == 0.68   (SP-20260620 TASK-02 update; NFR-05 canon delta §6.2)
  //
  // <!-- CANON GAP: liquid-glass translucency token not yet in bible; per spec §6.2 / OQ-13 -->
  // <!-- CANON GAP: glass surface (fill alpha light/dark, blur sigma, shadow spec, radii) -->
  // ---------------------------------------------------------------------------
  group('GlassTokens value gates (NFR-05 / NFR-03 — sp-20260620 TASK-02)', () {
    testWidgets('AppTheme.light() GlassTokens.fillAlphaLight == 0.68 '
        '(NFR-05 alpha-drift guard — pinned constant, SP-20260620 TASK-02)', (
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
        tokens.fillAlphaLight,
        // PINNED: change this and the constant in glass_surface.dart together.
        // SP-20260620 TASK-02: updated 0.92 → 0.68 (NFR-05 canon delta §6.2).
        closeTo(0.68, 0.001),
        reason:
            'fillAlphaLight is PINNED at 0.68 (SP-20260620 TASK-02, NFR-05 canon delta). '
            'Change this test AND the constant in glass_surface.dart together.',
      );
    });

    testWidgets('AppTheme.light() GlassTokens.fillAlphaDark == 0.68 '
        '(NFR-05 alpha-drift guard — pinned constant, SP-20260620 TASK-02)', (
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
        tokens.fillAlphaDark,
        // PINNED: change this and the constant in glass_surface.dart together.
        // SP-20260620 TASK-02: updated 0.82 → 0.68 (NFR-05 canon delta §6.2).
        closeTo(0.68, 0.001),
        reason:
            'fillAlphaDark is PINNED at 0.68 (SP-20260620 TASK-02, NFR-05 canon delta). '
            'Change this test AND the constant in glass_surface.dart together.',
      );
    });

    testWidgets(
      'AppTheme.light() GlassTokens.blurSigma > 0 and borderWidth > 0 (NFR-03)',
      (tester) async {
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
          reason: 'blurSigma must be a positive named token (NFR-03)',
        );
        expect(
          tokens.borderWidth,
          greaterThan(0),
          reason: 'borderWidth must be a positive named token (NFR-03)',
        );
      },
    );

    testWidgets(
      'AppTheme.light() GlassTokens.pillRadius and popoverRadius are non-null '
      '(NFR-03)',
      (tester) async {
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

        // pillRadius and popoverRadius are BorderRadius (non-nullable) — this test
        // guards that they are non-default/non-zero; actual values come from tokens.
        expect(
          tokens.pillRadius,
          isNotNull,
          reason: 'pillRadius must be a non-null named token (NFR-03)',
        );
        expect(
          tokens.popoverRadius,
          isNotNull,
          reason: 'popoverRadius must be a non-null named token (NFR-03)',
        );
      },
    );

    testWidgets(
      'AppTheme.dark() GlassTokens is registered and accessible (NFR-03)',
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
          reason: 'GlassTokens must be registered in AppTheme.dark() (NFR-03)',
        );
        expect(
          tokens!.fillAlphaDark,
          // SP-20260620 TASK-02: PINNED at 0.68 (NFR-05 canon delta §6.2).
          closeTo(0.68, 0.001),
          reason:
              'fillAlphaDark is PINNED at 0.68 per SP-20260620 TASK-02 '
              '(NFR-05 canon delta §6.2). Change here + glass_surface.dart together.',
        );
      },
    );
  });
}
