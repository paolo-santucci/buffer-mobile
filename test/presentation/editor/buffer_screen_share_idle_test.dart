// TASK-09 (SP-20260616): BufferScreen share-wiring + idle-reveal TDD tests.
//
// Spec refs: FR-01, FR-04, FR-05, FR-09, FR-10, FR-11, FR-12, NFR-04,
//            EC-02, EC-05, EC-06, EC-07, EC-08, EC-09, §5.1.6, §4.3, §7.2
//
// Three bundled edits verified here:
//   1. ShareOverlay mount — sibling of ChromeOverlay inside !findState.active.
//   2. enabled + onShareTap wiring via bufferProvider.text (NOT _controller.text).
//   3. Host-owned idle-reveal Timer (1300 ms) with dispose safety.
//
// TDD discipline: these tests are written BEFORE the implementation edits.
// They fail (red) until the three edits land in buffer_screen.dart.
//
// OQ-08: tester.pump(Duration(...)) drives dart:async Timer in test mode.
// OQ-09: _applyingState seam is the existing BufferScreenTestSeam.testSetApplyingState
//         — no new seam needed.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/infrastructure/share/share_target_service.dart';
import 'package:buffer/l10n/app_localizations.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/find/find_provider.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/shell/chrome_reveal_controller.dart';
import 'package:buffer/presentation/shell/share_overlay.dart';
import 'package:buffer/presentation/shell/chrome_overlay.dart';
import 'package:buffer/presentation/theme/app_theme.dart';
import 'package:buffer/domain/settings/app_settings.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Fake [RecoveryRepository] — no I/O.
class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async => File('/tmp/test.txt');
  @override
  File saveSync(String text, {int keep = 10}) => File('/tmp/test.txt');
  @override
  Future<List<RecoveryNote>> list() async => const [];
  @override
  Future<String> read(RecoveryNote note) async => '';
  @override
  Future<void> delete(RecoveryNote note) async {}
  @override
  Future<void> deleteAll() async {}
  @override
  Future<void> trim(int keep) async {}
}

/// Fake [ShareIntentService] with no warm-start events.
class _FakeShareIntentService implements ShareIntentService {
  final StreamController<String> _sc = StreamController<String>.broadcast();
  @override
  Future<String?> initialSharedText() async => null;
  @override
  Stream<String> sharedTextStream() => _sc.stream;
  @override
  void dispose() {
    if (!_sc.isClosed) _sc.close();
  }
}

/// Recording fake [ShareTargetService] — captures calls without hitting platform.
class _FakeShareTargetService implements ShareTargetService {
  final List<String> capturedTexts = [];

  @override
  Future<void> shareText(String text) async {
    capturedTexts.add(text);
  }
}

/// Fake [SettingsNotifier] — returns fixed settings synchronously.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? s])
    : _settings = s ?? const AppSettings(spellingEnabled: false);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

/// Seeded [BufferNotifierImpl] subclass — returns initial text from build().
class _SeededBufferNotifier extends BufferNotifierImpl {
  _SeededBufferNotifier(this._seed);
  final String _seed;

  @override
  BufferState build() => BufferState(text: _seed);
}

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

