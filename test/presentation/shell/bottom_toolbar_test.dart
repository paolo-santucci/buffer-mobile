// Tests for BottomToolbar widget (TASK-08, Wave 2).
//
// Spec refs: FR-07, FR-15, FR-19, FR-25, FR-26, NFR-04
// Plan refs: TASK-08 (Wave 2), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// TDD harness: plain MaterialApp + ProviderScope (toolbar itself is Ref-free).
//
// Test plan:
//  1. three buttons (FR-07): three button descendants, each RenderBox >= 48×48dp.
//  2. always-enabled (FR-15): all onPressed non-null; tap Copy invokes onCopy.
//  3. semantics+tooltip (FR-25/26): Semantics(button:true) on each button;
//     byTooltip finds each EN label; tooltip strings non-empty.
//  4. glass container (FR-19): GlassSurface ancestor with borderRadius == pillRadius.
//  5. gate-7 — Ref-free: bottom_toolbar.dart contains zero WidgetRef /
//     ConsumerWidget / ref.watch / ref.read occurrences.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/shell/bottom_toolbar.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildApp({
  VoidCallback? onCopy,
  VoidCallback? onPaste,
  VoidCallback? onFind,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BottomToolbar(
          onCopy: onCopy ?? () {},
          onPaste: onPaste ?? () {},
          onFind: onFind ?? () {},
        ),
      ),
    ),
  );
}

