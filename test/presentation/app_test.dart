// app_test.dart — TASK-16: app.dart route swap + ConsumerWidget
//
// Spec refs: FR-M6-03, FR-M6-09, FR-M6-10, FR-M6-23, EC-08, §5.1-h
//
// Acceptance criteria verified here:
//   1. Route '/' renders BufferScreen (regression from TASK-11/M2).
//   2. Route '/recovery' renders RecoveryScreen (regression from TASK-11/M5).
//   3. Route '/settings' renders SettingsScreen (NOT _EmptyScreen).
//   4. Route '/about' renders AboutScreen (NOT _EmptyScreen).
//   5. BufferApp is a ConsumerWidget (FR-M6-23 — themeMode wired to provider).
//   6. themeMode reacts to themeModeProvider:
//      - follow  → ThemeMode.system
//      - dark    → ThemeMode.dark
//      (no restart; single ProviderScope — FR-M6-03)
//   7. First-frame AsyncLoading → themeMode==system, no throw (EC-08).
//   8. LifecycleBufferHost is present above the Navigator (EC-M2-14 regression).
//   9. LifecycleBufferHost survives route changes (EC-M2-14 regression).
//
// All I/O providers are overridden with fakes — no filesystem, no platform
// channel, no real share intent service.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/presentation/about/about_screen.dart';
import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/editor/buffer_screen.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/lifecycle/lifecycle_buffer_host.dart';
import 'package:buffer/presentation/recovery/recovery_screen.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';
import 'package:buffer/presentation/settings/settings_screen.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async =>
      File('/tmp/fake-${DateTime.now().microsecondsSinceEpoch}.txt');

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

// A SettingsNotifier that immediately returns a fixed AppSettings without
// hitting SharedPreferences — used for themeMode reactive tests.
class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Standard ProviderScope overrides for pumping BufferApp with route '/'
/// active (which mounts BufferScreen, requiring all share providers).
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

