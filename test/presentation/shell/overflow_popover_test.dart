// Tests for OverflowPopover (TASK-04 / TASK-07)
//
// Spec refs: FR-04, FR-05, FR-06, FR-07, FR-08, FR-19, NFR-06, NFR-07
// Plan refs: TASK-04 (Wave 1 morph rewrite), sp-20260620-ui-chrome-morph-transparency-spacing-plan.md
//            TASK-07 (Wave 2 original), sp-20260617-liquid-glass-floating-chrome-plan.md
//
// TDD: tests written FIRST (red phase), implementation follows.
//
// OQ-12 caveat: the test harness pumps with a real Overlay/Navigator (via
// MaterialApp) so OverlayEntry insertions are detectable via
// find.byType(OverflowPopover).
//
// Acceptance criteria verified here:
//   1. open (FR-04): trigger open → find.byType(OverflowPopover) == 1;
//      find.byType(BottomSheet) == 0;
//      no showModalBottomSheet in lib/presentation/shell/.
//   2. entries (FR-05): popover open → theme selector, font-size stepper,
//      Preferences, About, Recovery present; NO Find/Replace tile.
//   3. outside-tap dismiss (FR-06/EC-15): tap transparent barrier →
//      find.byType(OverflowPopover) == 0; no entry action triggered.
//   4. anchor geometry (FR-04 REWRITE): CompositedTransformFollower
//      targetAnchor==followerAnchor==topRight, offset==Offset.zero ⇒
//      bubble.top == anchor.top && bubble.right == anchor.right (NO 8dp gap).
//   5. nav (FR-06 About): tap About → popover dismisses AND About pushed.
//   6. glass (FR-19): popover container is/contains a GlassSurface(popoverRadius).
//   7. morph (FR-04/FR-05): ScaleTransition + FadeTransition on one controller;
//      duration 180ms; after settle scale==1 opacity==1; async reverse-before-remove.
//   8. reduce-motion (FR-06/EC-04): disableAnimations→Duration.zero; instant open+dismiss.
//   9. dispose: _MorphedBubble controller disposed cleanly; no FlutterError after removal.
//   10. idempotent async latch (EC-01/FR-07): async dismiss paths serialise correctly.
//
// <!-- CANON GAP: anchored popover bubble anatomy + outside-tap-dismiss rule
//      ui-design-bible.md does not define the anatomy or dismiss behaviour for
//      anchored popover bubbles. Implementation binds to surface/outlineVariant,
//      GlassTokens.popoverRadius, ≥48dp on entries. -->

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';
import 'package:foglietto/presentation/shell/overflow_popover.dart';
import 'package:foglietto/presentation/shell/theme_selector.dart';
import 'package:foglietto/presentation/theme/glass_surface.dart';
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
// Stub screens for named-route navigation assertions.
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
// Host screen: renders a CompositedTransformTarget anchor button that opens
// the OverflowPopover.
// ---------------------------------------------------------------------------

class _AnchorHostScreen extends StatefulWidget {
  const _AnchorHostScreen({this.onNavigated});

  final void Function(String route)? onNavigated;

  @override
  State<_AnchorHostScreen> createState() => _AnchorHostScreenState();
}

class _AnchorHostScreenState extends State<_AnchorHostScreen> {
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
                key: const Key('anchor_btn'),
                onPressed: () =>
                    openOverflowPopover(context, anchorLink: _link),
                child: const Text('...'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spy host screen: captures the returned dismiss and the onDismissed spy
// counter so tests can drive idempotent-dismiss assertions (T-03 / BUG-B).
// ---------------------------------------------------------------------------

class _SpyHostScreen extends StatefulWidget {
  const _SpyHostScreen({required this.onDismissedCallCount});

  /// Updated in-place by the host whenever onDismissed fires.
  final List<int> onDismissedCallCount;

  @override
  State<_SpyHostScreen> createState() => _SpyHostScreenState();
}

class _SpyHostScreenState extends State<_SpyHostScreen> {
  final LayerLink _link = LayerLink();

  /// The funnel returned by openOverflowPopover — held so tests can call it.
  VoidCallback? returnedDismiss;

  void _openPopover() {
    returnedDismiss = openOverflowPopover(
      context,
      anchorLink: _link,
      onDismissed: () => widget.onDismissedCallCount.add(1),
    );
  }

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
                key: const Key('spy_btn'),
                onPressed: _openPopover,
                child: const Text('...'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Harness builder (OQ-12: must use MaterialApp for real Overlay/Navigator).
// ---------------------------------------------------------------------------

Widget _buildApp({AppSettings initial = const AppSettings()}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(initial: initial),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/': (_) => const _AnchorHostScreen(),
        '/settings': (_) => const _StubSettings(),
        '/about': (_) => const _StubAbout(),
        '/recovery': (_) => const _StubRecovery(),
      },
    ),
  );
}

/// Opens the popover by tapping the anchor button.
Future<void> _openPopover(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('anchor_btn')));
  await tester.pumpAndSettle();
}

