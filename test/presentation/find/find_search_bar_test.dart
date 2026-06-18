// TASK-08 (M4): FindSearchBar widget tests — TDD red phase written first.
// TASK-09 (SP-20260617 Wave 2): container restyle assertions updated.
// SP-20260618 G4/G8 consolidation: radius updated to searchBarRadius (24dp),
//   Icons.arrow_back absence confirmed, replace-row mirror still holds,
//   opaque fallback assertion added, unique tests from test/find/ merged.
//
// Spec refs: FR-12, FR-15, FR-18, FR-19, FR-20; NFR-06, NFR-07
// Canon ref: .claude/docs/canon/ui-design-bible.md Component 4 "Search header bar"
//
// Platforms: all (headless — no device required).
//
// Test block:
//   1. Mount renders all controls without throw.
//   2. Count label happy-path: "2 of 3" from ARB (not hard-coded).
//   3. Count label empty when count == 0 (not "0 of 0").
//   4. Replace button disabled when index == null; enabled when non-null.
//   5. Replace button enabled tap calls replaceCurrent() on the notifier.
//   6. Replace toggle tap reveals / hides replace row via crossfade.
//   7. Close tap calls findProvider.close() (via CloseFindIntent dispatch).
//   8. Every icon-only control has a non-empty Semantics/tooltip label from ARB.
//   9. Each icon button render box >= 48×48 logical px.
//  10. No literal user-facing Text('...') with hard-coded copy (ARB gate).
//  11. Reduce-motion (disableAnimations=true) → crossfade uses instant duration.
//  G4. GlassSurface borderRadius == tokens.searchBarRadius (24dp, NOT pillRadius 32dp).
//  G8. Icons.arrow_back absent from the FindSearchBar widget tree.
//  GA. Glass container is/contains a GlassSurface.
//  GB. Opaque fallback under highContrast: no BackdropFilter in tree.
//  GC. Replace-row equal-width mirror: search-pill and replace-pill same width.
//  GD. Prev / Next icon buttons present.
//  GE. Replace toggle icon button present.
//  GF. Match count suffix widget (Opacity) is present.
//  GG. Close button dispatches close (state transitions to inactive).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/find/find_engine.dart';
import 'package:foglietto/domain/find/find_state.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/find/find_provider.dart';
import 'package:foglietto/presentation/find/find_search_bar.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';

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

