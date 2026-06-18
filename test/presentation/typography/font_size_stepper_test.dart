// Tests for FontSizeStepper — TASK-05
//
// Spec refs : FR-M7-06, FR-M7-12, NFR-M7-05, NFR-M7-07
// Canon ref : .claude/docs/canon/ui-design-bible.md §5 "Font-size selector"
//
// Verifies:
//   1. Label: slotList[index] displayed as '{n}pt'.
//   2. Decrease disabled at index 0; increase enabled. Increase disabled at
//      index 20; decrease enabled.
//   3. Decrease tap calls settingsProvider.notifier.setFontSizeIndex(index-1).
//   4. Increase tap calls settingsProvider.notifier.setFontSizeIndex(index+1).
//   5. Both IconButtons have ≥48 dp BoxConstraints (NFR-M7-05).
//   6. Semantics: decrease == l10n.a11yZoomOut; increase == l10n.a11yZoomIn.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/domain/settings/settings_repository.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';
import 'package:foglietto/presentation/typography/font_size_stepper.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A recording repository that loads from a mutable [_stored] state
/// and records every [save] call.
class _RecordingRepository implements SettingsRepository {
  AppSettings _stored;
  final List<AppSettings> savedArgs = [];

  _RecordingRepository({required AppSettings initial}) : _stored = initial;

  @override
  Future<AppSettings> load() async => _stored;

