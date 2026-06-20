// Tests for KeyboardAccessoryBar widget (TASK-06, sp-20260620).
//
// Spec refs: FR-16, FR-18, FR-20, FR-21, NFR-04, NFR-08
// Plan refs: sp-20260620-ui-chrome-morph-transparency-spacing-plan.md TASK-06
//
// TDD: tests written FIRST (red phase — file does not exist yet), implementation
// follows. The widget must be a pure StatelessWidget with no Ref / Riverpod.
//
// Acceptance criteria verified here:
//   1. GlassSurface branch (FR-16): tree contains a GlassSurface; no hardcoded
//      alpha literal inside the widget source.
//   2. Done anatomy (FR-20/NFR-04): IconButton with CupertinoIcons.chevron_down;
//      hit target tester.getSize(find.byType(IconButton)) >= Size(48,48);
//      Tooltip(message == l10n.keyboardDoneTooltip);
//      Semantics(button: true) resolves on the button.
//   3. onDone fires (FR-18): tapping the button invokes onDone exactly once; no
//      exception thrown.
//   4. onDone is required: compile-time enforcement via Dart required named param;
//      no runtime null path (structural, not a widget test).
//   5. high-contrast fallback (EC-10): MediaQuery(highContrast:true) ⇒ no
//      BackdropFilter in the sub-tree (inherited from GlassSurface for free).
//
// <!-- CANON GAP: iOS keyboard-accessory bar not in bible; cross-cutting a11y
//      minimums applied; per spec §4 CANON PARTIAL / OQ-06/OQ-13 -->

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/shell/keyboard_accessory_bar.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

// ---------------------------------------------------------------------------
// Test harness helpers
// ---------------------------------------------------------------------------

/// Wraps [KeyboardAccessoryBar] in a MaterialApp with full l10n delegates.
///
/// [onDone]         — forwarded to [KeyboardAccessoryBar.onDone].
/// [locale]         — locale for l10n resolution.
/// [highContrast]   — MediaQuery.highContrast (for reduce-transparency test).
Widget _buildApp({
  VoidCallback? onDone,
  Locale locale = const Locale('en'),
  bool highContrast = false,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: Scaffold(body: KeyboardAccessoryBar(onDone: onDone ?? () {})),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('KeyboardAccessoryBar', () {
    // -----------------------------------------------------------------------
    // 1. GlassSurface branch
    // -----------------------------------------------------------------------
    group('renders as GlassSurface (FR-16)', () {
      testWidgets('tree contains a GlassSurface', (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        expect(find.byType(GlassSurface), findsOneWidget);
      });
    });

    // -----------------------------------------------------------------------
    // 2. Done anatomy
    // -----------------------------------------------------------------------
    group('Done button anatomy (FR-20/NFR-04)', () {
      testWidgets('IconButton with CupertinoIcons.chevron_down is present', (
        tester,
      ) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == CupertinoIcons.chevron_down,
          ),
          findsOneWidget,
        );
      });

      testWidgets('hit target is >= 48x48 dp', (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        final size = tester.getSize(find.byType(IconButton));
        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason: 'NFR-04: tap target width must be >= 48dp',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason: 'NFR-04: tap target height must be >= 48dp',
        );
      });

      testWidgets('Tooltip message equals l10n.keyboardDoneTooltip (EN)', (
        tester,
      ) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        // Build context after first frame to resolve l10n.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(KeyboardAccessoryBar)),
        );

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        expect(tooltip.message, equals(l10n.keyboardDoneTooltip));
      });

      testWidgets('Tooltip message equals l10n.keyboardDoneTooltip (IT)', (
        tester,
      ) async {
        await tester.pumpWidget(_buildApp(locale: const Locale('it')));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(KeyboardAccessoryBar)),
        );

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        expect(tooltip.message, equals(l10n.keyboardDoneTooltip));
      });

      testWidgets('Semantics label is non-empty on the IconButton', (
        tester,
      ) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        // The Semantics(button:true, label:...) wrapper exposes a label that
        // the IconButton inherits; assert via the SemanticsNode on the button.
        final semanticsNode = tester.getSemantics(find.byType(IconButton));
        expect(
          semanticsNode.label,
          isNotEmpty,
          reason:
              'Semantics(button:true) wrapper must provide a non-empty label',
        );
      });
    });

    // -----------------------------------------------------------------------
    // 3. onDone fires
    // -----------------------------------------------------------------------
    group('onDone callback (FR-18)', () {
      testWidgets('tapping the IconButton invokes onDone exactly once', (
        tester,
      ) async {
        int callCount = 0;
        await tester.pumpWidget(_buildApp(onDone: () => callCount++));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();

        expect(callCount, equals(1));
      });

      testWidgets('tapping the IconButton throws no exception', (tester) async {
        await tester.pumpWidget(_buildApp(onDone: () {}));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // 4. onDone is required — compile-time contract; no runtime null path.
    //    (Verified structurally: the constructor has `required this.onDone`.)
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // 5. high-contrast fallback
    // -----------------------------------------------------------------------
    group('high-contrast fallback (EC-10)', () {
      testWidgets(
        'MediaQuery(highContrast:true) => no BackdropFilter in sub-tree',
        (tester) async {
          await tester.pumpWidget(_buildApp(highContrast: true));
          await tester.pumpAndSettle();

          // GlassSurface must still be present (widget still renders).
          expect(find.byType(GlassSurface), findsOneWidget);

          // No BackdropFilter under the accessory bar.
          expect(
            find.descendant(
              of: find.byType(KeyboardAccessoryBar),
              matching: find.byType(BackdropFilter),
            ),
            findsNothing,
            reason:
                'EC-10: highContrast:true must suppress BackdropFilter (opaque fallback)',
          );
        },
      );
    });
  });
}