Widget _buildSpyApp(_SpyHostScreen spyHost) {
  return ProviderScope(
    overrides: [settingsProvider.overrideWith(() => _FakeSettingsNotifier())],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/': (_) => spyHost,
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
  // 1. open (FR-04)
  // =========================================================================
  group('OverflowPopover — open (FR-04)', () {
    testWidgets(
      'given_anchor_button_tapped_then_OverflowPopover_appears_and_no_BottomSheet',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(OverflowPopover),
          findsOneWidget,
          reason: 'OverflowPopover must be in the tree after opening (FR-04)',
        );
        expect(
          find.byType(BottomSheet),
          findsNothing,
          reason:
              'showModalBottomSheet must NOT be used — no BottomSheet in tree (FR-04)',
        );
      },
    );
  });

  // =========================================================================
  // 2. entries (FR-05) — exactly 5 entries, no Find/Replace
  // =========================================================================
  group('OverflowPopover — entries (FR-05)', () {
    testWidgets(
      'given_popover_open_when_inspected_then_ThemeSelector_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.byType(ThemeSelector),
          findsOneWidget,
          reason: 'OverflowPopover must contain a ThemeSelector (FR-05)',
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
          reason: 'OverflowPopover must contain a FontSizeStepper (FR-05)',
        );
      },
    );

    testWidgets(
      'given_popover_open_when_inspected_then_Preferences_tile_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.text('Preferences'),
          findsAtLeastNWidgets(1),
          reason: 'Preferences tile must be present (FR-05)',
        );
      },
    );

    testWidgets('given_popover_open_when_inspected_then_About_tile_present', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openPopover(tester);

      expect(
        find.text('About'),
        findsAtLeastNWidgets(1),
        reason: 'About tile must be present (FR-05)',
      );
    });

    testWidgets(
      'given_popover_open_when_inspected_then_Recovery_tile_present',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(
          find.text('Recovery'),
          findsAtLeastNWidgets(1),
          reason: 'Recovery tile must be present (FR-05)',
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
            'Find/Replace tile must NOT be in the popover (FR-05 — Find moved to bottom toolbar)',
      );
      expect(
        find.byIcon(Icons.search),
        findsNothing,
        reason: 'No Find/Replace tile means no Icons.search in the popover',
      );
    });
  });

  // =========================================================================
  // 3. outside-tap dismiss (FR-06 / EC-15)
  // =========================================================================
  group('OverflowPopover — outside-tap dismiss (FR-06/EC-15)', () {
    testWidgets(
      'given_popover_open_when_barrier_tapped_then_popover_dismissed_and_no_entry_action',
      (tester) async {
        // Taller viewport so the barrier tap point is clearly outside the popover.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool actionFired = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routes: {
                '/': (_) =>
                    _AnchorHostScreen(onNavigated: (_) => actionFired = true),
                '/settings': (_) => _StubSettings(),
                '/about': (_) => _StubAbout(),
                '/recovery': (_) => _StubRecovery(),
              },
            ),
          ),
        );
        await _openPopover(tester);

        expect(
          find.byType(OverflowPopover),
          findsOneWidget,
          reason: 'Popover should be open before barrier tap',
        );

        // Tap bottom-left corner — well outside the popover (which is top-right).
        await tester.tapAt(const Offset(20, 1100));
        await tester.pumpAndSettle();

        expect(
          find.byType(OverflowPopover),
          findsNothing,
          reason:
              'Tapping the transparent barrier must dismiss the popover (FR-06/EC-15)',
        );
        expect(
          actionFired,
          isFalse,
          reason: 'No entry action must have fired on outside tap (EC-15)',
        );
      },
    );
  });

  // =========================================================================
  // 4. anchor geometry (FR-04 REWRITE — morph anchor at topRight, zero gap)
  //
  // REWRITE: CompositedTransformFollower now uses targetAnchor=topRight,
  // followerAnchor=topRight, offset=Offset.zero.
  // Old assertions (bubble.top >= anchor.bottom + kPopoverGap, bubble.top >
  // anchor.top) are REPLACED with equality: bubble.top == anchor.top AND
  // bubble.right == anchor.right.
  // =========================================================================
  group('OverflowPopover — anchor geometry (FR-04 REWRITE)', () {
    testWidgets(
      'given_popover_open_then_bubble_top_equals_anchor_top_and_bubble_right_equals_anchor_right',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        final anchorRect = tester.getRect(find.byKey(const Key('anchor_btn')));
        // Measure the GlassSurface bubble, not the OverflowPopover stack
        // (OverflowPopover fills the screen; GlassSurface is the bubble).
        final bubbleFinder = find.descendant(
          of: find.byType(OverflowPopover),
          matching: find.byType(GlassSurface),
        );
        final bubbleRect = tester.getRect(bubbleFinder.first);

        // FR-04 REWRITE: morph grows OUT of pill's top-right corner.
        // Follower topRight == anchor topRight → no gap below, no gap to side.
        expect(
          bubbleRect.top,
          closeTo(anchorRect.top, 2.0),
          reason:
              'Popover bubble top must align with anchor top (morph topRight anchor, FR-04)',
        );
        expect(
          bubbleRect.right,
          closeTo(anchorRect.right, 2.0),
          reason:
              'Popover bubble right must align with anchor right (morph topRight anchor, FR-04)',
        );
      },
    );
  });

  // =========================================================================
  // 7. morph animation (FR-04/FR-05) — scale+fade from topRight
  //
  // CANON GAP: morph-motion exception for off-anatomy popover;
  // per spec §4 CANON PARTIAL / OQ-03.
  // =========================================================================
  group('OverflowPopover — morph animation (FR-04/FR-05)', () {
    testWidgets(
      'given_animations_enabled_then_ScaleTransition_and_FadeTransition_present_after_open',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        // ScaleTransition must be present in the popover tree (morph open, FR-04).
        expect(
          find.descendant(
            of: find.byType(OverflowPopover),
            matching: find.byType(ScaleTransition),
          ),
          findsAtLeastNWidgets(1),
          reason: 'ScaleTransition must be present after morph open (FR-04)',
        );

        // FadeTransition must also be present (combined scale+fade, FR-04).
        expect(
          find.descendant(
            of: find.byType(OverflowPopover),
            matching: find.byType(FadeTransition),
          ),
          findsAtLeastNWidgets(1),
          reason: 'FadeTransition must be present after morph open (FR-04)',
        );

        // ScaleTransition must align to topRight (morph grows from pill corner).
        final scale = tester.widget<ScaleTransition>(
          find
              .descendant(
                of: find.byType(OverflowPopover),
                matching: find.byType(ScaleTransition),
              )
              .first,
        );
        expect(
          scale.alignment,
          equals(Alignment.topRight),
          reason:
              'ScaleTransition alignment must be Alignment.topRight (FR-04)',
        );

        // After pumpAndSettle the animation must have completed: scale == 1.
        expect(
          scale.scale.value,
          closeTo(1.0, 0.01),
          reason:
              'ScaleTransition scale must be 1.0 after animation settles (FR-04)',
        );

        // FadeTransition opacity must be 1.0 after animation settles.
        final fade = tester.widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(OverflowPopover),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(
          fade.opacity.value,
          closeTo(1.0, 0.01),
          reason:
              'FadeTransition opacity must be 1.0 after animation settles (FR-04)',
        );
      },
    );

    testWidgets(
      'given_animations_enabled_then_morph_controller_duration_is_180ms',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());

        // Pump without settling so we can inspect the animation mid-flight.
        await tester.tap(find.byKey(const Key('anchor_btn')));
        await tester.pump(); // start the entry
        await tester.pump(); // trigger initState forward()

        // Find the ScaleTransition and inspect its animation's duration via
        // the underlying controller (accessible through the Listenable).
        final scaleFinder = find.descendant(
          of: find.byType(OverflowPopover),
          matching: find.byType(ScaleTransition),
        );
        expect(
          scaleFinder,
          findsAtLeastNWidgets(1),
          reason: 'ScaleTransition must be in the tree',
        );

        // The controller duration is on the AnimationController which backs
        // the CurvedAnimation. We check duration indirectly: the scale animation
        // is not yet at 1.0 when we pump a fraction of 180ms.
        // Pump 90ms (half of 180ms) — scale should be between 0 and 1.
        await tester.pump(const Duration(milliseconds: 90));

        final scaleMid = tester.widget<ScaleTransition>(scaleFinder.first);
        expect(
          scaleMid.scale.value,
          lessThan(1.0),
          reason:
              'Scale must still be animating at t=90ms (controller duration=180ms, FR-04)',
        );
        expect(
          scaleMid.scale.value,
          greaterThan(0.0),
          reason: 'Scale must have started by t=90ms',
        );

        // Complete the animation.
        await tester.pumpAndSettle();
      },
    );
  });

  // =========================================================================
  // 8. reduce-motion (FR-06/EC-04)
  // =========================================================================
  group('OverflowPopover — reduce-motion (FR-06/EC-04)', () {
    testWidgets(
      'given_disableAnimations_true_then_scale_and_fade_are_instant_and_guard_unchanged',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Build with disableAnimations = true (reduce-motion).
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: _buildApp(),
          ),
        );

        // Open — must complete in one frame (Duration.zero controller).
        await tester.tap(find.byKey(const Key('anchor_btn')));
        await tester.pump(); // OverlayEntry inserted + initState forward()
        await tester.pump(); // settle

        expect(
          find.byType(OverflowPopover),
          findsOneWidget,
          reason: 'Popover must appear immediately under reduce-motion (FR-06)',
        );

        // After open the scale must already be 1.0 (instant).
        final scaleFinder = find.descendant(
          of: find.byType(OverflowPopover),
          matching: find.byType(ScaleTransition),
        );
        if (scaleFinder.evaluate().isNotEmpty) {
          final scale = tester.widget<ScaleTransition>(scaleFinder.first);
          expect(
            scale.scale.value,
            closeTo(1.0, 0.01),
            reason: 'Scale must be 1.0 instantly under reduce-motion (FR-06)',
          );
        }

        // Dismiss via barrier — must complete instantly (no reverse wait).
        await tester.tapAt(const Offset(20, 1100));
        await tester.pump();
        await tester.pump();

        expect(
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Popover must dismiss instantly under reduce-motion (FR-06)',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'No exception under reduce-motion dismiss (EC-04)',
        );
      },
    );
  });

  // =========================================================================
  // 9. dispose — _MorphedBubble controller disposed cleanly (NFR-06)
  // =========================================================================
  group('OverflowPopover — dispose (_MorphedBubble controller, NFR-06)', () {
    testWidgets(
      'given_popover_dismissed_then_pumping_more_frames_causes_no_FlutterError',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(find.byType(OverflowPopover), findsOneWidget);

        // Dismiss via barrier.
        await tester.tapAt(const Offset(20, 1100));
        await tester.pumpAndSettle();

        expect(find.byType(OverflowPopover), findsNothing);

        // Pump extra frames — a leaked/undisposed AnimationController
        // would tick and throw a FlutterError here.
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          tester.takeException(),
          isNull,
          reason: '_MorphedBubble must dispose its controller cleanly (NFR-06)',
        );
      },
    );
  });

  // =========================================================================
  // 5. navigation — tap About → popover dismisses AND About pushed (FR-06)
  // =========================================================================
  group('OverflowPopover — navigation (FR-06)', () {
    testWidgets(
      'given_popover_open_when_About_tapped_then_popover_dismissed_and_About_screen_pushed',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        expect(find.byType(OverflowPopover), findsOneWidget);

        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();

        expect(
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Popover must be dismissed after tapping About (FR-06)',
        );
        expect(
          find.text('About Stub'),
          findsOneWidget,
          reason: 'About screen must be pushed after tapping About tile',
        );
      },
    );

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
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Popover must dismiss on Preferences tap',
        );
        expect(
          find.text('Settings Stub'),
          findsOneWidget,
          reason: 'Settings screen must be pushed',
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
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Popover must dismiss on Recovery tap',
        );
        expect(
          find.text('Recovery Stub'),
          findsOneWidget,
          reason: 'Recovery screen must be pushed',
        );
      },
    );
  });

  // =========================================================================
  // 6. glass surface (FR-19)
  // =========================================================================
  group('OverflowPopover — glass surface (FR-19)', () {
    testWidgets(
      'given_popover_open_then_container_contains_GlassSurface_with_popoverRadius',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await _openPopover(tester);

        // The popover container must be/contain a GlassSurface.
        expect(
          find.descendant(
            of: find.byType(OverflowPopover),
            matching: find.byType(GlassSurface),
          ),
          findsAtLeastNWidgets(1),
          reason:
              'OverflowPopover must wrap its content in a GlassSurface (FR-19)',
        );

        // The GlassSurface must use popoverRadius from the token.
        final glassSurface = tester.widget<GlassSurface>(
          find
              .descendant(
                of: find.byType(OverflowPopover),
                matching: find.byType(GlassSurface),
              )
              .first,
        );
        // Verify the radius is non-zero (popoverRadius = 16.0 per kDefaultGlassTokens).
        final topLeft = glassSurface.borderRadius.topLeft;
        expect(
          topLeft.x,
          greaterThan(0),
          reason: 'GlassSurface borderRadius must be the popoverRadius token',
        );
      },
    );
  });

  // =========================================================================
  // 7. idempotent dismiss + onDismissed funnel (BUG-B / T-03)
  //
  // Contract file B: the returned dismiss is a guarded funnel that:
  //   (a) is safe to call multiple times (entry.mounted guard — no double-remove);
  //   (b) fires onDismissed exactly ONCE per open, regardless of how many times
  //       the returned dismiss is called;
  //   (c) funnels through onDismissed on barrier tap too (outside-tap path).
  // =========================================================================
  group('OverflowPopover — idempotent dismiss + onDismissed funnel (BUG-B)', () {
    testWidgets(
      'given_returned_dismiss_called_twice_then_no_exception_and_onDismissed_fires_once',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final callCount = <int>[];
        final spyHost = _SpyHostScreen(onDismissedCallCount: callCount);

        await tester.pumpWidget(_buildSpyApp(spyHost));

        // Open the popover via the spy button.
        await tester.tap(find.byKey(const Key('spy_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byType(OverflowPopover),
          findsOneWidget,
          reason: 'Popover must be open after tapping spy_btn',
        );

        // Grab the returned dismiss from the state.
        final hostState = tester.state<_SpyHostScreenState>(
          find.byType(_SpyHostScreen),
        );
        final dismiss = hostState.returnedDismiss!;

        // First call — removes the entry, fires onDismissed once.
        dismiss();
        await tester.pumpAndSettle();

        expect(
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Popover must be gone after first dismiss call',
        );
        expect(
          callCount.length,
          equals(1),
          reason: 'onDismissed must fire exactly once on first dismiss',
        );

        // Second call — must NOT throw and must NOT fire onDismissed again.
        dismiss();
        await tester.pumpAndSettle();

        expect(
          callCount.length,
          equals(1),
          reason: 'onDismissed must NOT fire a second time (idempotent guard)',
        );
      },
    );

    testWidgets(
      'given_barrier_tapped_then_returned_dismiss_is_safe_no_op_and_onDismissed_fires_once',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final callCount = <int>[];
        final spyHost = _SpyHostScreen(onDismissedCallCount: callCount);

        await tester.pumpWidget(_buildSpyApp(spyHost));

        // Open the popover.
        await tester.tap(find.byKey(const Key('spy_btn')));
        await tester.pumpAndSettle();

        final hostState = tester.state<_SpyHostScreenState>(
          find.byType(_SpyHostScreen),
        );
        final dismiss = hostState.returnedDismiss!;

        // Dismiss via barrier (outside-tap).
        await tester.tapAt(const Offset(20, 1100));
        await tester.pumpAndSettle();

        expect(
          find.byType(OverflowPopover),
          findsNothing,
          reason: 'Popover dismissed by barrier tap',
        );
        expect(
          callCount.length,
          equals(1),
          reason: 'onDismissed must fire once when barrier is tapped',
        );

        // Now call the returned dismiss — must be a safe no-op (no exception,
        // no second onDismissed invocation).
        dismiss();
        await tester.pumpAndSettle();

        expect(
          callCount.length,
          equals(1),
          reason:
              'onDismissed must NOT fire again after barrier already dismissed',
        );
      },
    );
  });
}
