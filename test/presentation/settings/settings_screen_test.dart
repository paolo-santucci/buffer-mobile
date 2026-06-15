// SettingsScreen tests — TASK-10 (M6) + TASK-06 (M7)
//
// Spec refs (M6): FR-M6-09, FR-M6-13, NFR-M6-01, D8, §Components §7
// Spec refs (M7): FR-M7-06, FR-M7-08, FR-M7-12, NFR-M7-05, NFR-M7-07
//
// TDD requirement:
//   1. settingsTitle rendered; two groups settingsAppearance / settingsBehavior from ARB.
//   2. ThemeSelector present in Appearance; recovery-enabled + spell-check
//      SwitchListTiles in Behavior.
//   3. No ListTile/SwitchListTile title matching /line/i or 'linelength' (FR-M6-13).
//   4. No Slider/Stepper/font-size control / fontSizeToast reference present (OQ-M6-02).
//   5. Toggle recovery OFF → emergencyRecoveryEnabled==false (→ 0); ON → 10 (M5 semantics).
//   6. Under it locale all labels from app_it.arb; no English literal for localized keys.
//   7. (M7) FontSizeStepper is present in the Appearance section.
//   8. (M7) Monospace SwitchListTile present with l10n.settingsMonospaceFont title,
//      reflecting settings.useMonospaceFont (default true → switch on).
//   9. (M7) Toggling the monospace switch calls setUseMonospaceFont(false).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/domain/settings/settings_repository.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/settings/settings_screen.dart';
import 'package:buffer/presentation/shell/theme_selector.dart';
import 'package:buffer/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// Fake repository — records save() calls; seeds from an initial AppSettings.
// ---------------------------------------------------------------------------
class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _stored;
  final List<AppSettings> savedArgs = [];

  _FakeSettingsRepository({AppSettings initial = const AppSettings()})
    : _stored = initial;

  @override
  Future<AppSettings> load() async => _stored;

  @override
  Future<void> save(AppSettings settings) async {
    _stored = settings;
    savedArgs.add(settings);
  }
}

// ---------------------------------------------------------------------------
// Widget pump helper
// ---------------------------------------------------------------------------

