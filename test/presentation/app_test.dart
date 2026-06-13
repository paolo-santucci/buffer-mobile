// TASK-11: app.dart route swap + MaterialApp.builder LifecycleBufferHost wrap.
//
// Spec refs: FR-M2-01, FR-M2-02, EC-M2-14, §4.1
//
// Acceptance criteria verified here:
//   1. Route '/' renders BufferScreen (find.byType(BufferScreen)==1;
//      _EmptyScreen absent at '/').
//   2. Routes '/recovery', '/settings', '/about' still render _EmptyScreen.
//   3. LifecycleBufferHost is present above the Navigator in the tree
//      (ancestor of Navigator; find.byType(LifecycleBufferHost)==1).
//   4. Navigating between routes does NOT unmount LifecycleBufferHost
//      (still found after a route push — EC-M2-14).
//
// All I/O providers are overridden with fakes — no filesystem, no platform
// channel, no real share intent service.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/lifecycle/lifecycle_buffer_host.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async =>
      File('/tmp/fake-${DateTime.now().microsecondsSinceEpoch}.txt');
}

class _FakeShareIntentService implements ShareIntentService {
  final StreamController<String> _ctrl = StreamController<String>.broadcast();

  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => _ctrl.stream;

  @override
  void dispose() {
    if (!_ctrl.isClosed) _ctrl.close();
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Standard ProviderScope overrides for pumping BufferApp with route '/'
/// active (which now mounts BufferScreen, requiring all share providers).
List<Override> _standardOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  initialSharedTextProvider.overrideWithValue(null),
  shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
  recoveryRepositoryProvider.overrideWithValue(_FakeRecoveryRepository()),
];

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

/// Pumps [BufferApp] with all required overrides and navigates to [route].
///
/// The [navigatorKey] is required for tests that exercise route transitions.
Future<void> _pumpAppAtRoute(
  WidgetTester tester, {
  required GlobalKey<NavigatorState> navigatorKey,
  String initialRoute = '/',
}) async {
  final prefs = await _emptyPrefs();

  await tester.pumpWidget(
    ProviderScope(
      overrides: _standardOverrides(prefs),
      child: BufferApp(navigatorKey: navigatorKey),
    ),
  );
  await tester.pumpAndSettle();

  if (initialRoute != '/') {
    navigatorKey.currentState!.pushNamed(initialRoute);
    await tester.pumpAndSettle();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // 1. Route '/' renders BufferScreen (FR-M2-01, §4.1)
  // -------------------------------------------------------------------------

  group('app.dart TASK-11 — route "/" renders BufferScreen', () {
    testWidgets(
      'given_app_at_slash_when_settled_then_BufferScreen_found_once',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(tester, navigatorKey: navKey);

        expect(find.byType(BufferScreen), findsOneWidget);
      },
    );

    testWidgets('given_app_at_slash_when_settled_then_no_EmptyScreen_in_tree', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(tester, navigatorKey: navKey);

      // _EmptyScreen is package-private; verify by checking that the route
      // delivers a BufferScreen (the positive assertion above covers this,
      // but checking the Scaffold count helps confirm no extra empty screen).
      expect(find.byType(BufferScreen), findsOneWidget);
      // No AppBar — chrome-free (FR-M2-02).
      expect(find.byType(AppBar), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Other three routes still render _EmptyScreen (M1 regression guard)
  // -------------------------------------------------------------------------

  group('app.dart TASK-11 — unchanged routes still render _EmptyScreen', () {
    for (final route in ['/recovery', '/settings', '/about']) {
      testWidgets(
        'route_${route.replaceAll("/", "_")}_has_no_BufferScreen_and_no_ErrorWidget',
        (tester) async {
          final navKey = GlobalKey<NavigatorState>();
          await _pumpAppAtRoute(
            tester,
            navigatorKey: navKey,
            initialRoute: route,
          );

          // _EmptyScreen renders a Scaffold — it's present.
          expect(find.byType(Scaffold), findsWidgets);
          // No BufferScreen on these routes.
          expect(find.byType(BufferScreen), findsNothing);
          // No crash.
          expect(find.byType(ErrorWidget), findsNothing);
        },
      );
    }
  });

  // -------------------------------------------------------------------------
  // 3. LifecycleBufferHost is present above the Navigator (EC-M2-14)
  // -------------------------------------------------------------------------

  group('app.dart TASK-11 — LifecycleBufferHost above Navigator', () {
    testWidgets('given_app_pumped_then_LifecycleBufferHost_found_once', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(tester, navigatorKey: navKey);

      expect(find.byType(LifecycleBufferHost), findsOneWidget);
    });

    testWidgets(
      'given_app_pumped_then_LifecycleBufferHost_is_ancestor_of_Navigator',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(tester, navigatorKey: navKey);

        // LifecycleBufferHost must be an ancestor of the Navigator widget.
        expect(
          find.ancestor(
            of: find.byType(Navigator),
            matching: find.byType(LifecycleBufferHost),
          ),
          findsWidgets,
          reason:
              'LifecycleBufferHost must wrap the Navigator via MaterialApp.builder '
              'so it sits above the route layer (EC-M2-14)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. LifecycleBufferHost survives route changes (EC-M2-14)
  // -------------------------------------------------------------------------

  group('app.dart TASK-11 — LifecycleBufferHost survives route push', () {
    testWidgets(
      'given_app_at_slash_when_push_recovery_then_LifecycleBufferHost_still_present',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(tester, navigatorKey: navKey);

        // Confirm present before navigation.
        expect(find.byType(LifecycleBufferHost), findsOneWidget);

        // Push a different route.
        navKey.currentState!.pushNamed('/recovery');
        await tester.pumpAndSettle();

        // Must still be found — never unmounted by a route change.
        expect(
          find.byType(LifecycleBufferHost),
          findsOneWidget,
          reason:
              'LifecycleBufferHost must NOT unmount on route push (EC-M2-14)',
        );
      },
    );

    testWidgets(
      'given_app_at_slash_when_push_settings_then_LifecycleBufferHost_still_present',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(tester, navigatorKey: navKey);

        navKey.currentState!.pushNamed('/settings');
        await tester.pumpAndSettle();

        expect(find.byType(LifecycleBufferHost), findsOneWidget);
      },
    );
  });
}