/// Builds a MaterialApp whose body is a [BottomToolbar] nested inside a
/// [SizedBox] of the given [containerWidth]. The toolbar is left-aligned inside
/// an [Align] so it can shrink to its natural (hug) width rather than being
/// forced to fill the container.
Widget _buildConstrainedApp({required double containerWidth}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: containerWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: BottomToolbar(onCopy: () {}, onPaste: () {}, onFind: () {}),
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
  group('BottomToolbar', () {
    // -----------------------------------------------------------------------
    // 1. Three buttons present and each >= 48×48dp (FR-07, FR-25, NFR-04)
    // -----------------------------------------------------------------------
    testWidgets('contains exactly three button descendants', (tester) async {
      await tester.pumpWidget(_buildApp());

      // IconButton widgets are the concrete button descendants.
      final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
      expect(buttons.length, 3);
    });

    testWidgets('each button has a RenderBox with size >= 48×48dp', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      for (final element in tester.elementList(find.byType(IconButton))) {
        final box = element.renderObject as RenderBox;
        expect(
          box.size.width,
          greaterThanOrEqualTo(48.0),
          reason: 'IconButton width must be >= 48dp (NFR-04/FR-25)',
        );
        expect(
          box.size.height,
          greaterThanOrEqualTo(48.0),
          reason: 'IconButton height must be >= 48dp (NFR-04/FR-25)',
        );
      }
    });

    // -----------------------------------------------------------------------
    // 2. Always enabled (FR-15)
    // -----------------------------------------------------------------------
    testWidgets('all buttons have non-null onPressed (always enabled)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      for (final button in tester.widgetList<IconButton>(
        find.byType(IconButton),
      )) {
        expect(
          button.onPressed,
          isNotNull,
          reason: 'FR-15: buttons must always be enabled',
        );
      }
    });

    testWidgets('tapping Copy invokes onCopy callback', (tester) async {
      var copyCount = 0;
      await tester.pumpWidget(_buildApp(onCopy: () => copyCount++));

      await tester.tap(find.byKey(const ValueKey('toolbar_copy')));
      await tester.pump();

      expect(copyCount, 1);
    });

    testWidgets('tapping Paste invokes onPaste callback', (tester) async {
      var pasteCount = 0;
      await tester.pumpWidget(_buildApp(onPaste: () => pasteCount++));

      await tester.tap(find.byKey(const ValueKey('toolbar_paste')));
      await tester.pump();

      expect(pasteCount, 1);
    });

    testWidgets('tapping Find invokes onFind callback', (tester) async {
      var findCount = 0;
      await tester.pumpWidget(_buildApp(onFind: () => findCount++));

      await tester.tap(find.byKey(const ValueKey('toolbar_find')));
      await tester.pump();

      expect(findCount, 1);
    });

    // -----------------------------------------------------------------------
    // 3. Semantics + Tooltip (FR-25, FR-26)
    // -----------------------------------------------------------------------
    testWidgets('each button is wrapped in Semantics with button:true', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      final semanticsNodes = tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.button ?? false),
        ),
      );
      // At least one Semantics(button:true) per interactive button.
      expect(semanticsNodes.length, greaterThanOrEqualTo(3));
    });

    testWidgets('Copy tooltip is non-empty and locale-resolved', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      // find.byTooltip triggers a Tooltip widget lookup.
      expect(find.byTooltip('Copy'), findsAtLeast(1));
    });

    testWidgets('Paste tooltip is non-empty and locale-resolved', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      expect(find.byTooltip('Paste'), findsAtLeast(1));
    });

    testWidgets('Find tooltip is non-empty and locale-resolved', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      expect(find.byTooltip('Find'), findsAtLeast(1));
    });

    // -----------------------------------------------------------------------
    // 4. Glass container (FR-19)
    // -----------------------------------------------------------------------
    testWidgets(
      'contains a GlassSurface with borderRadius == tokens.pillRadius',
      (tester) async {
        await tester.pumpWidget(_buildApp());

        // GlassSurface must be present in the widget tree.
        expect(find.byType(GlassSurface), findsOneWidget);

        // Verify the borderRadius matches kDefaultGlassTokens.pillRadius.
        final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
        expect(
          surface.borderRadius,
          kDefaultGlassTokens.pillRadius,
          reason: 'FR-19: toolbar container must use pillRadius token',
        );
      },
    );

    // -----------------------------------------------------------------------
    // G6. Hug-width — toolbar must shrink-wrap its three buttons (not full-bleed)
    //
    // Regression sentinel: if the parent slot forces left:0/right:0 (full-bleed
    // Positioned), the toolbar inherits the full container width and these tests
    // turn red. The tests are independent of that parent-slot change; they verify
    // only that the Row itself does not stretch beyond its content.
    // -----------------------------------------------------------------------
    testWidgets(
      'G6: hug at tablet width (800dp) — toolbar width < container width',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildConstrainedApp(containerWidth: 800));
        await tester.pump();

        final toolbarFinder = find.byType(BottomToolbar);
        expect(toolbarFinder, findsOneWidget);

        final box = tester.renderObject<RenderBox>(toolbarFinder);
        final toolbarWidth = box.size.width;

        // Must hug the buttons — strictly narrower than the 800dp container.
        expect(
          toolbarWidth,
          lessThan(800.0),
          reason: 'G6: toolbar must hug its 3 buttons, not fill the container',
        );

        // Three IconButtons at minWidth: 48dp each = 144dp minimum.
        // Allow up to 144dp + 8dp tolerance for padding / glass surface insets.
        expect(
          toolbarWidth,
          greaterThan(0.0),
          reason: 'G6: toolbar must have positive width',
        );
        expect(
          toolbarWidth,
          lessThanOrEqualTo(144.0 + 8.0),
          reason:
              'G6: toolbar width must be ≈ 3×48dp buttons within 8dp tolerance',
        );
      },
    );

    testWidgets(
      'G6: hug at narrow width (320dp) — toolbar width < container width '
      'and no RenderBox overflow (EC-07)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildConstrainedApp(containerWidth: 320));
        await tester.pump();

        final toolbarFinder = find.byType(BottomToolbar);
        expect(toolbarFinder, findsOneWidget);

        final box = tester.renderObject<RenderBox>(toolbarFinder);
        final toolbarWidth = box.size.width;

        expect(
          toolbarWidth,
          lessThan(320.0),
          reason: 'G6: toolbar must hug buttons on narrow 320dp screen',
        );
        expect(
          toolbarWidth,
          greaterThan(0.0),
          reason: 'G6: toolbar must have positive width (EC-07)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 5. Gate-7 — Ref-free source scan
    // -----------------------------------------------------------------------
    test('gate-7: bottom_toolbar.dart contains no WidgetRef / ref usage', () {
      final file = File('lib/presentation/shell/bottom_toolbar.dart');

      // If the file does not exist yet (pre-implementation), the test is
      // trivially red. Post-implementation it must pass.
      if (!file.existsSync()) {
        fail('bottom_toolbar.dart not found — implementation pending');
      }

      final source = file.readAsStringSync();

      expect(
        source,
        isNot(contains('WidgetRef')),
        reason: 'gate-7: BottomToolbar must be Ref-free (no WidgetRef)',
      );
      expect(
        source,
        isNot(contains('ConsumerWidget')),
        reason: 'gate-7: BottomToolbar must be Ref-free (no ConsumerWidget)',
      );
      expect(
        source,
        isNot(contains('ConsumerStatefulWidget')),
        reason:
            'gate-7: BottomToolbar must be Ref-free (no ConsumerStatefulWidget)',
      );
      expect(
        source,
        isNot(contains('ref.watch')),
        reason: 'gate-7: BottomToolbar must be Ref-free (no ref.watch)',
      );
      expect(
        source,
        isNot(contains('ref.read')),
        reason: 'gate-7: BottomToolbar must be Ref-free (no ref.read)',
      );
    });
  });
}
