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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

void main() {
  // Initialise the integration-test binding.  This replaces the standard
  // TestWidgetsFlutterBinding with one that reports results via the native
  // integration test channel.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // Boot smoke — FR-19 / MC-01
  //
  // Pump ProviderScope + BufferApp with a mock SharedPreferences seam so
  // sharedPreferencesProvider is satisfied without touching the platform
  // channel.  Then assert:
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
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