  @override
  Future<void> save(AppSettings settings) async {
    _stored = settings;
    savedArgs.add(settings);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps the [FontSizeStepper] inside a [MaterialApp] + [ProviderScope],
/// seeding [settingsProvider] with [initial].
Future<void> _pumpStepper(
  WidgetTester tester,
  _RecordingRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: FontSizeStepper())),
      ),
    ),
  );
  // Let the AsyncNotifier build phase complete.
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  // --------------------------------------------------------------------------
  // 1. Label: slot value rendered as '{n}pt'
  // --------------------------------------------------------------------------

  group('FontSizeStepper — label shows slot value as {n}pt', () {
    test('given_fontSizeIndex_8_when_pump_then_label_contains_14pt', () async {
      // Index 8 → slotList[8] == 14 → "14pt".
      // This is a unit-style data check (no widget pump needed).
      expect(AppSettings.slotList[8], equals(14));
      expect('${AppSettings.slotList[8]}pt', equals('14pt'));
    });

    testWidgets(
      'given_fontSizeIndex_8_when_stepper_pumped_then_text_contains_14pt',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 8),
        );
        await _pumpStepper(tester, repo);

        expect(
          find.text('14pt'),
          findsOneWidget,
          reason: 'fontSizeIndex 8 → slotList[8]==14 → label must be "14pt"',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_0_when_stepper_pumped_then_text_contains_6pt',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 0),
        );
        await _pumpStepper(tester, repo);

        expect(
          find.text('6pt'),
          findsOneWidget,
          reason: 'fontSizeIndex 0 → slotList[0]==6 → label must be "6pt"',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_20_when_stepper_pumped_then_text_contains_38pt',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 20),
        );
        await _pumpStepper(tester, repo);

        expect(
          find.text('38pt'),
          findsOneWidget,
          reason: 'fontSizeIndex 20 → slotList[20]==38 → label must be "38pt"',
        );
      },
    );
  });

  // --------------------------------------------------------------------------
  // 2. Disable states at ends
  // --------------------------------------------------------------------------

  group('FontSizeStepper — disable at ends', () {
    testWidgets(
      'given_fontSizeIndex_0_then_decrease_button_is_disabled_and_increase_is_enabled',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 0),
        );
        await _pumpStepper(tester, repo);

        // Decrease is the first IconButton (Icons.remove).
        final decreaseButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.remove),
        );
        final increaseButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add),
        );

        expect(
          decreaseButton.onPressed,
          isNull,
          reason:
              'At index 0, decrease must be disabled (onPressed == null); '
              'FR-M7-06 / canon §5',
        );
        expect(
          increaseButton.onPressed,
          isNotNull,
          reason: 'At index 0, increase must be enabled',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_20_then_increase_button_is_disabled_and_decrease_is_enabled',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 20),
        );
        await _pumpStepper(tester, repo);

        final decreaseButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.remove),
        );
        final increaseButton = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add),
        );

        expect(
          increaseButton.onPressed,
          isNull,
          reason:
              'At index 20, increase must be disabled (onPressed == null); '
              'FR-M7-06 / canon §5',
        );
        expect(
          decreaseButton.onPressed,
          isNotNull,
          reason: 'At index 20, decrease must be enabled',
        );
      },
    );
  });

  // --------------------------------------------------------------------------
  // 3 & 4. Tap calls setFontSizeIndex with the adjacent index
  // --------------------------------------------------------------------------

  group('FontSizeStepper — tap calls setFontSizeIndex', () {
    testWidgets(
      'given_fontSizeIndex_10_when_decrease_tapped_then_setFontSizeIndex_9_called',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 10),
        );
        await _pumpStepper(tester, repo);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
        await tester.pumpAndSettle();

        expect(
          repo.savedArgs,
          isNotEmpty,
          reason: 'Tapping decrease must trigger a save',
        );
        expect(
          repo.savedArgs.last.fontSizeIndex,
          equals(9),
          reason:
              'Tapping decrease at index 10 must call setFontSizeIndex(9); '
              'FR-M7-06',
        );
      },
    );

    testWidgets(
      'given_fontSizeIndex_10_when_increase_tapped_then_setFontSizeIndex_11_called',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 10),
        );
        await _pumpStepper(tester, repo);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
        await tester.pumpAndSettle();

        expect(
          repo.savedArgs,
          isNotEmpty,
          reason: 'Tapping increase must trigger a save',
        );
        expect(
          repo.savedArgs.last.fontSizeIndex,
          equals(11),
          reason:
              'Tapping increase at index 10 must call setFontSizeIndex(11); '
              'FR-M7-06',
        );
      },
    );
  });

  // --------------------------------------------------------------------------
  // 5. Touch targets ≥ 48 dp
  // --------------------------------------------------------------------------

  group('FontSizeStepper — touch targets ≥ 48 dp (NFR-M7-05)', () {
    testWidgets(
      'both_IconButtons_have_minimum_size_constraints_of_at_least_48x48',
      (tester) async {
        final repo = _RecordingRepository(
          initial: const AppSettings(fontSizeIndex: 10),
        );
        await _pumpStepper(tester, repo);

        // Find both IconButton render objects and check their size via the
        // SizedBox wrapper used to enforce the 48dp target.
        final decreaseFinder = find.widgetWithIcon(IconButton, Icons.remove);
        final increaseFinder = find.widgetWithIcon(IconButton, Icons.add);

        // Walk up to the parent SizedBox that enforces the minimum size.
        final decreaseBox = tester.getSize(decreaseFinder);
        final increaseBox = tester.getSize(increaseFinder);

        expect(
          decreaseBox.width,
          greaterThanOrEqualTo(48.0),
          reason:
              'Decrease button rendered width must be ≥48dp (NFR-M7-05; '
              'canon §5 "each ≥48dp")',
        );
        expect(
          decreaseBox.height,
          greaterThanOrEqualTo(48.0),
          reason: 'Decrease button rendered height must be ≥48dp',
        );
        expect(
          increaseBox.width,
          greaterThanOrEqualTo(48.0),
          reason: 'Increase button rendered width must be ≥48dp',
        );
        expect(
          increaseBox.height,
          greaterThanOrEqualTo(48.0),
          reason: 'Increase button rendered height must be ≥48dp',
        );
      },
    );
  });

  // --------------------------------------------------------------------------
  // 6. Semantics labels
  // --------------------------------------------------------------------------

  group('FontSizeStepper — semantics labels (NFR-M7-07)', () {
    testWidgets('decrease_button_carries_a11yZoomOut_semantics_label', (
      tester,
    ) async {
      final repo = _RecordingRepository(
        initial: const AppSettings(fontSizeIndex: 10),
      );
      await _pumpStepper(tester, repo);

      // The EN l10n value for a11yZoomOut is "Decrease font size".
      expect(
        find.bySemanticsLabel('Decrease font size'),
        findsOneWidget,
        reason:
            'Decrease button must carry l10n.a11yZoomOut Semantics label '
            '("Decrease font size" in EN); NFR-M7-07 / canon §5',
      );
    });

    testWidgets('increase_button_carries_a11yZoomIn_semantics_label', (
      tester,
    ) async {
      final repo = _RecordingRepository(
        initial: const AppSettings(fontSizeIndex: 10),
      );
      await _pumpStepper(tester, repo);

      // The EN l10n value for a11yZoomIn is "Increase font size".
      expect(
        find.bySemanticsLabel('Increase font size'),
        findsOneWidget,
        reason:
            'Increase button must carry l10n.a11yZoomIn Semantics label '
            '("Increase font size" in EN); NFR-M7-07 / canon §5',
      );
    });
  });
}
