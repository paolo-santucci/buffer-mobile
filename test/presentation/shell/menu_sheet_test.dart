// Tests for MenuSheet widget and openMenuSheet helper (TASK-09)
// Extended in TASK-07 (M7): FontSizeStepper embed tests.
//
// Spec refs: FR-M6-08, FR-M6-23, OQ-M6-02, §Mobile-adaptation
//            FR-M7-06 (FontSizeStepper host in menu sheet)
// Canon ref: .claude/docs/canon/ui-design-bible.md §Mobile-adaptation
//            .claude/docs/canon/ui-design-bible.md §5 "Font-size selector"
//            .claude/docs/canon/ui-design-bible.md §7 "Menu sheet"
//
// TDD: tests written FIRST, implementation follows.
//
// Acceptance criteria verified here:
//   1. Sheet contains a ThemeSelector, Preferences tile (menuPreferences ARB),
//      About tile (menuAbout ARB), Recovery tile (menuRecovery ARB).
//   2. NO font-size stepper / slider / +/- control anywhere in the sheet (D2
//      pre-M7). POST-M7 the Material Stepper widget is still absent; the custom
//      FontSizeStepper is PRESENT (see group 8).
//   3. Tap Preferences → Navigator route /settings.
//   4. Tap About → Navigator route /about.
//   5. Tap Recovery → Navigator route /recovery.
//   6. Scrim tap dismisses; Navigator back at '/'.
//   7. Labels localized under it locale (no English leak).
//   8. FontSizeStepper present; steps and disables-at-ends work in-sheet
//      (FR-M7-06).
//
// <!-- CANON GAP: OQ-M6-12 — ui-design-bible.md has no bottom-sheet container
//      anatomy (padding, corner radius, handle bar, elevation). Layout below
//      uses Material defaults. Flag for upstream review if fidelity gaps are
//      reported. -->

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/shell/menu_sheet.dart';
import 'package:buffer/presentation/shell/theme_selector.dart';
import 'package:buffer/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// Fake SettingsNotifier — seeds configurable AppSettings, implements all
// mutating setters so widget taps produce observable state changes.
// ---------------------------------------------------------------------------

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier({this._initial = const AppSettings()});

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> setColorScheme(AppColorScheme scheme) async {
    final current = state.value ?? const AppSettings();
    if (current.colorScheme != scheme) {
      state = AsyncData(current.copyWith(colorScheme: scheme));
    }
  }

  @override
  Future<void> setFontSizeIndex(int index) async {
    final current = state.value ?? const AppSettings();
    final next = current.setFontSizeIndex(index);
    if (!identical(next, current)) {
      state = AsyncData(next);
    }
  }
}

// ---------------------------------------------------------------------------
// Stub screens for named routes tested in navigation assertions.
// ---------------------------------------------------------------------------

class _StubSettings extends StatelessWidget {
  const _StubSettings();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Settings Stub')));
}

class _StubAbout extends StatelessWidget {
  const _StubAbout();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('About Stub')));
}

class _StubRecovery extends StatelessWidget {
  const _StubRecovery();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Recovery Stub')));
}

// ---------------------------------------------------------------------------
// Host screen: renders a button that calls openMenuSheet (no onFind).
// ---------------------------------------------------------------------------

