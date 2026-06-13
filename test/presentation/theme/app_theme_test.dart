// Tests for AppTheme — light and dark ThemeData derived from canon tokens.
//
// Spec refs: FR-06, EC-14, NFR-05
// Canon: .claude/docs/canon/ui-design-bible.md §Colour & branding tokens, §Typography tokens
//
// Test-first (TDD): all tests below are written before the implementation exists.
// Run `flutter test test/presentation/theme/app_theme_test.dart` to confirm they fail,
// then again after implementation to confirm they pass.

import 'package:buffer/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  //   light: #f6d32d  → Color(0xFFF6D32D) (sanctioned branding literal)
  //   dark:  #873000  → Color(0xFF873000) (sanctioned branding literal)
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

    test(
      'light theme: colorScheme.primary corresponds to #f6d32d branding token',
      () {
        final theme = AppTheme.light();
        expect(
          theme.colorScheme.primary,
          const Color(0xFFF6D32D),
          reason:
              'light primary must be #f6d32d per --accent-bg-color / branding token',
        );
      },
    );

    test(
      'dark theme: colorScheme.primary corresponds to #873000 branding token',
      () {
        final theme = AppTheme.dark();
        expect(
          theme.colorScheme.primary,
          const Color(0xFF873000),
          reason:
              'dark primary must be #873000 per branding token (dark variant)',
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
}
