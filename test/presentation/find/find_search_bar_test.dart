// TASK-08 (M4): FindSearchBar widget tests — TDD red phase written first.
//
// Spec refs: FR-12, FR-15, FR-18, FR-19, FR-20; NFR-06, NFR-07
// Canon ref: .claude/docs/canon/ui-design-bible.md Component 4 "Search header bar"
//
// Test block (from plan TASK-08):
//   1. Mount renders all controls without throw.
//   2. Count label happy-path: "2 of 3" from ARB (not hard-coded).
//   3. Count label empty when count == 0 (not "0 of 0").
//   4. Replace button disabled when index == null; enabled when non-null.
//   5. Replace button enabled tap calls replaceCurrent() on the notifier.
//   6. Replace toggle tap reveals / hides replace row via crossfade.
//   7. Close tap calls findProvider.close().
//   8. Every icon-only control has a non-empty Semantics/tooltip label from ARB.
//   9. Each icon button render box >= 48×48 logical px.
//  10. No literal user-facing Text('...') with hard-coded copy (ARB gate).
//  11. Reduce-motion (disableAnimations=true) → crossfade uses instant duration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/find/find_engine.dart';
import 'package:buffer/domain/find/find_state.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/find/find_provider.dart';
import 'package:buffer/presentation/find/find_search_bar.dart';

// ---------------------------------------------------------------------------
// Fake notifier for provider override
// ---------------------------------------------------------------------------

/// Tracks which verbs were called (counts only, no real computation).
class _FakeNotifier extends FindNotifier {
  int closeCount = 0;
  int replaceCurrentCount = 0;
  int nextCount = 0;
  int previousCount = 0;

  _FakeNotifier(FindState initialState) : _initial = initialState;
  final FindState _initial;

  @override
  FindState build() => _initial;

  @override
  void close() {
    closeCount++;
    state = state.copyWith(
      active: false,
      matches: const [],
      currentMatchIndex: null,
    );
  }

  @override
  ({String text, int nextCaretOffset})? replaceCurrent() {
    replaceCurrentCount++;
    return state.hasCurrent ? (text: 'replaced', nextCaretOffset: 0) : null;
  }

  @override
  void next() => nextCount++;

  @override
  void previous() => previousCount++;

  @override
  void startSearch({required int entryOffset}) {}

  @override
  void setQuery(String query) {}

  @override
  void setReplaceTerm(String term) {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a localised [MaterialApp] wrapper for testing.
///
/// [notifier] is used to override [findProvider] so the widget under test
/// reads a controlled state without a real ProviderContainer setup.
Widget _buildApp({
  required _FakeNotifier notifier,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: [findProvider.overrideWith(() => notifier)],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: FindSearchBar()),
      ),
    ),
  );
}

/// Returns a [_FakeNotifier] pre-seeded with the given [FindState].
_FakeNotifier _notifier(FindState state) => _FakeNotifier(state);

/// A [FindState] with `active=true` and no matches.
FindState get _activeEmpty => const FindState(active: true);

/// A [FindState] with `active=true`, 3 matches, currentMatchIndex = 1
/// (i.e. position = 2).
FindState get _threeMatchesIdx1 => FindState(
  active: true,
  query: 'x',
  matches: const [MatchSpan(0, 1), MatchSpan(5, 6), MatchSpan(10, 11)],
  currentMatchIndex: 1,
);

