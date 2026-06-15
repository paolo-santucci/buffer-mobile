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
//
// TASK-11 reconciliation: route '/' now renders BufferScreen (not _EmptyScreen).
//   BufferScreen reads initialSharedTextProvider (throws until overridden),
//   shareIntentServiceProvider (connects to platform channel), and
//   recoveryRepositoryProvider (filesystem).  All three are overridden with
//   fakes in every test in this file.  Tests that previously asserted
//   _EmptyScreen at '/' are updated; the three unchanged-route assertions
//   (no crash, no ErrorWidget) remain.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/settings/app_settings.dart';
import 'package:buffer/domain/settings/settings_repository.dart';
import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
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

/// No-op [RecoveryRepository] — required because route '/' now renders
/// BufferScreen which reads saveBufferToRecoveryProvider (TASK-11).
class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) async =>
      File('/tmp/fake-${DateTime.now().microsecondsSinceEpoch}.txt');

  // M5 stubs — not exercised by these boot tests.
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

  // Defect-B sync stub — not exercised by boot tests.
  @override
  File saveSync(String text, {int keep = 10}) =>
      File('/tmp/fake-sync-${DateTime.now().microsecondsSinceEpoch}.txt');
}

/// Null-stream [ShareIntentService] — required because BufferScreen subscribes
/// to sharedTextStream() in initState (TASK-11).
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
// Helpers
// ---------------------------------------------------------------------------

/// Returns a [SharedPreferences] instance backed by empty in-memory storage.
Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

/// Pumps [BufferApp] inside a [ProviderScope] with the required overrides.
///
/// Route '/' now renders BufferScreen (TASK-11), which reads
/// initialSharedTextProvider, shareIntentServiceProvider, and
/// recoveryRepositoryProvider.  All three are overridden here in addition to
/// sharedPreferencesProvider.  The optional [extraOverrides] are appended.
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
        initialSharedTextProvider.overrideWithValue(null),
        shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
        recoveryRepositoryProvider.overrideWithValue(_FakeRecoveryRepository()),
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

          // TASK-11: route '/' now renders BufferScreen, which requires
          // initialSharedTextProvider, shareIntentServiceProvider, and
          // recoveryRepositoryProvider overrides.
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                initialSharedTextProvider.overrideWithValue(null),
                shareIntentServiceProvider.overrideWithValue(
                  _FakeShareIntentService(),
                ),
                recoveryRepositoryProvider.overrideWithValue(
                  _FakeRecoveryRepository(),
                ),
              ],
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

        // TASK-11: route '/' now renders BufferScreen — include share overrides.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              initialSharedTextProvider.overrideWithValue(null),
              shareIntentServiceProvider.overrideWithValue(
                _FakeShareIntentService(),
              ),
              recoveryRepositoryProvider.overrideWithValue(
                _FakeRecoveryRepository(),
              ),
            ],
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
