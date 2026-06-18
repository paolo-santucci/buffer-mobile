// Tests for openMenuSheet helper (TASK-07)
//
// Formerly tested the bottom-sheet path. Rewritten to test the popover path
// after the conversion of menu_sheet.dart to OverflowPopover (FR-04).
//
// Spec refs: FR-04, FR-05, FR-06, FR-19
// Plan refs: TASK-07 (Wave 2), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// TDD: tests written FIRST, implementation follows.
//
// OQ-12 caveat: harness uses MaterialApp (real Overlay/Navigator) so
// OverlayEntry insertions are detectable via find.byType(OverflowPopover).
//
// Acceptance criteria verified here:
//   1. openMenuSheet opens an OverflowPopover, NOT a BottomSheet.
//   2. The popover has exactly 5 entries: ThemeSelector, FontSizeStepper,
//      Preferences, About, Recovery — and NO Find/Replace tile.
//   3. Outside-tap dismisses the popover.
//   4. Preferences, About, Recovery navigation works.
//   5. Italian locale renders correct labels.
//   6. FontSizeStepper present; step behaviour in-popover works.
//   7. onFind compat: openMenuSheet compiles with and without onFind; the
//      Find tile is absent either way (FR-05 / backward-compat).
//
// <!-- CANON GAP: anchored popover bubble anatomy + outside-tap-dismiss rule
//      See overflow_popover.dart for the full canon gap note. -->

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';
import 'package:foglietto/presentation/shell/menu_sheet.dart';
import 'package:foglietto/presentation/shell/overflow_popover.dart';
import 'package:foglietto/presentation/shell/theme_selector.dart';
import 'package:foglietto/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// Fake SettingsNotifier
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
    if (!identical(next, current)) state = AsyncData(next);
  }
}

// ---------------------------------------------------------------------------
// Stub screens for named routes
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
// Host screen: renders an anchor button that calls openMenuSheet.
// ---------------------------------------------------------------------------

class _HostScreen extends StatefulWidget {
  const _HostScreen({this.onFind});

  final VoidCallback? onFind;

