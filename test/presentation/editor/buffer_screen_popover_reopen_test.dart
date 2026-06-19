// BUG-B behavioural reopen widget test — T-04
//
// Contract refs: §3.1 Contract file B — exercises the full onDismissed latch
// funnel through the real BufferScreen host (not the standalone _AnchorHostScreen
// in overflow_popover_test.dart).
//
// Two tests cover the two dismissal paths:
//   Test 1 (outside-tap reopen): open → tap barrier → reopen.
//   Test 2 (menu-tile reopen):   open → tap About tile → pop back → reopen.
//
// Pre-T-03 behaviour: open → dismiss → reopen threw
//   'An OverlayEntry should be removed only once.'
// Post-T-03: both tests must pass GREEN and `tester.takeException()` must be null.
//
// Rules (per plan §T-04):
//   - NO production files modified. Test-only.
//   - The second `…` tap MUST re-show the popover — a no-op test is unacceptable.
//   - `tester.takeException()` is null in both tests.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/domain/recovery/recovery_repository.dart';
import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/infrastructure/share/share_intent_service.dart';
import 'package:foglietto/l10n/app_localizations.dart';
import 'package:foglietto/presentation/editor/buffer_screen.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';
import 'package:foglietto/presentation/shell/overflow_popover.dart';
import 'package:foglietto/presentation/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Test doubles (mirrors buffer_screen_test.dart — minimal stubs)
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async =>
      File('/tmp/popover-reopen-sentinel.txt');

  @override
  File saveSync(String text, {int keep = 10}) =>
      File('/tmp/popover-reopen-sentinel-sync.txt');

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

class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

// ---------------------------------------------------------------------------
// Stub screens for named-route navigation (same pattern as buffer_screen_test.dart).
// ---------------------------------------------------------------------------

class _StubScreen extends StatelessWidget {
  const _StubScreen({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pump helper — drives the REAL BufferScreen inside a MaterialApp with named
// route stubs. Uses 800×1200 so the barrier tap point at (20, 1100) falls well
// outside the popover bubble (which anchors to the top-right pill).
// ---------------------------------------------------------------------------

Future<void> _pumpBufferScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSharedTextProvider.overrideWithValue(null),
        shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
        recoveryRepositoryProvider.overrideWithValue(_FakeRecoveryRepository()),
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            // spellingEnabled=false avoids the Flutter headless spell-check
            // assertion (no native service in the test environment).
            const AppSettings(spellingEnabled: false),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Named-route stubs so Navigator.pushNamed('/about') etc. resolve.
        routes: {
          '/settings': (_) => const _StubScreen(label: 'Settings Stub'),
          '/about': (_) => const _StubScreen(label: 'About Stub'),
          '/recovery': (_) => const _StubScreen(label: 'Recovery Stub'),
        },
        home: const BufferScreen(),
      ),
    ),
  );
  // Allow initState + first frame to execute.
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Helper: locate and tap the … overflow button in the ChromePill.
//
// The button carries Icons.more_horiz (chrome_pill.dart _buildOverflowButton).
// ---------------------------------------------------------------------------

Future<void> _tapOverflowButton(WidgetTester tester) async {
  final overflowButton = find.byIcon(Icons.more_horiz);
  expect(
    overflowButton,
    findsOneWidget,
    reason: '… overflow button (Icons.more_horiz) must be in the tree',
  );
  await tester.tap(overflowButton);
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Test 1 — outside-tap (barrier) reopen
  //
  // Pre-T-03: open → barrier-dismiss → re-tap … threw
  //   'An OverlayEntry should be removed only once.'
  // Post-T-03: open → dismiss → reopen must succeed with no exception.
  // =========================================================================
  testWidgets(
    'BUG-B reopen: open → outside-tap dismiss → re-tap … reopens popover with no exception',
    (tester) async {
      // 800×1200 so barrier-tap (20, 1100) is well outside the top-right popover.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpBufferScreen(tester);

      // --- Step 1: open the popover ---
      await _tapOverflowButton(tester);

      expect(
        find.byType(OverflowPopover),
        findsOneWidget,
        reason: 'OverflowPopover must be visible after tapping …',
      );

      // --- Step 2: dismiss via barrier (outside-tap) ---
      await tester.tapAt(const Offset(20, 1100));
      await tester.pumpAndSettle();

      expect(
        find.byType(OverflowPopover),
        findsNothing,
        reason: 'OverflowPopover must be gone after barrier tap',
      );

      // --- Step 3: reopen by tapping … again ---
      await _tapOverflowButton(tester);

      expect(
        find.byType(OverflowPopover),
        findsOneWidget,
        reason:
            'OverflowPopover must reopen after outside-tap dismiss (BUG-B: '
            'pre-T-03 this threw "OverlayEntry should be removed only once.")',
      );

      // No exception thrown during the entire open→dismiss→reopen sequence.
      expect(
        tester.takeException(),
        isNull,
        reason: 'No exception must be thrown during outside-tap reopen',
      );
    },
  );

  // =========================================================================
  // Test 2 — menu-tile reopen (About tile)
  //
  // Pre-T-03: the host latch (_dismissPopoverRaw) was NOT cleared via
  //   onDismissed on the menu-tile path, so the second … tap called the stale
  //   raw dismiss (already-removed entry) → exception.
  // Post-T-03: tile dismiss funnels through onDismissed → latch cleared →
  //   reopen succeeds.
  // =========================================================================
  testWidgets(
    'BUG-B reopen: open → About tile → back → re-tap … reopens popover with no exception',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpBufferScreen(tester);

      // --- Step 1: open the popover ---
      await _tapOverflowButton(tester);

      expect(
        find.byType(OverflowPopover),
        findsOneWidget,
        reason: 'OverflowPopover must be visible after tapping …',
      );

      // --- Step 2: tap the About tile — popover dismisses and About is pushed ---
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      expect(
        find.byType(OverflowPopover),
        findsNothing,
        reason: 'OverflowPopover must be gone after tapping About',
      );
      expect(
        find.text('About Stub'),
        findsOneWidget,
        reason: 'About stub screen must be pushed',
      );

      // --- Step 3: pop back to BufferScreen ---
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await tester.pumpAndSettle();

      expect(
        find.byType(BufferScreen),
        findsOneWidget,
        reason: 'Must be back on BufferScreen after pop',
      );

      // --- Step 4: reopen by tapping … again ---
      await _tapOverflowButton(tester);

      expect(
        find.byType(OverflowPopover),
        findsOneWidget,
        reason:
            'OverflowPopover must reopen after About-tile dismiss + back nav '
            '(BUG-B: pre-T-03 this threw "OverlayEntry should be removed only once.")',
      );

      // No exception thrown during the entire sequence.
      expect(
        tester.takeException(),
        isNull,
        reason: 'No exception must be thrown during menu-tile reopen',
      );
    },
  );
}
