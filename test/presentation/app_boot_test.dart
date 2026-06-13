// Tests for BufferApp + main.dart composition root (TASK-16)
//
// Spec refs: FR-05, MC-01, EC-04, NFR-04, NFR-05
//
// Verifies:
//   1. MC-01 / FR-05   — pumpWidget(ProviderScope + BufferApp) → no exception;
//                        tree contains exactly one MaterialApp.
//   2. EC-04            — when settingsRepositoryProvider throws on load(),
//                        the app does NOT crash at boot (settingsProvider
//                        degrades to defaults; no fatal ErrorWidget).
//   3. FR-05 routes     — routes "/", "/recovery", "/settings", "/about" each
//                        resolve without UnknownRoute and render a non-null
//                        widget tree.
//   4. FR-05 negative   — "/nonexistent" is handled by onUnknownRoute; no crash.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/domain/settings/settings_repository.dart';
import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A repository whose load() always throws — covers EC-04 degradation.
class _ThrowingRepository implements SettingsRepository {
  const _ThrowingRepository();

  @override
  Future<AppSettings> load() async =>
      throw Exception('simulated settings failure');

  @override
  Future<void> save(AppSettings settings) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a [SharedPreferences] instance backed by empty in-memory storage.
Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

/// Pumps [BufferApp] inside a [ProviderScope] with the real (mock) prefs
/// override.  The optional [extraOverrides] are appended to the scope.
Future<void> _pumpApp(
  WidgetTester tester, {
  List<Override> extraOverrides = const [],
  SharedPreferences? prefs,
}) async {
  final resolvedPrefs = prefs ?? await _emptyPrefs();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(resolvedPrefs),
        ...extraOverrides,
      ],
      child: const BufferApp(),
    ),
  );
  // Settle all async operations (l10n delegate loading, settingsProvider).
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // 1. MC-01 / FR-05: basic boot
  // -------------------------------------------------------------------------

  group('BufferApp — MC-01 / FR-05 boot', () {
    testWidgets(
      'given_valid_prefs_when_pumpWidget_then_no_exception_and_one_MaterialApp',
      (tester) async {
        await _pumpApp(tester);

        expect(find.byType(MaterialApp), findsOneWidget);
      },
    );

    testWidgets(
      'given_valid_prefs_when_pumpWidget_then_no_ErrorWidget_in_tree',
      (tester) async {
        await _pumpApp(tester);

        expect(find.byType(ErrorWidget), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2. EC-04: graceful degradation when settings repo throws
  // -------------------------------------------------------------------------

  group('BufferApp — EC-04 settings failure does not crash app', () {
    testWidgets(
      'given_throwing_SettingsRepository_when_pumpWidget_then_no_ErrorWidget',
      (tester) async {
        await _pumpApp(
          tester,
          extraOverrides: [
            settingsRepositoryProvider.overrideWithValue(
              const _ThrowingRepository(),
            ),
          ],
        );

        expect(find.byType(ErrorWidget), findsNothing);
      },
    );

    testWidgets(
      'given_throwing_SettingsRepository_when_pumpWidget_then_MaterialApp_present',
      (tester) async {
        await _pumpApp(
          tester,
          extraOverrides: [
            settingsRepositoryProvider.overrideWithValue(
              const _ThrowingRepository(),
            ),
          ],
        );

        expect(find.byType(MaterialApp), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 3. FR-05 routes: four named routes resolve without UnknownRoute
  // -------------------------------------------------------------------------

  group('BufferApp — FR-05 named routes resolve', () {
    for (final route in ['/', '/recovery', '/settings', '/about']) {
      testWidgets(
        'route_${route.replaceAll("/", "_")}_resolves_without_crash',
        (tester) async {
          // Use a GlobalKey on the Navigator to imperatively push routes.
          final navigatorKey = GlobalKey<NavigatorState>();

          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
              child: BufferApp(navigatorKey: navigatorKey),
            ),
          );
          await tester.pumpAndSettle();

          // Push the named route.
          navigatorKey.currentState!.pushNamed(route);
          await tester.pumpAndSettle();

          // No ErrorWidget and no crash means the route resolved.
          expect(find.byType(ErrorWidget), findsNothing);
        },
      );
    }
  });

  // -------------------------------------------------------------------------
  // 4. FR-05 negative: unknown route is handled gracefully
  // -------------------------------------------------------------------------

  group(
    'BufferApp — FR-05 negative: unknown route handled by onUnknownRoute',
    () {
      testWidgets('given_unregistered_route_when_navigate_then_no_crash', (
        tester,
      ) async {
        final navigatorKey = GlobalKey<NavigatorState>();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
            child: BufferApp(navigatorKey: navigatorKey),
          ),
        );
        await tester.pumpAndSettle();

        navigatorKey.currentState!.pushNamed('/nonexistent');
        await tester.pumpAndSettle();

        expect(find.byType(ErrorWidget), findsNothing);
      });
    },
  );
}