  @override
  State<_HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<_HostScreen> {
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0, right: 8.0),
          child: CompositedTransformTarget(
            link: _link,
            child: SizedBox(
              width: 80,
              height: 48,
              child: ElevatedButton(
                onPressed: () => openMenuSheet(
                  context,
                  anchorLink: _link,
                  onFind: widget.onFind,
                ),
                child: const Text('Open Menu'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Harness builder (OQ-12: MaterialApp for real Overlay/Navigator).
// ---------------------------------------------------------------------------

Widget _buildApp({
  Locale locale = const Locale('en'),
  AppSettings initial = const AppSettings(),
  VoidCallback? onFind,
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
        '/': (_) => _HostScreen(onFind: onFind),
        '/settings': (_) => const _StubSettings(),
        '/about': (_) => const _StubAbout(),
        '/recovery': (_) => const _StubRecovery(),
      },
    ),
  );
}

/// Opens the popover by tapping the host button.
Future<void> _openPopover(WidgetTester tester) async {
  await tester.tap(find.text('Open Menu'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Open — OverflowPopover, NOT BottomSheet (FR-04)
  // =========================================================================
  group('openMenuSheet — opens OverflowPopover, not BottomSheet (FR-04)', () {
    testWidgets(
      'given_openMenuSheet_called_then_OverflowPopover_in_tree_and_no_BottomSheet',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(OverflowPopover),
          findsOneWidget,
          reason:
              'openMenuSheet must open an OverflowPopover (FR-04, popover-not-sheet)',
        );
        expect(
          find.byType(BottomSheet),
          findsNothing,
          reason:
              'showModalBottomSheet must not be used — no BottomSheet in tree',
        );
      },
    );
  });

  // =========================================================================
  // 2. Contents — ThemeSelector + FontSizeStepper + 3 nav tiles; no Find
  //    (FR-05 exact entry set)
  // =========================================================================
  group('openMenuSheet — popover contents (FR-05)', () {
    testWidgets(
      'given_popover_open_when_inspected_then_ThemeSelector_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(ThemeSelector),
          findsOneWidget,
          reason: 'Popover must embed exactly one ThemeSelector (FR-05)',
        );
      },
    );

    testWidgets(
      'given_popover_open_when_inspected_then_FontSizeStepper_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(FontSizeStepper),
          findsOneWidget,
          reason: 'Popover must embed exactly one FontSizeStepper (FR-05)',
        );
      },
    );

    testWidgets(
      'given_popover_open_when_inspected_then_Preferences_tile_present_en',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.text('Preferences'),
          findsAtLeastNWidgets(1),
          reason:
              'menuPreferences ARB key must resolve to "Preferences" in en locale',
        );
      },
    );

    testWidgets(
      'given_popover_open_when_inspected_then_About_tile_present_en',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.text('About'),
          findsAtLeastNWidgets(1),
          reason: 'menuAbout ARB key must resolve to "About" in en locale',
        );
      },
    );

    testWidgets(
      'given_popover_open_when_inspected_then_Recovery_tile_present_en',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.text('Recovery'),
          findsAtLeastNWidgets(1),
          reason:
              'menuRecovery ARB key must resolve to "Recovery" in en locale',
        );
      },
    );

    testWidgets('given_popover_open_when_inspected_then_NO_Find_tile_present', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openPopover(tester);

      expect(
        find.text('Find / Replace'),
        findsNothing,
        reason:
            'Find/Replace tile must NOT be in the popover (FR-05 — Find moved '
            'to bottom toolbar)',
      );
    });
  });

  // =========================================================================
  // 3. D2 guard — NO Material Stepper anywhere in the popover
  //    (D2 pre-M7; the custom FontSizeStepper is present, Stepper is not)
  // =========================================================================
  group('openMenuSheet — D2 no Material Stepper (CRITICAL)', () {
    testWidgets('given_popover_open_when_inspected_then_no_Slider_present', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openPopover(tester);

      expect(
        find.byType(Slider),
        findsNothing,
        reason: 'D2: NO font-size Slider anywhere in the popover',
      );
    });

    testWidgets(
      'given_popover_open_when_inspected_then_no_Material_Stepper_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(Stepper),
          findsNothing,
          reason: 'D2: NO Material Stepper anywhere in the popover',
        );
      },
    );
  });

  // =========================================================================
  // 4. Navigation — tap each tile → correct route (FR-06 nav seam)
  // =========================================================================
  group('openMenuSheet — navigation (FR-06)', () {
    testWidgets(
      'given_popover_open_when_Preferences_tapped_then_navigates_to_settings',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

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
      'given_popover_open_when_About_tapped_then_navigates_to_about',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

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
      'given_popover_open_when_Recovery_tapped_then_navigates_to_recovery',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

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
  // 5. Outside-tap dismiss (FR-06/EC-15)
  // =========================================================================
  group('openMenuSheet — dismiss (FR-06/EC-15)', () {
    testWidgets(
      'given_popover_open_when_barrier_tapped_then_popover_dismissed',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(find.byType(ThemeSelector), findsOneWidget);

        // Tap bottom-left — outside the popover bubble (which is top-right).
        await tester.tapAt(const Offset(20, 1100));
        await tester.pumpAndSettle();

        expect(
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Tapping the barrier must dismiss the popover (FR-06/EC-15)',
        );
        expect(
          find.text('Open Menu'),
          findsOneWidget,
          reason: 'After dismiss, host screen must still be visible',
        );
      },
    );
  });

  // =========================================================================
  // 6. Italian locale — labels from app_it.arb; no English leak
  // =========================================================================
  group('openMenuSheet — Italian locale (FR-M6-17, NFR-M6-01)', () {
    testWidgets('given_it_locale_when_popover_opened_then_labels_are_italian', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(locale: const Locale('it')));
      await _openPopover(tester);

      expect(
        find.text('Preferenze'),
        findsAtLeastNWidgets(1),
        reason:
            'menuPreferences ARB key must resolve to "Preferenze" in it locale',
      );
      expect(
        find.text('Informazioni'),
        findsAtLeastNWidgets(1),
        reason: 'menuAbout ARB key must resolve to "Informazioni" in it locale',
      );
      expect(
        find.text('Recupero'),
        findsAtLeastNWidgets(1),
        reason: 'menuRecovery ARB key must resolve to "Recupero" in it locale',
      );
      expect(
        find.text('Preferences'),
        findsNothing,
        reason: 'English "Preferences" must not leak into it locale',
      );
      expect(
        find.text('About'),
        findsNothing,
        reason: 'English "About" must not leak into it locale',
      );
    });
  });

  // =========================================================================
  // 7. FontSizeStepper embed (FR-M7-06)
  // =========================================================================
  group('openMenuSheet — FontSizeStepper (FR-M7-06)', () {
    testWidgets(
      'given_default_settings_when_popover_opened_then_FontSizeStepper_present_with_14pt_label',
      (tester) async {
        // Default fontSizeIndex == 8 → slotList[8] == 14 → label "14pt"
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(FontSizeStepper),
          findsOneWidget,
          reason: 'Popover must embed exactly one FontSizeStepper (FR-M7-06)',
        );
        expect(
          find.text('14pt'),
          findsOneWidget,
          reason:
              'FontSizeStepper label must show "14pt" for default fontSizeIndex 8',
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
        await _openPopover(tester);

        expect(find.text('16pt'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(
          find.text('17pt'),
          findsOneWidget,
          reason: 'After tapping Icons.add at index 10, label must be "17pt"',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_20_when_inspected_then_add_disabled_and_remove_steps_to_34pt',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(initial: const AppSettings(fontSizeIndex: 20)),
        );
        await _openPopover(tester);

        final addButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add),
        );
        expect(
          addButton.onPressed,
          isNull,
          reason:
              'Icons.add onPressed must be null at fontSizeIndex 20 (top of scale)',
        );

        await tester.tap(find.byIcon(Icons.remove));
        await tester.pumpAndSettle();

        expect(
          find.text('34pt'),
          findsOneWidget,
          reason:
              'After tapping Icons.remove at index 20, label must be "34pt"',
        );
      },
    );
  });

  // =========================================================================
  // 8. onFind compat — openMenuSheet compiles and opens with/without onFind;
  //    the Find tile is absent either way (FR-05 backward-compat)
  // =========================================================================
  group('openMenuSheet — onFind compat (FR-05, backward-compat)', () {
    testWidgets(
      'given_onFind_nonnull_when_popover_opened_then_Find_tile_absent',
      (tester) async {
        // FR-05: Find tile is absent regardless of onFind injection.
        // The Find button moved to the bottom toolbar.
        int callCount = 0;
        await tester.pumpWidget(_buildApp(onFind: () => callCount++));
        await _openPopover(tester);

        expect(
          find.text('Find / Replace'),
          findsNothing,
          reason:
              'Find/Replace tile must NOT appear in the popover even when '
              'onFind != null (FR-05 — Find moved to bottom toolbar)',
        );
        expect(
          find.byIcon(Icons.search),
          findsNothing,
          reason: 'No Find/Replace tile means no Icons.search in the popover',
        );
      },
    );

    testWidgets(
      'given_additive_signature_when_openMenuSheet_called_without_onFind_then_compiles_and_opens',
      (tester) async {
        // Backward-compat: existing call sites compile without onFind.
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(OverflowPopover),
          findsOneWidget,
          reason: 'openMenuSheet without onFind must still open the popover',
        );
        expect(
          find.text('Find / Replace'),
          findsNothing,
          reason: 'No Find tile when onFind not provided',
        );
      },
    );
  });
}