class _HostScreen extends StatelessWidget {
  const _HostScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => openMenuSheet(context),
          child: const Text('Open Menu'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Host screen with onFind injection (TASK-05).
// ---------------------------------------------------------------------------

class _HostScreenWithFind extends StatelessWidget {
  const _HostScreenWithFind({required this.onFind});

  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => openMenuSheet(context, onFind: onFind),
          child: const Text('Open Menu'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Harness builder.
// ---------------------------------------------------------------------------

Widget _buildApp({
  Locale locale = const Locale('en'),
  AppSettings initial = const AppSettings(),
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(initial: initial),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/': (_) => const _HostScreen(),
        '/settings': (_) => const _StubSettings(),
        '/about': (_) => const _StubAbout(),
        '/recovery': (_) => const _StubRecovery(),
      },
    ),
  );
}

/// Opens the menu sheet by tapping the host button.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Open Menu'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Harness builder with onFind injection (TASK-05).
// ---------------------------------------------------------------------------

Widget _buildAppWithFind({
  required VoidCallback onFind,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [settingsProvider.overrideWith(() => _FakeSettingsNotifier())],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/': (_) => _HostScreenWithFind(onFind: onFind),
        '/settings': (_) => const _StubSettings(),
        '/about': (_) => const _StubAbout(),
        '/recovery': (_) => const _StubRecovery(),
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Sheet contents — ThemeSelector + three nav tiles
  // =========================================================================
  group('MenuSheet — contents', () {
    testWidgets(
      'given_sheet_opened_when_inspected_then_ThemeSelector_is_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        expect(
          find.byType(ThemeSelector),
          findsOneWidget,
          reason: 'MenuSheet must embed exactly one ThemeSelector (FR-M6-08)',
        );
      },
    );

    testWidgets(
      'given_sheet_opened_when_inspected_then_Preferences_tile_present_en',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        // EN: menuPreferences = "Preferences"
        expect(
          find.text('Preferences'),
          findsAtLeastNWidgets(1),
          reason:
              'menuPreferences ARB key must resolve to "Preferences" in en locale',
        );
      },
    );

    testWidgets(
      'given_sheet_opened_when_inspected_then_About_tile_present_en',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        // EN: menuAbout = "About"
        expect(
          find.text('About'),
          findsAtLeastNWidgets(1),
          reason: 'menuAbout ARB key must resolve to "About" in en locale',
        );
      },
    );

    testWidgets(
      'given_sheet_opened_when_inspected_then_Recovery_tile_present_en',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        // EN: menuRecovery = "Recovery"
        expect(
          find.text('Recovery'),
          findsAtLeastNWidgets(1),
          reason:
              'menuRecovery ARB key must resolve to "Recovery" in en locale',
        );
      },
    );
  });

  // =========================================================================
  // 2. D2 guard — NO font-size control anywhere in the sheet
  // =========================================================================
  group('MenuSheet — D2 font-size-free (CRITICAL)', () {
    testWidgets('given_sheet_opened_when_inspected_then_no_Slider_present', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openSheet(tester);

      expect(
        find.byType(Slider),
        findsNothing,
        reason: 'D2: NO font-size Slider anywhere in MenuSheet',
      );
    });

    testWidgets('given_sheet_opened_when_inspected_then_no_Stepper_present', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openSheet(tester);

      expect(
        find.byType(Stepper),
        findsNothing,
        reason: 'D2: NO font-size Stepper anywhere in MenuSheet',
      );
    });
  });

  // =========================================================================
  // 3–5. Navigation — tap each tile → correct route
  // =========================================================================
  group('MenuSheet — navigation', () {
    testWidgets(
      'given_sheet_opened_when_Preferences_tapped_then_navigates_to_settings',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        await tester.tap(find.text('Preferences'));
        await tester.pumpAndSettle();

        expect(
          find.text('Settings Stub'),
          findsOneWidget,
          reason: 'Tapping Preferences must navigate to /settings',
        );
      },
    );

    testWidgets(
      'given_sheet_opened_when_About_tapped_then_navigates_to_about',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();

        expect(
          find.text('About Stub'),
          findsOneWidget,
          reason: 'Tapping About must navigate to /about',
        );
      },
    );

    testWidgets(
      'given_sheet_opened_when_Recovery_tapped_then_navigates_to_recovery',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        await tester.tap(find.text('Recovery'));
        await tester.pumpAndSettle();

        expect(
          find.text('Recovery Stub'),
          findsOneWidget,
          reason: 'Tapping Recovery must navigate to /recovery',
        );
      },
    );
  });

  // =========================================================================
  // 6. Scrim tap dismisses sheet; Navigator stays at '/'
  // =========================================================================
  group('MenuSheet — dismiss', () {
    testWidgets('given_sheet_opened_when_scrim_tapped_then_sheet_dismissed', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openSheet(tester);

      // Verify sheet is open (ThemeSelector visible)
      expect(find.byType(ThemeSelector), findsOneWidget);

      // Tap the scrim (top-left corner, outside the sheet)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Sheet dismissed: ThemeSelector no longer in tree
      expect(
        find.byType(ThemeSelector),
        findsNothing,
        reason: 'Tapping scrim must dismiss the sheet',
      );

      // Navigator is back at '/' host
      expect(
        find.text('Open Menu'),
        findsOneWidget,
        reason: 'After dismiss, Navigator must be back at the host route',
      );
    });
  });

  // =========================================================================
  // 7. Italian locale — labels from app_it.arb; no English leak
  // =========================================================================
  group('MenuSheet — Italian locale (FR-M6-17, NFR-M6-01)', () {
    testWidgets('given_it_locale_when_sheet_opened_then_labels_are_italian', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(locale: const Locale('it')));
      await _openSheet(tester);

      // IT: menuPreferences = "Preferenze"
      expect(
        find.text('Preferenze'),
        findsAtLeastNWidgets(1),
        reason:
            'menuPreferences ARB key must resolve to "Preferenze" in it locale',
      );

      // IT: menuAbout = "Informazioni"
      expect(
        find.text('Informazioni'),
        findsAtLeastNWidgets(1),
        reason: 'menuAbout ARB key must resolve to "Informazioni" in it locale',
      );

      // IT: menuRecovery = "Recupero"
      expect(
        find.text('Recupero'),
        findsAtLeastNWidgets(1),
        reason: 'menuRecovery ARB key must resolve to "Recupero" in it locale',
      );

      // No English leak — none of the EN-only labels should appear as tiles
      expect(
        find.text('Preferences'),
        findsNothing,
        reason: 'English "Preferences" must not leak into it locale rendering',
      );
      expect(
        find.text('About'),
        findsNothing,
        reason: 'English "About" must not leak into it locale rendering',
      );
    });
  });

  // =========================================================================
  // 8. FontSizeStepper embed (FR-M7-06)
  //
  //    The stepper is hosted between the ThemeSelector Padding and the first
  //    Divider, mirroring the ThemeSelector embed pattern (spec §4.1).
  //    Tests written FIRST (TDD, red phase) before the embed lands in
  //    menu_sheet.dart (TASK-07).
  // =========================================================================
  group('MenuSheet — FontSizeStepper (FR-M7-06)', () {
    testWidgets(
      'given_default_settings_when_sheet_opened_then_FontSizeStepper_present_with_14pt_label',
      (tester) async {
        // Default fontSizeIndex == 8 → slotList[8] == 14 → label "14pt"
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        expect(
          find.byType(FontSizeStepper),
          findsOneWidget,
          reason: 'MenuSheet must embed exactly one FontSizeStepper (FR-M7-06)',
        );
        expect(
          find.text('14pt'),
          findsOneWidget,
          reason:
              'FontSizeStepper label must show "14pt" for default fontSizeIndex 8 '
              '(slotList[8] == 14)',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_10_when_add_tapped_then_label_updates_to_17pt',
      (tester) async {
        // fontSizeIndex 10 → slotList[10] == 16 → "16pt"
        // After tapping Icons.add → index 11 → slotList[11] == 17 → "17pt"
        await tester.pumpWidget(
          _buildApp(initial: const AppSettings(fontSizeIndex: 10)),
        );
        await _openSheet(tester);

        expect(
          find.text('16pt'),
          findsOneWidget,
          reason: 'Initial label must be "16pt" for fontSizeIndex 10',
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(
          find.text('17pt'),
          findsOneWidget,
          reason:
              'After tapping Icons.add at index 10, label must update to "17pt" '
              '(index 11, slotList[11] == 17)',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_20_when_inspected_then_add_disabled_and_remove_steps_to_34pt',
      (tester) async {
        // fontSizeIndex 20 → slotList[20] == 38 → "38pt"; add must be disabled
        // After tapping Icons.remove → index 19 → slotList[19] == 34 → "34pt"
        await tester.pumpWidget(
          _buildApp(initial: const AppSettings(fontSizeIndex: 20)),
        );
        await _openSheet(tester);

        // Icons.add must be disabled at the top of the scale
        final addButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add),
        );
        expect(
          addButton.onPressed,
          isNull,
          reason:
              'Icons.add onPressed must be null at fontSizeIndex 20 (top of scale)',
        );

        // Tapping Icons.remove should step down to index 19 → "34pt"
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pumpAndSettle();

        expect(
          find.text('34pt'),
          findsOneWidget,
          reason:
              'After tapping Icons.remove at index 20, label must update to "34pt" '
              '(index 19, slotList[19] == 34)',
        );
      },
    );
  });

  // =========================================================================
  // 9. Find / Replace tile — TASK-05 (SP-20260615, FR-08, FR-17, NFR-02,
  //    NFR-04, contract C3)
  //
  //    The tile is rendered ONLY when onFind != null (callback-gated).
  //    MenuSheet stays a StatelessWidget with no ref; the tile only pops the
  //    sheet and invokes the injected callback.
  //
  //    Placement: after the Divider, before the Preferences tile (C3).
  //    Icon: Icons.search (edit-find-symbolic → Icons.search per bible §Iconography).
  //    Touch target: ListTile default >= 48dp (NFR-02).
  //
  // <!-- CANON GAP: ui-design-bible.md §Components.2 documents the chrome menu
  //      tile pattern but does not name a specific icon for the Find entry.
  //      Icons.search is the canonical Material mapping for edit-find-symbolic
  //      (GNOME icon → Material equivalent per spec §Iconography). Using
  //      Icons.search until the bible is updated with an explicit mapping. -->
  //
  //  Note: tests in this group that open the sheet with onFind != null set a
  //  taller test-surface height (1200 logical px) to avoid Column overflow in
  //  the 5-tile layout. The production widget is unchanged; this is a test
  //  harness concern only (overflow fires at <= ~338 px available height).
  // =========================================================================
  group('MenuSheet — Find tile (TASK-05, FR-08, FR-17, NFR-02, NFR-04)', () {
    testWidgets(
      'given_onFind_nonnull_when_sheet_opened_then_Find_tile_with_search_icon_present',
      (tester) async {
        // Taller viewport: sheet now has 5 tiles + ThemeSelector + stepper.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // FR-08, contract C3 — tile rendered when onFind != null
        await tester.pumpWidget(_buildAppWithFind(onFind: () {}));
        await _openSheet(tester);

        expect(
          find.text('Find / Replace'),
          findsOneWidget,
          reason:
              'menuFind ARB key must resolve to "Find / Replace" in en locale '
              'when onFind != null (FR-17)',
        );

        // The tile must have leading Icons.search
        expect(
          find.byIcon(Icons.search),
          findsOneWidget,
          reason:
              'Find tile must have leading Icons.search '
              '(edit-find-symbolic mapping, canon §Iconography)',
        );

        // The text must be inside a ListTile
        expect(
          find.ancestor(
            of: find.text('Find / Replace'),
            matching: find.byType(ListTile),
          ),
          findsOneWidget,
          reason: 'menuFind text must be inside a ListTile',
        );
      },
    );

    testWidgets('given_onFind_null_when_sheet_opened_then_Find_tile_absent', (
      tester,
    ) async {
      // Callback-gated: tile must NOT appear when openMenuSheet(context) is
      // called without onFind (additive/backward-compat, NFR-04).
      await tester.pumpWidget(_buildApp());
      await _openSheet(tester);

      expect(
        find.text('Find / Replace'),
        findsNothing,
        reason:
            'Find tile must be absent when onFind == null (NFR-04 backward-compat)',
      );
      expect(
        find.byIcon(Icons.search),
        findsNothing,
        reason:
            'Icons.search must be absent when onFind == null '
            '(tile is gated on the callback)',
      );
    });

    testWidgets(
      'given_onFind_nonnull_when_tile_tapped_then_callback_called_exactly_once_and_sheet_dismissed',
      (tester) async {
        // Taller viewport: sheet now has 5 tiles + ThemeSelector + stepper.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Tap fires injected callback and pops the sheet (FR-10 ordering:
        // sheet dismissed, then onFind invoked).
        int callCount = 0;
        await tester.pumpWidget(_buildAppWithFind(onFind: () => callCount++));
        await _openSheet(tester);

        // Sheet is open — ThemeSelector visible
        expect(find.byType(ThemeSelector), findsOneWidget);

        await tester.tap(find.text('Find / Replace'));
        await tester.pumpAndSettle();

        expect(
          callCount,
          equals(1),
          reason: 'onFind must be called exactly once after tapping the tile',
        );

        // Sheet must be dismissed (ThemeSelector gone)
        expect(
          find.byType(ThemeSelector),
          findsNothing,
          reason: 'Sheet must be dismissed after tapping Find tile',
        );
      },
    );

    testWidgets(
      'given_onFind_nonnull_when_sheet_opened_then_Find_tile_touch_target_meets_48dp_minimum',
      (tester) async {
        // Taller viewport: sheet now has 5 tiles + ThemeSelector + stepper.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // NFR-02: touch target height >= 48dp.
        await tester.pumpWidget(_buildAppWithFind(onFind: () {}));
        await _openSheet(tester);

        final tileFinder = find.ancestor(
          of: find.text('Find / Replace'),
          matching: find.byType(ListTile),
        );
        expect(tileFinder, findsOneWidget);

        final rect = tester.getRect(tileFinder);
        expect(
          rect.height,
          greaterThanOrEqualTo(48.0),
          reason: 'ListTile tap-target height must be >= 48dp (NFR-02)',
        );
        expect(
          rect.width,
          greaterThan(0),
          reason: 'ListTile must have positive width',
        );
      },
    );

    testWidgets(
      'given_additive_signature_when_openMenuSheet_called_without_onFind_then_compiles_and_opens',
      (tester) async {
        // NFR-04 backward-compat: existing call sites compile and still open
        // the sheet normally; no Find tile rendered.
        await tester.pumpWidget(_buildApp());
        await _openSheet(tester);

        // Sheet opened normally
        expect(
          find.byType(ThemeSelector),
          findsOneWidget,
          reason:
              'openMenuSheet(context) without onFind must still open normally '
              '(additive signature, NFR-04)',
        );
        expect(
          find.text('Find / Replace'),
          findsNothing,
          reason: 'No Find tile when onFind not provided',
        );
      },
    );

    testWidgets(
      'given_it_locale_and_onFind_nonnull_when_sheet_opened_then_Find_tile_label_is_italian',
      (tester) async {
        // Taller viewport: sheet now has 5 tiles + ThemeSelector + stepper.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // FR-17: IT locale tile title matches app_it.arb menuFind value
        // "Trova / Sostituisci".
        await tester.pumpWidget(
          _buildAppWithFind(onFind: () {}, locale: const Locale('it')),
        );
        await _openSheet(tester);

        expect(
          find.text('Trova / Sostituisci'),
          findsOneWidget,
          reason:
              'menuFind ARB key must resolve to "Trova / Sostituisci" in it locale '
              '(FR-17)',
        );
        expect(
          find.text('Find / Replace'),
          findsNothing,
          reason: 'English label must not appear in it locale',
        );
      },
    );
  });
}
