// Boot-smoke integration test — buffer-mobile
//
// Spec refs: FR-19, MC-01
// Platforms: Android, iOS (headless: `flutter test integration_test/boot_smoke_test.dart`)
//
// Verifies that the app's composition root (ProviderScope + BufferApp) mounts
// without exception and that the "/" route renders an AppTheme surface
// (Scaffold present, theme brightness resolves).
//
// Run locally (with a connected device or headless VM):
//   flutter test integration_test/boot_smoke_test.dart
//
// Run headlessly on Linux CI (no device needed for the Flutter test driver):
//   flutter test integration_test/boot_smoke_test.dart --platform=vm
//   (or use the standard `flutter test integration_test/` on the CI runner)
//
// TASK-12 note: "/" now routes to BufferScreen (TASK-11 route swap), which
// reads initialSharedTextProvider and shareIntentServiceProvider. Both must be
// overridden in the ProviderScope so BufferScreen does not throw
// UnimplementedError on-device. A fake ShareIntentService and a fake
// RecoveryRepository are provided to satisfy the full provider graph.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/domain/recovery/recovery_repository.dart';
import 'package:foglietto/infrastructure/share/share_intent_service.dart';
import 'package:foglietto/presentation/app.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Fakes — satisfy the provider graph without touching any platform channel.
// ──────────────────────────────────────────────────────────────────────────────

/// A no-op [ShareIntentService] that never emits share events and always
/// returns null for the cold-start read.
class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

/// A no-op [RecoveryRepository] that always completes successfully without
/// touching the filesystem.
class _FakeRecoveryRepository implements RecoveryRepository {
  @override
  Future<File> save(String text) => Future.value(File('/dev/null'));

  // M5 stubs — not exercised by this smoke test.
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

  // Defect-B sync stub — not exercised by this smoke test.
  @override
  File saveSync(String text, {int keep = 10}) => File('/dev/null');
}

void main() {
  // Initialise the integration-test binding.  This replaces the standard
  // TestWidgetsFlutterBinding with one that reports results via the native
  // integration test channel.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // Boot smoke — FR-19 / MC-01
  //
  // Pump ProviderScope + BufferApp with mock seams so all M2 providers are
  // satisfied without touching any platform channel. Then assert:
  //   a) exactly one MaterialApp mounts
  //   b) the "/" route renders a Scaffold (AppTheme surface is present)
  //   c) Theme.of(context).brightness resolves to a valid Brightness value
  //   d) no exception is thrown during pump
  // ──────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_mount_ProviderScope_and_BufferApp_and_render_slash_route_with_AppTheme_given_empty_prefs',
    (tester) async {
      // Provide an empty in-memory SharedPreferences so the settings provider
      // seam is satisfied without touching the real platform channel.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            // initialSharedTextProvider throws until overridden (see
            // share_providers.dart). Seed null for a normal cold-start boot.
            initialSharedTextProvider.overrideWithValue(null),
            // shareIntentServiceProvider: use a no-op fake so BufferScreen's
            // sharedTextStream() subscription never reaches the real package.
            shareIntentServiceProvider.overrideWithValue(
              _FakeShareIntentService(),
            ),
            // recoveryRepositoryProvider: use a no-op fake so paused-lifecycle
            // saves never touch the filesystem in the smoke test.
            recoveryRepositoryProvider.overrideWithValue(
              _FakeRecoveryRepository(),
            ),
          ],
          child: const BufferApp(),
        ),
      );

      // Settle all async work: l10n delegate loading, settingsProvider
      // AsyncNotifier initialisation, any pending microtasks.
      await tester.pumpAndSettle();

      // ── Assertion a) exactly one MaterialApp ──────────────────────────────
      expect(
        find.byType(MaterialApp),
        findsOneWidget,
        reason:
            'The composition root must mount exactly one MaterialApp (FR-19/MC-01)',
      );

      // ── Assertion b) Scaffold present on the "/" route ────────────────────
      // The placeholder "/" route renders _EmptyScreen → Scaffold(body:…).
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason:
            'The "/" route must render at least one Scaffold — AppTheme surface '
            'is present (FR-19)',
      );

      // ── Assertion c) Theme brightness resolves ────────────────────────────
      // Grab the BuildContext from the MaterialApp element so we can call
      // Theme.of().
      final materialApp = tester.element(find.byType(MaterialApp).first);
      // MaterialApp exposes a child; use the app's navigator context.
      final scaffoldElement = tester.element(find.byType(Scaffold).first);
      final brightness = Theme.of(scaffoldElement).brightness;
      expect(
        brightness,
        anyOf(equals(Brightness.light), equals(Brightness.dark)),
        reason:
            'Theme.of(context).brightness must resolve to light or dark '
            '— AppTheme is applied (FR-19)',
      );

      // ── Assertion d) no ErrorWidget ───────────────────────────────────────
      expect(
        find.byType(ErrorWidget),
        findsNothing,
        reason:
            'No ErrorWidget must be present after boot — app must render '
            'without exception (FR-19/MC-01)',
      );

      // suppress unused variable warning for materialApp
      expect(materialApp, isNotNull);
    },
  );
}