Future<void> _pumpSettingsScreen(
  WidgetTester tester,
  _FakeSettingsRepository repo, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  // Let the async settings load settle.
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen — structure', () {
    late _FakeSettingsRepository repo;

    setUp(() {
      repo = _FakeSettingsRepository();
      SharedPreferences.setMockInitialValues({});
    });

    // -----------------------------------------------------------------------
    // TC-1 : AppBar title resolves from ARB key settingsTitle.
    // -----------------------------------------------------------------------
    testWidgets('TC-1: AppBar shows settingsTitle from ARB', (tester) async {
      await _pumpSettingsScreen(tester, repo);

      // settingsTitle EN: "Preferences"
      expect(find.text('Preferences'), findsWidgets);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final titleWidget = appBar.title as Text;
      expect(titleWidget.data, 'Preferences');
    });

    // -----------------------------------------------------------------------
    // TC-2 : Section headers settingsAppearance + settingsBehavior appear.
    // -----------------------------------------------------------------------
    testWidgets('TC-2: two group headers Appearance and Behavior present', (
      tester,
    ) async {
      await _pumpSettingsScreen(tester, repo);

      // settingsAppearance EN: "Appearance"
      expect(find.text('Appearance'), findsOneWidget);
      // settingsBehavior EN: "Behavior"
      expect(find.text('Behavior'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // TC-3 : ThemeSelector is present in the Appearance section.
    // -----------------------------------------------------------------------
    testWidgets('TC-3: ThemeSelector widget is present', (tester) async {
      await _pumpSettingsScreen(tester, repo);

      expect(find.byType(ThemeSelector), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // TC-4 : Recovery-enabled SwitchListTile present with settingsRecoveryEnabled label.
    // -----------------------------------------------------------------------
    testWidgets('TC-4: recovery-enabled SwitchListTile present', (
      tester,
    ) async {
      await _pumpSettingsScreen(tester, repo);

      // settingsRecoveryEnabled EN: "Save emergency recovery files"
      expect(
        find.descendant(
          of: find.byType(SwitchListTile),
          matching: find.text('Save emergency recovery files'),
        ),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // TC-5 : Spell-check SwitchListTile present with settingsSpellCheck label.
    // -----------------------------------------------------------------------
    testWidgets('TC-5: spell-check SwitchListTile present', (tester) async {
      await _pumpSettingsScreen(tester, repo);

      // settingsSpellCheck EN: "Check spelling"
      expect(
        find.descendant(
          of: find.byType(SwitchListTile),
          matching: find.text('Check spelling'),
        ),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // TC-6 : No line-LENGTH row (FR-M6-13 / D8).
    //        NARROWED (SP-20260615 TASK-06): the old gate forbade any switch
    //        whose title contained "line" — that was a proxy to catch the
    //        dropped line-length control. Adding "Show line numbers"
    //        (settingsLineNumbers) would have tripped the wide gate.
    //        The gate now forbids ONLY "line length" (case-insensitive),
    //        which is the vestigial proxy that must not reappear (D8).
    //        The "Show line numbers" row IS allowed.
    // -----------------------------------------------------------------------
    testWidgets('TC-6: no line-length row present (narrowed gate)', (
      tester,
    ) async {
      await _pumpSettingsScreen(tester, repo);

      // Assert no SwitchListTile title contains 'line length' (case-insensitive).
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      for (final sw in switches) {
        final titleWidget = sw.title;
        if (titleWidget is Text) {
          final text = (titleWidget.data ?? '').toLowerCase();
          expect(
            text.contains('line length'),
            isFalse,
            reason: 'Found a SwitchListTile with "line length" in title: $text',
          );
        }
      }
    });

    // -----------------------------------------------------------------------
    // TC-7 : No Slider or Stepper (font-size control excluded, OQ-M6-02).
    // -----------------------------------------------------------------------
    testWidgets('TC-7: no Slider or Stepper widget present', (tester) async {
      await _pumpSettingsScreen(tester, repo);

      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Stepper), findsNothing);
    });
  });

  group('SettingsScreen — recovery toggle semantics', () {
    late _FakeSettingsRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // -----------------------------------------------------------------------
    // TC-8 : Recovery ON → emergencyRecoveryEnabled true → files == 10.
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-8: recovery ON → emergencyRecoveryEnabled true, files==10',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(emergencyRecoveryEnabled: true),
        );
        await _pumpSettingsScreen(tester, repo);

        // The SwitchListTile with recovery label should show value=true.
        final sw = tester.widget<SwitchListTile>(
          find.ancestor(
            of: find.text('Save emergency recovery files'),
            matching: find.byType(SwitchListTile),
          ),
        );
        expect(sw.value, isTrue);

        // emergencyRecoveryFiles getter returns 10 when enabled.
        expect(repo.savedArgs, isEmpty); // no mutation yet
        final settings = (await repo.load());
        expect(settings.emergencyRecoveryEnabled, isTrue);
        expect(settings.emergencyRecoveryFiles, 10);
      },
    );

    // -----------------------------------------------------------------------
    // TC-9 : Toggle recovery OFF → setEmergencyRecoveryEnabled(false) →
    //         emergencyRecoveryEnabled==false → files==0.
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-9: toggle recovery OFF → emergencyRecoveryEnabled false, files==0',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(emergencyRecoveryEnabled: true),
        );
        await _pumpSettingsScreen(tester, repo);

        // Tap the recovery SwitchListTile to toggle it OFF.
        await tester.tap(
          find.ancestor(
            of: find.text('Save emergency recovery files'),
            matching: find.byType(SwitchListTile),
          ),
        );
        await tester.pumpAndSettle();

        // Verify the repository received a save call with disabled recovery.
        expect(repo.savedArgs, isNotEmpty);
        final saved = repo.savedArgs.last;
        expect(saved.emergencyRecoveryEnabled, isFalse);
        expect(saved.emergencyRecoveryFiles, 0);
      },
    );

    // -----------------------------------------------------------------------
    // TC-10: Toggle recovery ON (when OFF) → emergencyRecoveryEnabled true → files==10.
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-10: toggle recovery ON → emergencyRecoveryEnabled true, files==10',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(emergencyRecoveryEnabled: false),
        );
        await _pumpSettingsScreen(tester, repo);

        await tester.tap(
          find.ancestor(
            of: find.text('Save emergency recovery files'),
            matching: find.byType(SwitchListTile),
          ),
        );
        await tester.pumpAndSettle();

        expect(repo.savedArgs, isNotEmpty);
        final saved = repo.savedArgs.last;
        expect(saved.emergencyRecoveryEnabled, isTrue);
        expect(saved.emergencyRecoveryFiles, 10);
      },
    );
  });

  group('SettingsScreen — spell-check toggle', () {
    late _FakeSettingsRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // -----------------------------------------------------------------------
    // TC-11: Spell-check toggle ON (default true) shows correct state.
    // -----------------------------------------------------------------------
    testWidgets('TC-11: spell-check toggle reflects current spellingEnabled', (
      tester,
    ) async {
      repo = _FakeSettingsRepository(
        initial: const AppSettings(spellingEnabled: false),
      );
      await _pumpSettingsScreen(tester, repo);

      final sw = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Check spelling'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(sw.value, isFalse);
    });

    // -----------------------------------------------------------------------
    // TC-12: Toggle spell-check → saves updated spellingEnabled.
    // -----------------------------------------------------------------------
    testWidgets('TC-12: toggle spell-check calls setSpellingEnabled', (
      tester,
    ) async {
      repo = _FakeSettingsRepository(
        initial: const AppSettings(spellingEnabled: true),
      );
      await _pumpSettingsScreen(tester, repo);

      await tester.tap(
        find.ancestor(
          of: find.text('Check spelling'),
          matching: find.byType(SwitchListTile),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.savedArgs, isNotEmpty);
      expect(repo.savedArgs.last.spellingEnabled, isFalse);
    });
  });

  group('SettingsScreen — Italian locale', () {
    late _FakeSettingsRepository repo;

    setUp(() {
      repo = _FakeSettingsRepository();
      SharedPreferences.setMockInitialValues({});
    });

    // -----------------------------------------------------------------------
    // TC-13: Under it locale, labels resolve from app_it.arb; no EN literals
    //        for the localized keys.
    // -----------------------------------------------------------------------
    testWidgets('TC-13: under it locale labels are Italian', (tester) async {
      await _pumpSettingsScreen(tester, repo, locale: const Locale('it'));

      // settingsTitle IT: "Preferenze"
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      final titleWidget = appBar.title as Text;
      expect(titleWidget.data, 'Preferenze');

      // settingsAppearance IT: "Aspetto"
      expect(find.text('Aspetto'), findsOneWidget);
      // settingsBehavior IT: "Comportamento"
      expect(find.text('Comportamento'), findsOneWidget);

      // settingsRecoveryEnabled IT: "Salva i file di recupero di emergenza"
      expect(
        find.text('Salva i file di recupero di emergenza'),
        findsOneWidget,
      );

      // settingsSpellCheck IT: "Controllo ortografico"
      expect(find.text('Controllo ortografico'), findsOneWidget);

      // Ensure no English literals for the keys we localized.
      expect(find.text('Preferences'), findsNothing);
      expect(find.text('Appearance'), findsNothing);
      expect(find.text('Behavior'), findsNothing);
      expect(find.text('Save emergency recovery files'), findsNothing);
      expect(find.text('Check spelling'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // M7 tests — FontSizeStepper + monospace toggle (TASK-06)
  // Spec refs: FR-M7-06, FR-M7-08, FR-M7-12, NFR-M7-05, NFR-M7-07
  // -------------------------------------------------------------------------

  group('SettingsScreen — M7 typography rows (TASK-06)', () {
    late _FakeSettingsRepository repo;

    setUp(() {
      repo = _FakeSettingsRepository();
      SharedPreferences.setMockInitialValues({});
    });

    // -----------------------------------------------------------------------
    // TC-14: FontSizeStepper widget is present in the Appearance group.
    //        FR-M7-06 / NFR-M7-05
    // -----------------------------------------------------------------------
    testWidgets('TC-14: FontSizeStepper is present in the tree', (
      tester,
    ) async {
      await _pumpSettingsScreen(tester, repo);

      expect(find.byType(FontSizeStepper), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // TC-15: Monospace SwitchListTile present with settingsMonospaceFont label.
    //        Default useMonospaceFont == true → switch value is true.
    //        FR-M7-08 / NFR-M7-07
    // -----------------------------------------------------------------------
    testWidgets('TC-15: monospace SwitchListTile present, default value true', (
      tester,
    ) async {
      // Default AppSettings: useMonospaceFont == true.
      await _pumpSettingsScreen(tester, repo);

      // settingsMonospaceFont EN: "Monospace font"
      final sw = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Monospace font'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(sw.value, isTrue);
    });

    // -----------------------------------------------------------------------
    // TC-16: Monospace SwitchListTile reflects useMonospaceFont == false
    //        when settings is seeded with false.
    //        FR-M7-08
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-16: monospace SwitchListTile reflects useMonospaceFont false',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(useMonospaceFont: false),
        );
        await _pumpSettingsScreen(tester, repo);

        final sw = tester.widget<SwitchListTile>(
          find.ancestor(
            of: find.text('Monospace font'),
            matching: find.byType(SwitchListTile),
          ),
        );
        expect(sw.value, isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // TC-17: Toggling monospace switch off calls setUseMonospaceFont(false).
    //        FR-M7-08
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-17: toggle monospace off calls setUseMonospaceFont(false)',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(useMonospaceFont: true),
        );
        await _pumpSettingsScreen(tester, repo);

        await tester.tap(
          find.ancestor(
            of: find.text('Monospace font'),
            matching: find.byType(SwitchListTile),
          ),
        );
        await tester.pumpAndSettle();

        expect(repo.savedArgs, isNotEmpty);
        expect(repo.savedArgs.last.useMonospaceFont, isFalse);
      },
    );
  });

  // -------------------------------------------------------------------------
  // SP-20260615 TASK-06 tests — "Show line numbers" toggle in Appearance group
  // Spec refs: FR-12, FR-13, FR-18, NFR-02, NFR-05
  // -------------------------------------------------------------------------

  group('SettingsScreen — show-line-numbers toggle (TASK-06)', () {
    late _FakeSettingsRepository repo;

    setUp(() {
      repo = _FakeSettingsRepository();
      SharedPreferences.setMockInitialValues({});
    });

    // -----------------------------------------------------------------------
    // TC-18: "Show line numbers" SwitchListTile is present after monospace row.
    //        Default showLineNumbers == false → switch value is false (FR-12).
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-18: show-line-numbers SwitchListTile present, default value false',
      (tester) async {
        // Default AppSettings: showLineNumbers == false.
        await _pumpSettingsScreen(tester, repo);

        // settingsLineNumbers EN: "Show line numbers"
        final sw = tester.widget<SwitchListTile>(
          find.ancestor(
            of: find.text('Show line numbers'),
            matching: find.byType(SwitchListTile),
          ),
        );
        expect(sw.value, isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // TC-19: toggle ON → setShowLineNumbers(true) called →
    //        repo.savedArgs.last.showLineNumbers == true (FR-13).
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-19: toggle ON writes showLineNumbers true through notifier',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(showLineNumbers: false),
        );
        await _pumpSettingsScreen(tester, repo);

        await tester.tap(
          find.ancestor(
            of: find.text('Show line numbers'),
            matching: find.byType(SwitchListTile),
          ),
        );
        await tester.pumpAndSettle();

        expect(repo.savedArgs, isNotEmpty);
        expect(repo.savedArgs.last.showLineNumbers, isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // TC-20: toggle back OFF → repo.savedArgs.last.showLineNumbers == false.
    //        FR-13
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-20: toggle OFF writes showLineNumbers false through notifier',
      (tester) async {
        repo = _FakeSettingsRepository(
          initial: const AppSettings(showLineNumbers: true),
        );
        await _pumpSettingsScreen(tester, repo);

        await tester.tap(
          find.ancestor(
            of: find.text('Show line numbers'),
            matching: find.byType(SwitchListTile),
          ),
        );
        await tester.pumpAndSettle();

        expect(repo.savedArgs, isNotEmpty);
        expect(repo.savedArgs.last.showLineNumbers, isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // TC-21: ≥ 48dp touch target (NFR-02).
    //        The SwitchListTile minimum height is 56dp by Material 3 spec,
    //        which exceeds the 48dp floor.  We assert the rendered height.
    // -----------------------------------------------------------------------
    testWidgets('TC-21: show-line-numbers row height >= 48dp', (tester) async {
      await _pumpSettingsScreen(tester, repo);

      final tile = tester.getRect(
        find.ancestor(
          of: find.text('Show line numbers'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(tile.height, greaterThanOrEqualTo(48.0));
    });

    // -----------------------------------------------------------------------
    // TC-22: key-count unchanged — still 8 SwitchListTiles total (NFR-05).
    //        Appearance: monospace + show-line-numbers (2).
    //        Behavior: recovery + spell-check (2).
    //        Total: 4 (same overall switch count after adding the new row).
    //
    //        NOTE: NFR-05 refers to persistence-key count (8), not widget count.
    //        This test guards widget-count stability so new rows are intentional.
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-22: exactly 4 SwitchListTiles in the screen (no unintended additions)',
      (tester) async {
        await _pumpSettingsScreen(tester, repo);

        expect(find.byType(SwitchListTile), findsNWidgets(4));
      },
    );

    // -----------------------------------------------------------------------
    // TC-23: Italian locale — row title matches app_it.arb settingsLineNumbers.
    //        FR-18
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-23: under it locale show-line-numbers row title is Italian',
      (tester) async {
        await _pumpSettingsScreen(tester, repo, locale: const Locale('it'));

        // settingsLineNumbers IT: "Mostra i numeri di riga"
        expect(find.text('Mostra i numeri di riga'), findsOneWidget);
        // English must NOT appear.
        expect(find.text('Show line numbers'), findsNothing);
      },
    );
  });
}