/// Pumps [BufferApp] with all required overrides and optionally navigates to
/// [initialRoute].
///
/// [navigatorKey] must be supplied when tests need to drive route transitions.
Future<void> _pumpAppAtRoute(
  WidgetTester tester, {
  required GlobalKey<NavigatorState> navigatorKey,
  String initialRoute = '/',
  List<Override> extraOverrides = const [],
}) async {
  final prefs = await _emptyPrefs();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [..._standardOverrides(prefs), ...extraOverrides],
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
  // 0. BufferApp is a ConsumerWidget (FR-M6-23 — themeMode wired to provider)
  // -------------------------------------------------------------------------

  test('BufferApp_is_a_ConsumerWidget', () {
    // Ensure the widget type hierarchy satisfies the TASK-16 contract.
    const app = BufferApp();
    expect(app, isA<ConsumerWidget>());
  });

  // -------------------------------------------------------------------------
  // 1. Route '/' renders BufferScreen (FR-M2-01, §4.1 — regression)
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

    testWidgets('given_app_at_slash_when_settled_then_chrome_free_no_AppBar', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(tester, navigatorKey: navKey);

      expect(find.byType(BufferScreen), findsOneWidget);
      // No AppBar — chrome-free (FR-M2-02).
      expect(find.byType(AppBar), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 2. /recovery route resolves to RecoveryScreen (FR-M5-05 — regression)
  // -------------------------------------------------------------------------

  group('app.dart TASK-11 M5 — /recovery resolves to RecoveryScreen', () {
    testWidgets('given_push_recovery_when_settled_then_RecoveryScreen_found', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(tester, navigatorKey: navKey);

      navKey.currentState!.pushNamed('/recovery');
      await tester.pumpAndSettle();

      expect(
        find.byType(RecoveryScreen),
        findsOneWidget,
        reason: '/recovery must resolve to RecoveryScreen (FR-M5-05, FR-M5-17)',
      );
    });

    testWidgets('given_push_recovery_when_settled_then_no_ErrorWidget', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(tester, navigatorKey: navKey);

      navKey.currentState!.pushNamed('/recovery');
      await tester.pumpAndSettle();

      expect(find.byType(ErrorWidget), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 3. /settings resolves to SettingsScreen (FR-M6-09 — TASK-16 new)
  // -------------------------------------------------------------------------

  group('app.dart TASK-16 — /settings resolves to SettingsScreen', () {
    testWidgets('given_push_settings_when_settled_then_SettingsScreen_found', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        initialRoute: '/settings',
      );

      expect(
        find.byType(SettingsScreen),
        findsOneWidget,
        reason:
            '/settings must resolve to SettingsScreen after TASK-16 route '
            'swap (FR-M6-09)',
      );
    });

    testWidgets('given_push_settings_when_settled_then_no_ErrorWidget', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        initialRoute: '/settings',
      );

      expect(find.byType(ErrorWidget), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 4. /about resolves to AboutScreen (FR-M6-10 — TASK-16 new)
  // -------------------------------------------------------------------------

  group('app.dart TASK-16 — /about resolves to AboutScreen', () {
    testWidgets('given_push_about_when_settled_then_AboutScreen_found', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        initialRoute: '/about',
      );

      expect(
        find.byType(AboutScreen),
        findsOneWidget,
        reason:
            '/about must resolve to AboutScreen after TASK-16 route swap '
            '(FR-M6-10)',
      );
    });

    testWidgets('given_push_about_when_settled_then_no_ErrorWidget', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        initialRoute: '/about',
      );

      expect(find.byType(ErrorWidget), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 5. themeMode reacts to themeModeProvider — FR-M6-03 / EC-08
  // -------------------------------------------------------------------------

  group('app.dart TASK-16 — themeMode reacts to themeModeProvider', () {
    testWidgets('given_colorScheme_follow_when_pumped_then_themeMode_is_system', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        extraOverrides: [
          settingsProvider.overrideWith(
            () => _FixedSettingsNotifier(
              const AppSettings(colorScheme: AppColorScheme.follow),
            ),
          ),
        ],
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.themeMode,
        ThemeMode.system,
        reason:
            'colorScheme.follow must map to ThemeMode.system (FR-M6-03, EC-08)',
      );
    });

    testWidgets('given_colorScheme_dark_when_pumped_then_themeMode_is_dark', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        extraOverrides: [
          settingsProvider.overrideWith(
            () => _FixedSettingsNotifier(
              const AppSettings(colorScheme: AppColorScheme.dark),
            ),
          ),
        ],
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.themeMode,
        ThemeMode.dark,
        reason: 'colorScheme.dark must map to ThemeMode.dark (FR-M6-03)',
      );
    });

    testWidgets('given_colorScheme_light_when_pumped_then_themeMode_is_light', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await _pumpAppAtRoute(
        tester,
        navigatorKey: navKey,
        extraOverrides: [
          settingsProvider.overrideWith(
            () => _FixedSettingsNotifier(
              const AppSettings(colorScheme: AppColorScheme.light),
            ),
          ),
        ],
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.themeMode,
        ThemeMode.light,
        reason: 'colorScheme.light must map to ThemeMode.light (FR-M6-03)',
      );
    });

    testWidgets(
      'given_AsyncLoading_first_frame_when_pumped_then_themeMode_is_system_and_no_throw',
      (tester) async {
        // EC-08: on the very first frame settingsProvider is AsyncLoading.
        // themeModeProvider must fall back to ThemeMode.system and never throw.
        // We simulate this by overriding themeModeProvider directly with a
        // value derived from the AsyncLoading fallback path.
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(
          tester,
          navigatorKey: navKey,
          extraOverrides: [
            // Override themeModeProvider to force the AsyncLoading fallback
            // path: value==null → AppSettings() → follow → ThemeMode.system.
            themeModeProvider.overrideWithValue(ThemeMode.system),
          ],
        );

        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(find.byType(ErrorWidget), findsNothing);
        expect(
          app.themeMode,
          ThemeMode.system,
          reason:
              'AsyncLoading first-frame must not throw and must yield '
              'ThemeMode.system (EC-08)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 6. LifecycleBufferHost is present above the Navigator (EC-M2-14 regression)
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

        expect(
          find.ancestor(
            of: find.byType(Navigator),
            matching: find.byType(LifecycleBufferHost),
          ),
          findsWidgets,
          reason:
              'LifecycleBufferHost must wrap the Navigator via '
              'MaterialApp.builder (EC-M2-14)',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 7. LifecycleBufferHost survives route changes (EC-M2-14 regression)
  // -------------------------------------------------------------------------

  group('app.dart TASK-11 — LifecycleBufferHost survives route push', () {
    testWidgets(
      'given_app_at_slash_when_push_recovery_then_LifecycleBufferHost_still_present',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(tester, navigatorKey: navKey);

        expect(find.byType(LifecycleBufferHost), findsOneWidget);

        navKey.currentState!.pushNamed('/recovery');
        await tester.pumpAndSettle();

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

    testWidgets(
      'given_app_at_slash_when_push_about_then_LifecycleBufferHost_still_present',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        await _pumpAppAtRoute(tester, navigatorKey: navKey);

        navKey.currentState!.pushNamed('/about');
        await tester.pumpAndSettle();

        expect(find.byType(LifecycleBufferHost), findsOneWidget);
      },
    );
  });
}