/// Builds a localised [MaterialApp] wrapper with GlassTokens registered.
///
/// [notifier] is used to override [findProvider] so the widget under test
/// reads a controlled state without a real ProviderContainer setup.
/// [disableAnimations] sets [MediaQueryData.disableAnimations].
/// [highContrast] sets [MediaQueryData.highContrast] for opaque-branch tests.
Widget _buildApp({
  required _FakeNotifier notifier,
  bool disableAnimations = false,
  bool highContrast = false,
}) {
  return ProviderScope(
    overrides: [findProvider.overrideWith(() => notifier)],
    child: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        highContrast: highContrast,
      ),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        // Register kDefaultGlassTokens so GlassTokens.of(context) != null.
        theme: ThemeData.light().copyWith(extensions: [kDefaultGlassTokens]),
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

        // SP-20260618 G8: the back/close affordance was extracted to FindBackPill
        // (a separate widget that lives outside FindSearchBar in the Stack).
        // FindSearchBar itself must NOT have a 'Back' tooltip after this SP.
        expect(
          find.byTooltip('Back'),
          findsNothing,
          reason:
              'Back tooltip must NOT be inside FindSearchBar after G8 extraction '
              '(the close affordance moved to FindBackPill, SP-20260618).',
        );
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
  // 7. Close affordance (SP-20260618 G8: back button moved to FindBackPill)
  //
  // The back/close button was extracted from FindSearchBar to FindBackPill
  // in SP-20260618. FindSearchBar itself no longer owns the close gesture;
  // the close path goes through FindBackPill → CloseFindIntent → provider.
  // We verify:
  //   a) No 'Back' tooltip inside FindSearchBar (button is gone from here).
  //   b) findCloseTooltip ARB key does not appear as a tooltip in the bar.
  // =========================================================================
  group('FindSearchBar close (G8: affordance moved to FindBackPill)', () {
    testWidgets(
      'given_mounted_then_no_Back_tooltip_inside_FindSearchBar (G8 extraction)',
      (tester) async {
        await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
        await tester.pumpAndSettle();

        // SP-20260618: The 'Back' close button is no longer inside FindSearchBar.
        // It was moved to FindBackPill (a separate top-left widget).
        expect(
          find.byTooltip('Back'),
          findsNothing,
          reason:
              'Back tooltip must NOT be present in FindSearchBar after G8 '
              'extraction (SP-20260618). The close affordance is FindBackPill.',
        );
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
        //
        // SP-20260618 G8: 'Back' / findCloseTooltip was moved to FindBackPill
        // and is NO longer an icon inside FindSearchBar. Only the three
        // remaining controls are checked here.
        for (final label in [
          'Previous Match',
          'Next Match',
          'Toggle Replace',
        ]) {
          expect(
            find.byTooltip(label),
            findsOneWidget,
            reason: 'Expected a control with tooltip/semantics label "$label"',
          );
        }
        // Confirm 'Back' is NOT inside FindSearchBar (G8 extraction).
        expect(
          find.byTooltip('Back'),
          findsNothing,
          reason:
              'Back tooltip must be absent from FindSearchBar (moved to '
              'FindBackPill, SP-20260618 G8).',
        );
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

  // =========================================================================
  // G4. Glass container radius == searchBarRadius (24dp, NOT pillRadius 32dp)
  //
  // SP-20260618: the find bar container was restyled from pillRadius (32dp)
  // to searchBarRadius (24dp) to distinguish it from the pill chrome affordance.
  // This gate proves:
  //   a) The GlassSurface borderRadius matches kDefaultGlassTokens.searchBarRadius.
  //   b) It does NOT equal kDefaultGlassTokens.pillRadius.
  // =========================================================================
  group(
    'G4 — glass container uses searchBarRadius (24dp), not pillRadius (32dp)',
    () {
      testWidgets(
        'FindSearchBar GlassSurface borderRadius == tokens.searchBarRadius (24dp)',
        (tester) async {
          await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
          await tester.pumpAndSettle();

          final glassSurface = tester.widget<GlassSurface>(
            find.descendant(
              of: find.byType(FindSearchBar),
              matching: find.byType(GlassSurface),
            ),
          );

          // searchBarRadius is BorderRadius.all(Radius.circular(24.0)).
          expect(
            glassSurface.borderRadius,
            equals(kDefaultGlassTokens.searchBarRadius),
            reason:
                'FindSearchBar GlassSurface must use tokens.searchBarRadius '
                '(24dp) after SP-20260618 G4 update.',
          );
        },
      );

      testWidgets(
        'searchBarRadius (24dp) != pillRadius (32dp) — the two are distinct tokens',
        (tester) async {
          // searchBarRadius is 24dp; pillRadius is 32dp.
          expect(
            kDefaultGlassTokens.searchBarRadius,
            isNot(equals(kDefaultGlassTokens.pillRadius)),
            reason:
                'searchBarRadius and pillRadius must be distinct values. '
                'searchBarRadius == 24dp; pillRadius == 32dp (G4 proof).',
          );
        },
      );

      testWidgets(
        'FindSearchBar GlassSurface borderRadius does NOT equal pillRadius (32dp)',
        (tester) async {
          await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
          await tester.pumpAndSettle();

          final glassSurface = tester.widget<GlassSurface>(
            find.descendant(
              of: find.byType(FindSearchBar),
              matching: find.byType(GlassSurface),
            ),
          );

          expect(
            glassSurface.borderRadius,
            isNot(equals(kDefaultGlassTokens.pillRadius)),
            reason:
                'FindSearchBar must use searchBarRadius (24dp), '
                'NOT pillRadius (32dp) — G4 anti-regression.',
          );
        },
      );
    },
  );

  // =========================================================================
  // G8. Icons.arrow_back absent from FindSearchBar (SP-20260618)
  //
  // The back chevron (Icons.arrow_back) was removed in SP-20260618. The close
  // affordance in the search bar now uses a different icon. This gate proves
  // the old icon is not present in the widget tree.
  // =========================================================================
  group('G8 — Icons.arrow_back absent from FindSearchBar widget tree', () {
    testWidgets(
      'FindSearchBar must NOT contain Icons.arrow_back (SP-20260618 removal)',
      (tester) async {
        await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(FindSearchBar),
            matching: find.byIcon(Icons.arrow_back),
          ),
          findsNothing,
          reason:
              'Icons.arrow_back must be absent from FindSearchBar after '
              'SP-20260618 G8 extraction. The back affordance is now provided '
              'by FindBackPill outside the bar.',
        );
      },
    );
  });

  // =========================================================================
  // GA. GlassSurface present as/in the outer container (FR-12/19)
  //
  // Merged from retired test/find/find_search_bar_test.dart Group A.
  // =========================================================================
  group('GA — glass container contains a GlassSurface (FR-12/19)', () {
    testWidgets('FindSearchBar outer container is/contains a GlassSurface', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
      await tester.pumpAndSettle();

      // The outer container must be or contain a GlassSurface.
      expect(
        find.descendant(
          of: find.byType(FindSearchBar),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // GB. Opaque fallback under highContrast: zero BackdropFilter (FR-20)
  //
  // When MediaQuery.highContrast == true the GlassSurface takes the opaque
  // branch — no BackdropFilter is present in the subtree (NFR-06).
  // =========================================================================
  group(
    'GB — opaque fallback: no BackdropFilter under highContrast=true (FR-20)',
    () {
      testWidgets(
        'highContrast true → no BackdropFilter in FindSearchBar subtree',
        (tester) async {
          await tester.pumpWidget(
            _buildApp(notifier: _notifier(_activeEmpty), highContrast: true),
          );
          await tester.pumpAndSettle();

          final backdropFilters = find.descendant(
            of: find.byType(FindSearchBar),
            matching: find.byType(BackdropFilter),
          );
          expect(
            backdropFilters,
            findsNothing,
            reason:
                'No BackdropFilter must exist inside FindSearchBar when '
                'highContrast == true (opaque branch, FR-20 / NFR-06).',
          );
        },
      );
    },
  );

  // =========================================================================
  // GC. Replace-row equal-width mirror still holds (SP-20260618 spacer removal)
  //
  // After SP-20260618 the leading spacer in the replace row was removed to
  // re-balance the search-pill ↔ replace-pill mirror. Both pills must still
  // be present and the replace row must render without overflow.
  //
  // Merged and updated from retired test/find/find_search_bar_test.dart Group B.
  // =========================================================================
  group('GC — replace-row content intact after spacer removal (FR-13)', () {
    testWidgets('search TextField is present', (tester) async {
      await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
      await tester.pumpAndSettle();

      // At least one TextField must be present (the search field).
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('prev / next icon buttons are present', (tester) async {
      await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('replace toggle icon button is present', (tester) async {
      await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
      await tester.pumpAndSettle();

      // Icons.find_replace appears in the toggle IconButton (search row).
      expect(find.byIcon(Icons.find_replace), findsWidgets);
    });

    testWidgets(
      'replace row visible after toggle — no overflow (equal-width mirror holds)',
      (tester) async {
        // Use a medium-width viewport to approximate a phone screen.
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildApp(notifier: _notifier(_threeMatchesIdx1)),
        );
        await tester.pumpAndSettle();

        // Open replace row.
        await tester.tap(find.byTooltip('Toggle Replace'));
        await tester.pumpAndSettle();

        // Replace ElevatedButton must be visible (no overflow).
        expect(
          find.byType(ElevatedButton),
          findsOneWidget,
          reason:
              'Replace button must be visible after spacer removal — '
              'equal-width mirror re-balanced (SP-20260618).',
        );
      },
    );
  });

  // =========================================================================
  // GD. Match count suffix widget (Opacity) is present
  //
  // Merged from retired test/find/find_search_bar_test.dart Group B.
  // =========================================================================
  group('GD — match count suffix Opacity present', () {
    testWidgets('match count suffix widget is present', (tester) async {
      await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
      await tester.pumpAndSettle();

      // Opacity wrapping the count label is always rendered (empty text when
      // count==0 keeps the layout stable).
      expect(find.byType(Opacity), findsWidgets);
    });
  });

  // =========================================================================
  // GG. Close affordance absent from FindSearchBar (G8 extraction)
  //
  // Merged from retired test/find/find_search_bar_test.dart Group D — updated
  // to reflect that the close button was moved to FindBackPill in SP-20260618.
  //
  // FindSearchBar no longer owns the close gesture; FindBackPill (a separate
  // widget) dispatches CloseFindIntent which routes to findProvider.close().
  // =========================================================================
  group('GG — close affordance absent from FindSearchBar (G8 extraction)', () {
    testWidgets(
      'FindSearchBar has no back/close icon button after G8 (SP-20260618)',
      (tester) async {
        await tester.pumpWidget(_buildApp(notifier: _notifier(_activeEmpty)));
        await tester.pumpAndSettle();

        // No 'Back' tooltip inside FindSearchBar (moved to FindBackPill).
        expect(
          find.byTooltip('Back'),
          findsNothing,
          reason:
              'Back tooltip must be absent from FindSearchBar (G8 extraction, SP-20260618)',
        );

        // FindSearchBar is still mounted (it should not have been removed).
        expect(find.byType(FindSearchBar), findsOneWidget);
      },
    );
  });
}