/// Pumps [BufferScreen] with configurable provider overrides.
///
/// [initialText] — seeds [bufferProvider] to a non-empty string.
/// [fakeShare]   — recording [ShareTargetService] fake.
Future<void> _pump(
  WidgetTester tester, {
  String? initialText,
  _FakeShareTargetService? fakeShare,
  _SeededBufferNotifier? seededNotifier,
}) async {
  final shareTarget = fakeShare ?? _FakeShareTargetService();

  final overrides = <Override>[
    initialSharedTextProvider.overrideWithValue(null),
    shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
    recoveryRepositoryProvider.overrideWithValue(_FakeRecoveryRepository()),
    settingsProvider.overrideWith(
      () => _FakeSettingsNotifier(const AppSettings(spellingEnabled: false)),
    ),
    shareTargetServiceProvider.overrideWithValue(shareTarget),
    if (seededNotifier != null)
      bufferProvider.overrideWith(() => seededNotifier)
    else if (initialText != null)
      bufferProvider.overrideWith(() => _SeededBufferNotifier(initialText)),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BufferScreen(),
      ),
    ),
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Group A — ShareOverlay mount (EC-05, FR-01)
  // -------------------------------------------------------------------------
  group('TASK-09 — ShareOverlay mount', () {
    testWidgets(
      'ShareOverlay is present in tree when find is inactive (FR-01, EC-05)',
      (tester) async {
        await _pump(tester, initialText: 'hello');

        expect(
          find.byType(ShareOverlay),
          findsOneWidget,
          reason: 'ShareOverlay must be mounted when findState.active == false',
        );
      },
    );

    testWidgets(
      'ShareOverlay and ChromeOverlay are both mounted when find is inactive (FR-01)',
      (tester) async {
        await _pump(tester, initialText: 'hello');

        expect(find.byType(ChromeOverlay), findsOneWidget);
        expect(find.byType(ShareOverlay), findsOneWidget);
      },
    );

    testWidgets('ShareOverlay is absent when find is active (EC-05)', (
      tester,
    ) async {
      await _pump(tester, initialText: 'hello');

      // Activate find via findProvider.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BufferScreen)),
      );
      container.read(findProvider.notifier).startSearch(entryOffset: 0);
      await tester.pump();

      expect(
        find.byType(ShareOverlay),
        findsNothing,
        reason: 'ShareOverlay must be hidden when find is active (EC-05)',
      );
    });

    testWidgets(
      'ChromeOverlay is also absent when find is active (EC-05 — existing guard)',
      (tester) async {
        await _pump(tester, initialText: 'hello');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(findProvider.notifier).startSearch(entryOffset: 0);
        await tester.pump();

        expect(find.byType(ChromeOverlay), findsNothing);
        expect(find.byType(ShareOverlay), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group B — share wiring: bufferProvider.text, enabled, onShareTap (FR-04/05)
  //
  // Important seam detail: the controller↔state sync means _controller.text
  // drives bufferProvider.text (via updateText in _onControllerChanged). To
  // get both in sync, tests type text via tester.enterText so the controller
  // and provider both hold the typed value. The key assertion (FR-04) is that
  // onShareTap reads bufferProvider.text (the provider value), not _controller
  // .text directly — they are equal after enterText, but the canonical read
  // path is the provider, not the controller field.
  // -------------------------------------------------------------------------
  group('TASK-09 — share wiring', () {
    testWidgets(
      'tap share → fake records 1 call with text == bufferProvider.text (FR-04)',
      (tester) async {
        final fake = _FakeShareTargetService();
        await _pump(tester, fakeShare: fake);

        // Type text — this syncs _controller.text + bufferProvider.text.
        await tester.enterText(find.byType(TextField).first, 'hello world');
        await tester.pump();

        // enterText triggers onTextChanged → chrome hides. Reveal it.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(chromeVisibilityProvider.notifier).reveal();
        await tester.pump();

        // Verify provider text matches what we typed.
        expect(
          container.read(bufferProvider).text,
          equals('hello world'),
          reason: 'bufferProvider must hold the typed text',
        );

        // Tap the IconButton directly (inside ShareOverlay) to fire onShareTap.
        final iconBtn = find.descendant(
          of: find.byType(ShareOverlay),
          matching: find.byType(IconButton),
        );
        final btn = tester.widget<IconButton>(iconBtn);
        expect(btn.onPressed, isNotNull, reason: 'button must be enabled');

        await tester.tap(iconBtn);
        await tester.pump();

        expect(
          fake.capturedTexts,
          hasLength(1),
          reason: 'shareText must be called exactly once',
        );
        expect(
          fake.capturedTexts.first,
          equals('hello world'),
          reason: 'text must come from bufferProvider.text path',
        );
      },
    );

    testWidgets(
      'empty buffer "" → IconButton.onPressed == null → 0 share calls (FR-05, EC-01)',
      (tester) async {
        final fake = _FakeShareTargetService();
        // Start with no text (default).
        await _pump(tester, fakeShare: fake);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        // Ensure buffer is empty (default is empty).
        expect(container.read(bufferProvider).text, isEmpty);
        await tester.pump();

        // Find the IconButton inside ShareOverlay.
        final iconButton = find.descendant(
          of: find.byType(ShareOverlay),
          matching: find.byType(IconButton),
        );
        final btn = tester.widget<IconButton>(iconButton);
        expect(btn.onPressed, isNull, reason: 'empty buffer → onPressed null');

        await tester.tap(iconButton, warnIfMissed: false);
        await tester.pump();
        expect(fake.capturedTexts, isEmpty);
      },
    );

    testWidgets(
      'whitespace-only "   " → onPressed null → 0 share calls (OQ-03, FR-05)',
      (tester) async {
        final fake = _FakeShareTargetService();
        await _pump(tester, fakeShare: fake);

        // Type whitespace only.
        await tester.enterText(find.byType(TextField).first, '   ');
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        // Verify the provider holds the whitespace.
        expect(container.read(bufferProvider).text, equals('   '));

        final iconButton = find.descendant(
          of: find.byType(ShareOverlay),
          matching: find.byType(IconButton),
        );
        final btn = tester.widget<IconButton>(iconButton);
        expect(
          btn.onPressed,
          isNull,
          reason: 'whitespace-only → trim.isEmpty → onPressed null (OQ-03)',
        );

        await tester.tap(iconButton, warnIfMissed: false);
        await tester.pump();
        expect(fake.capturedTexts, isEmpty);
      },
    );

    testWidgets(
      'reactive enable: empty → enabled false; type "x" → enabled true (EC-02)',
      (tester) async {
        await _pump(tester);

        // Initially empty → disabled.
        final iconBtnFinder = find.descendant(
          of: find.byType(ShareOverlay),
          matching: find.byType(IconButton),
        );
        expect(
          tester.widget<IconButton>(iconBtnFinder).onPressed,
          isNull,
          reason: 'empty text → onPressed null',
        );

        // Type something to enable the button.
        await tester.enterText(find.byType(TextField).first, 'x');
        await tester.pump();

        expect(
          tester.widget<IconButton>(iconBtnFinder).onPressed,
          isNotNull,
          reason: '"x" → onPressed non-null (EC-02)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group C — lockstep chrome visibility (FR-02)
  // -------------------------------------------------------------------------
  group('TASK-09 — lockstep chrome/share visibility', () {
    testWidgets(
      'chromeVisibilityProvider false → both overlays opacity 0.0 (FR-02)',
      (tester) async {
        await _pump(tester, initialText: 'hello');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        await tester.pump();

        // Both overlays wrapped in AnimatedOpacity with opacity 0.0.
        final opacities = tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .toList();

        // Find the one that belongs to ShareOverlay.
        final shareAO = tester
            .widgetList<AnimatedOpacity>(
              find.descendant(
                of: find.byType(ShareOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .first;

        expect(shareAO.opacity, equals(0.0));
        expect(opacities.any((ao) => ao.opacity == 0.0), isTrue);
      },
    );

    testWidgets(
      'chromeVisibilityProvider true → ShareOverlay AnimatedOpacity 1.0 (FR-02)',
      (tester) async {
        await _pump(tester, initialText: 'hello');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(chromeVisibilityProvider.notifier).reveal();
        await tester.pump();

        final shareAO = tester
            .widgetList<AnimatedOpacity>(
              find.descendant(
                of: find.byType(ShareOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .first;

        expect(shareAO.opacity, equals(1.0));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group D — idle-reveal timer (FR-09, FR-10, FR-11, NFR-04)
  // -------------------------------------------------------------------------
  group('TASK-09 — idle-reveal timer', () {
    testWidgets(
      'typing → pump 1300ms → chromeVisibilityProvider becomes true (FR-09/10)',
      (tester) async {
        await _pump(tester, initialText: '');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );

        // Ensure chrome is hidden (typing hides it).
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        await tester.pump();
        expect(container.read(chromeVisibilityProvider), isFalse);

        // Simulate user typing via enterText.
        await tester.enterText(find.byType(TextField).first, 'a');
        await tester.pump();

        // Idle-reveal timer should NOT have fired yet.
        expect(container.read(chromeVisibilityProvider), isFalse);

        // Advance 1300ms — timer fires.
        await tester.pump(const Duration(milliseconds: 1300));
        expect(
          container.read(chromeVisibilityProvider),
          isTrue,
          reason: 'idle timer (1300ms) must reveal chrome (FR-09)',
        );
      },
    );

    testWidgets(
      'pump only 1299ms → chrome still false (NFR-04 — must not fire early)',
      (tester) async {
        await _pump(tester, initialText: '');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        await tester.pump();

        await tester.enterText(find.byType(TextField).first, 'a');
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 1299));
        expect(
          container.read(chromeVisibilityProvider),
          isFalse,
          reason: '1299ms is before the 1300ms threshold',
        );
      },
    );

    testWidgets(
      'debounce: 5 keystrokes 200ms apart, pump 1000ms → still false (FR-09, EC-06)',
      (tester) async {
        await _pump(tester, initialText: '');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        await tester.pump();

        // Type 5 characters, 200ms apart.
        for (int i = 0; i < 5; i++) {
          await tester.enterText(find.byType(TextField).first, 'a' * (i + 1));
          await tester.pump(const Duration(milliseconds: 200));
        }
        // Last keystroke was at t=1000ms. Pump 1000ms more → t=2000ms total,
        // but only 1000ms since the LAST keystroke — still < 1300ms.
        await tester.pump(const Duration(milliseconds: 1000));
        expect(
          container.read(chromeVisibilityProvider),
          isFalse,
          reason: 'debounce: timer resets on each keystroke (EC-06)',
        );
      },
    );

    testWidgets(
      '_applyingState active → controller change does NOT restart idle timer (EC-07)',
      (tester) async {
        await _pump(tester, initialText: '');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(BufferScreen)),
        );
        container.read(chromeVisibilityProvider.notifier).onTextChanged();
        await tester.pump();

        // Force _applyingState = true via the test seam.
        final seam =
            tester.state(find.byType(BufferScreen)) as BufferScreenTestSeam;
        seam.testSetApplyingState(true);

        // Trigger a text change (simulates a programmatic rewrite).
        // Using enterText while _applyingState is true — the guard must block
        // the idle timer from starting.
        await tester.enterText(find.byType(TextField).first, 'programmatic');
        await tester.pump();

        // Clear the guard.
        seam.testSetApplyingState(false);

        // Pump 1300ms — if the timer was incorrectly started, chrome would reveal.
        await tester.pump(const Duration(milliseconds: 1300));
        expect(
          container.read(chromeVisibilityProvider),
          isFalse,
          reason:
              'programmatic guard must prevent idle timer from starting (EC-07)',
        );
      },
    );

    testWidgets('dispose with pending timer → no exception after unmount (EC-08)', (
      tester,
    ) async {
      // Use a separate, long-lived container to observe chrome state
      // across widget unmount.
      final outerContainer = ProviderContainer();
      addTearDown(outerContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: outerContainer,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProviderScope(
              overrides: [
                initialSharedTextProvider.overrideWithValue(null),
                shareIntentServiceProvider.overrideWithValue(
                  _FakeShareIntentService(),
                ),
                recoveryRepositoryProvider.overrideWithValue(
                  _FakeRecoveryRepository(),
                ),
                settingsProvider.overrideWith(
                  () => _FakeSettingsNotifier(
                    const AppSettings(spellingEnabled: false),
                  ),
                ),
                shareTargetServiceProvider.overrideWithValue(
                  _FakeShareTargetService(),
                ),
              ],
              child: const BufferScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Get the inner container for the BufferScreen scope.
      final innerContainer = ProviderScope.containerOf(
        tester.element(find.byType(BufferScreen)),
      );

      // Hide chrome, then type to start the idle timer.
      innerContainer.read(chromeVisibilityProvider.notifier).onTextChanged();
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.pump();
      // Timer is now running (1300ms pending).

      // Replace the widget tree — BufferScreen.dispose() is called.
      // This must cancel the pending timer.
      await tester.pumpWidget(MaterialApp(home: const SizedBox()));
      await tester.pump();

      // Advance past the timer duration.
      // If dispose() did NOT cancel the timer, a call to ref.read(...).reveal()
      // on a disposed widget would throw — which would surface as a test error.
      await tester.pump(const Duration(milliseconds: 1500));

      // If we reach here with no exception, the timer was properly cancelled.
    });
  });
}