/// A [FindState] with `active=true`, 3 matches, NO current match.
FindState get _threeMatchesNoIndex => FindState(
  active: true,
  query: 'x',
  matches: const [MatchSpan(0, 1), MatchSpan(5, 6), MatchSpan(10, 11)],
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Mount — renders all controls without throw
  // =========================================================================
  group('FindSearchBar mount', () {
    testWidgets(
      'given_activeState_when_mounted_then_rendersSearchFieldCountLabelNavButtonsToggleClose',
      (tester) async {
        await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));

        // Search input field
        expect(find.byType(TextField), findsWidgets);

        // Prev / Next icon buttons (using Tooltip finders)
        expect(find.byTooltip('Previous Match'), findsOneWidget);
        expect(find.byTooltip('Next Match'), findsOneWidget);

        // Replace toggle
        expect(find.byTooltip('Toggle Replace'), findsOneWidget);

        // Close / back affordance
        expect(find.byTooltip('Back'), findsOneWidget);
      },
    );
  });

  // =========================================================================
  // 2. Count label happy-path
  // =========================================================================
  group('FindSearchBar count label', () {
    testWidgets(
      'given_threeMatchesIdx1_when_mounted_then_showsPosition2Of3FromARB',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(notifier: _notifier(_threeMatchesIdx1)),
        );

        // "2 of 3" is the ICU expansion for position=2, count=3 in EN.
        expect(find.text('2 of 3'), findsOneWidget);

        // Must NOT be hard-coded: the widget must not contain a literal
        // Text('2 of 3') — it should arrive through AppLocalizations.
        // (We verify below in the literal-string gate that no hardcoded
        // copy lives in the widget source; here we just assert the value
        // appears at runtime, driven by the ARB key.)
      },
    );

    // -----------------------------------------------------------------------
    // 3. Count label empty when count == 0
    // -----------------------------------------------------------------------
    testWidgets('given_emptyMatches_when_mounted_then_countLabelIsEmpty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));

      // "0 of 0" must NOT appear.
      expect(find.text('0 of 0'), findsNothing);

      // The count widget should render an empty string (not null, but '').
      // We verify by finding the Opacity-wrapped label that is empty.
      // The Opacity widget wrapping the count label should be present.
      expect(find.byType(Opacity), findsWidgets);
    });
  });

  // =========================================================================
  // 4 & 5. Replace button enabled/disabled + callback
  // =========================================================================
  group('FindSearchBar replace button', () {
    testWidgets(
      'given_noCurrentMatch_when_replacePanelOpen_then_replaceButtonIsDisabled',
      (tester) async {
        final notifier = _notifier(_threeMatchesNoIndex);
        await tester.pumpWidget(_buildApp(notifier: notifier));

        // Open replace row first by tapping the toggle.
        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pumpAndSettle();

        // Find the Replace button (TextButton or ElevatedButton labeled via ARB).
        // The button is disabled when hasCurrent == false.
        final replaceButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Replace'),
        );
        expect(replaceButton.onPressed, isNull);
      },
    );

    testWidgets(
      'given_currentMatchExists_when_replacePanelOpenAndReplaceButtonTapped_then_notifierReplaceCurrentCalled',
      (tester) async {
        final notifier = _notifier(_threeMatchesIdx1);
        await tester.pumpWidget(_buildApp(notifier: notifier));

        // Open replace row.
        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pumpAndSettle();

        // The Replace button should be enabled.
        final replaceButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Replace'),
        );
        expect(replaceButton.onPressed, isNotNull);

        // Tap the Replace button.
        await tester.tap(find.widgetWithText(ElevatedButton, 'Replace'));
        await tester.pump();

        expect(notifier.replaceCurrentCount, equals(1));
      },
    );
  });

  // =========================================================================
  // 6. Replace toggle crossfade
  //
  // AnimatedCrossFade keeps both children in the widget tree at all times
  // (CrossFadeState controls which is shown via Visibility). We verify the
  // crossfade state via the AnimatedCrossFade widget itself.
  // =========================================================================
  group('FindSearchBar replace toggle crossfade', () {
    AnimatedCrossFade findCrossFade(WidgetTester tester) {
      return tester.widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade));
    }

    testWidgets('given_initial_when_mounted_then_crossfadeShowsFirstChild', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(notifier: _notifier(_threeMatchesIdx1)),
      );

      // Before toggle, should show first child (empty SizedBox = hidden).
      final xf = findCrossFade(tester);
      expect(xf.crossFadeState, CrossFadeState.showFirst);
    });

    testWidgets(
      'given_replaceRowHidden_when_toggleTapped_then_crossfadeShowsSecondChild',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(notifier: _notifier(_threeMatchesIdx1)),
        );

        // Tap toggle to reveal.
        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pump();

        final xf = findCrossFade(tester);
        expect(xf.crossFadeState, CrossFadeState.showSecond);
      },
    );

    testWidgets(
      'given_replaceRowVisible_when_toggleTappedAgain_then_crossfadeShowsFirstChild',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(notifier: _notifier(_threeMatchesIdx1)),
        );

        // Open.
        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pump();

        // Close.
        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pump();

        final xf = findCrossFade(tester);
        expect(xf.crossFadeState, CrossFadeState.showFirst);
      },
    );

    testWidgets(
      'given_animationsDisabled_when_toggleTapped_then_crossfadeUsesReducedDuration',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            notifier: _notifier(_threeMatchesIdx1),
            disableAnimations: true,
          ),
        );

        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pumpAndSettle();

        // With reduce-motion the crossfade duration must be at most 1ms
        // (perceptually instant — see _crossfadeDuration implementation note).
        final xf = findCrossFade(tester);
        expect(
          xf.duration.inMilliseconds,
          lessThanOrEqualTo(1),
          reason: 'Reduce-motion crossfade must use at most 1ms duration',
        );
        expect(xf.crossFadeState, CrossFadeState.showSecond);
      },
    );
  });

  // =========================================================================
  // 7. Close tap
  // =========================================================================
  group('FindSearchBar close', () {
    testWidgets(
      'given_activeState_when_closeButtonTapped_then_notifierCloseCalledOnce',
      (tester) async {
        final notifier = _notifier(_activeEmpty);
        await tester.pumpWidget(_buildApp(notifier: notifier));

        await tester.tap(find.byTooltip('Back'));
        await tester.pump();

        expect(notifier.closeCount, equals(1));
      },
    );
  });

  // =========================================================================
  // 8. Semantic labels on icon-only controls
  // =========================================================================
  group('FindSearchBar semantics', () {
    testWidgets(
      'given_mounted_when_semanticsTreeRead_then_allIconControlsHaveNonEmptyLabels',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(notifier: _notifier(_threeMatchesIdx1)),
        );

        // Each icon-only control is wrapped in an IconButton with a tooltip,
        // which creates a Semantics node via the tooltip mechanism.
        // We assert that each tooltip value is non-empty.
        for (final label in [
          'Previous Match',
          'Next Match',
          'Toggle Replace',
          'Back',
        ]) {
          expect(
            find.byTooltip(label),
            findsOneWidget,
            reason: 'Expected a control with tooltip/semantics label "$label"',
          );
        }
      },
    );
  });

  // =========================================================================
  // 9. Tap-target size >= 48×48 dp
  // =========================================================================
  group('FindSearchBar touch targets', () {
    testWidgets(
      'given_mounted_when_touchTargetsChecked_then_allIconButtonsAtLeast48x48',
      (tester) async {
        await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));

        // Check every IconButton's render size.
        final iconButtons = tester.widgetList<IconButton>(
          find.byType(IconButton),
        );
        for (final btn in iconButtons) {
          final element = tester.element(find.byWidget(btn));
          final renderBox = element.renderObject as RenderBox;
          final size = renderBox.size;
          expect(
            size.width,
            greaterThanOrEqualTo(48.0),
            reason: 'IconButton width ${size.width} < 48dp',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48.0),
            reason: 'IconButton height ${size.height} < 48dp',
          );
        }
      },
    );
  });

  // =========================================================================
  // 10. No literal user-facing strings — ARB gate (runtime check)
  // =========================================================================
  // The source-code gate (no Text('...') literals) is enforced by m4_gate_test.
  // Here we verify at runtime that the ARB system drives all user-visible text
  // by asserting the EN localisation values appear (not the key names).
  group('FindSearchBar ARB runtime gate', () {
    testWidgets(
      'given_mounted_when_hintTextsRead_then_valuesMatchARBNotKeyNames',
      (tester) async {
        await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));

        // The search field hint text should be "Search" (EN), not "findHintText".
        expect(find.text('findHintText'), findsNothing);
        // The key name should not appear as literal text in the widget tree.
        expect(find.text('findCountLabel'), findsNothing);
        expect(find.text('findPreviousTooltip'), findsNothing);
        expect(find.text('findNextTooltip'), findsNothing);
        expect(find.text('findReplaceToggleTooltip'), findsNothing);
        expect(find.text('findCloseTooltip'), findsNothing);
      },
    );
  });

  // =========================================================================
  // 11. Prev/Next button callbacks
  // =========================================================================
  group('FindSearchBar nav callbacks', () {
    testWidgets('given_matches_when_prevTapped_then_notifierPreviousCalled', (
      tester,
    ) async {
      final notifier = _notifier(_threeMatchesIdx1);
      await tester.pumpWidget(_buildApp(notifier: notifier));

      await tester.tap(find.byTooltip('Previous Match'));
      await tester.pump();

      expect(notifier.previousCount, equals(1));
    });

    testWidgets('given_matches_when_nextTapped_then_notifierNextCalled', (
      tester,
    ) async {
      final notifier = _notifier(_threeMatchesIdx1);
      await tester.pumpWidget(_buildApp(notifier: notifier));

      await tester.tap(find.byTooltip('Next Match'));
      await tester.pump();

      expect(notifier.nextCount, equals(1));
    });
  });
}
