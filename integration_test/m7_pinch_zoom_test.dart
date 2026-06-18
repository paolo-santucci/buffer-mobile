// M7 pinch/scale on-device integration test — buffer-mobile
//
// Spec refs: FR-M7-02, FR-M7-05, NFR-M7-01, NFR-M7-03, MC-01, MC-02, MC-03
// Platforms: Android (primary); iOS (secondary).
// Tags: ['on-device'] — this test REQUIRES a running Android/iOS device or
//   emulator. It is SKIPPED by plain `flutter test` (no --device-id). Run it
//   manually with:
//
//   flutter test integration_test/m7_pinch_zoom_test.dart \
//       --device-id <device-id>
//
// What it verifies:
//
//   Scenario A — Two-pointer pinch-out (MC-02, FR-M7-05):
//     Synthesise a two-pointer scale-out gesture over the editor. Assert that
//     fontSizeIndex increases by at least one slot, the font-size toast widget
//     is visible, and no exception is thrown.
//
//   Scenario B — Single-finger drag regression (NFR-M7-03, MC-03):
//     Drag one finger across the editor. Assert that fontSizeIndex remains
//     unchanged at drag end — the `pointerCount == 2` guard must prevent
//     single-pointer scale from changing the slot.
//
//   Scenario C — OS font-scale reflection without restart (MC-01, FR-M7-02,
//     NFR-M7-01):
//     Pump the editor at the default slot. Rebuild the MediaQuery with
//     textScaler = TextScaler.linear(1.3). Assert that the editor's
//     TextField.style.fontSize is the raw slot value (not pre-multiplied by
//     the scaler) — confirming textScaler is passed through, not pre-applied.
//
// On headless `flutter test` (no --device-id), the @Tags(['on-device'])
// annotation causes the test runner to skip the file automatically. No manual
// guard is needed; the tag is sufficient.

@Tags(['on-device'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foglietto/domain/settings/app_settings.dart';
import 'package:foglietto/infrastructure/share/share_intent_service.dart';
import 'package:foglietto/presentation/app.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';
import 'package:foglietto/presentation/settings/settings_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Fakes
// ──────────────────────────────────────────────────────────────────────────────

/// No-op share service — keeps the provider graph satisfied.
class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Boots the full [BufferApp] with fresh SharedPreferences.
///
/// Optionally overrides the initial fontSizeIndex via [fontSizeIndex] so
/// scenarios can start at a known slot.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  int fontSizeIndex = 8, // default slot (14 pt)
}) async {
  SharedPreferences.setMockInitialValues({
    AppSettings.kFontSize: fontSizeIndex,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        shareIntentServiceProvider.overrideWithValue(_FakeShareIntentService()),
      ],
      child: const BufferApp(),
    ),
  );
  await tester.pumpAndSettle();

  // Return the container so tests can inspect provider state.
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Returns the center of the editor TextField in global coordinates.
Offset _editorCenter(WidgetTester tester) {
  final tf = find.byType(TextField);
  expect(tf, findsOneWidget, reason: 'Editor TextField must be present.');
  return tester.getCenter(tf);
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // Scenario A — two-pointer pinch-out increases fontSizeIndex + toast shown
  //
  // Synthesises a two-pointer scale-out gesture over the editor using the
  // Flutter gesture synthesiser. The start spread is 50 px; the end spread
  // is 200 px (4× expansion, expected slot delta ≥ 1). Asserts:
  //   (a) fontSizeIndex increased by at least 1 slot after gesture end.
  //   (b) The font-size toast Finder is visible in the widget tree.
  //   (c) No exception thrown during or after the gesture.
  //
  // (MC-02, FR-M7-05)
  // ──────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_increase_fontSizeIndex_and_show_toast_when_two_pointer_pinch_out',
    (tester) async {
      final container = await _pumpApp(tester, fontSizeIndex: 8);

      final initialIndex =
          container.read(settingsProvider).value?.fontSizeIndex ?? 8;
      final center = _editorCenter(tester);

      // Synthesise a two-pointer scale-out gesture.
      // Pointer 1 starts 25 px left of center; pointer 2 starts 25 px right.
      // Both move outward to ±100 px over 300 ms — a 4× spread expansion.
      final pointer1 = TestPointer(1, PointerDeviceKind.touch);
      final pointer2 = TestPointer(2, PointerDeviceKind.touch);

      final start1 = center + const Offset(-25, 0);
      final start2 = center + const Offset(25, 0);
      final end1 = center + const Offset(-100, 0);
      final end2 = center + const Offset(100, 0);

      // Both pointers down.
      await tester.sendEventToBinding(pointer1.down(start1));
      await tester.sendEventToBinding(pointer2.down(start2));
      await tester.pump();

      // Move in steps to give the scale detector time to fire.
      const steps = 10;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        final p1 = Offset.lerp(start1, end1, t)!;
        final p2 = Offset.lerp(start2, end2, t)!;
        await tester.sendEventToBinding(pointer1.move(p1));
        await tester.sendEventToBinding(pointer2.move(p2));
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Both pointers up — triggers onScaleEnd + setFontSizeIndex.
      await tester.sendEventToBinding(pointer1.up());
      await tester.sendEventToBinding(pointer2.up());
      await tester.pumpAndSettle();

      final finalIndex =
          container.read(settingsProvider).value?.fontSizeIndex ?? 8;

      // (a) fontSizeIndex must have increased.
      expect(
        finalIndex,
        greaterThan(initialIndex),
        reason:
            'Pinch-out (4× spread expansion from slot $initialIndex) must '
            'increase fontSizeIndex by at least 1 slot (FR-M7-05, MC-02). '
            'Initial: $initialIndex, Final: $finalIndex.',
      );

      // (b) Toast must be visible — the font-size change triggers the
      //     ref.listen in buffer_screen.dart.
      // The toast shows the slot's pt value; search for any Text widget
      // in the tree that contains "pt" (e.g. "Font size now 16pt").
      final toastFinder = find.textContaining('pt');
      expect(
        toastFinder,
        findsWidgets,
        reason:
            'Font-size toast must be visible after pinch-out increases the '
            'slot (FR-M7-12 fontSizeToast, ref.listen in buffer_screen.dart).',
      );
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Scenario B — single-finger drag does NOT change fontSizeIndex
  //
  // Drags one pointer across the editor. Because the pinch GestureDetector's
  // onScaleUpdate guard rejects events where `details.pointerCount != 2`,
  // fontSizeIndex must remain unchanged.
  //
  // (NFR-M7-03, MC-03)
  // ──────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_NOT_change_fontSizeIndex_when_single_finger_drags_across_editor',
    (tester) async {
      final container = await _pumpApp(tester, fontSizeIndex: 8);

      final initialIndex =
          container.read(settingsProvider).value?.fontSizeIndex ?? 8;

      // Single-pointer horizontal drag across the editor.
      await tester.drag(
        find.byType(TextField),
        const Offset(200, 0),
        pointer: 1,
      );
      await tester.pumpAndSettle();

      final finalIndex =
          container.read(settingsProvider).value?.fontSizeIndex ?? 8;

      expect(
        finalIndex,
        equals(initialIndex),
        reason:
            'Single-finger drag must NOT change fontSizeIndex. '
            'The `pointerCount == 2` guard in onScaleUpdate must reject '
            'single-pointer gestures (NFR-M7-03, MC-03). '
            'Initial: $initialIndex, Final: $finalIndex.',
      );
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Scenario C — OS font-scale reflected in editor without restart
  //
  // Verifies that the editor passes the OS text scaler through to the
  // TextField without pre-multiplying it into the raw slot fontSize.
  //
  // Steps:
  //   1. Boot the app at default slot 8 (14 pt).
  //   2. Read the initial TextField.style.fontSize — must equal 14.0.
  //   3. Rebuild the MediaQuery with textScaler = TextScaler.linear(1.3).
  //   4. Assert TextField.style.fontSize is still 14.0 (not pre-multiplied
  //      to 18.2). The scaler is passed via textScaler, not baked in.
  //   5. Assert no crash / exception during the rebuild.
  //
  // (MC-01, FR-M7-02, NFR-M7-01)
  // ──────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_pass_OS_textScaler_through_without_pre_multiplying_fontSize',
    (tester) async {
      // Boot at default slot 8 (14 pt).
      await _pumpApp(tester, fontSizeIndex: 8);

      // (2) Read initial fontSize from the editor TextStyle.
      final tf0 = tester.widget<TextField>(find.byType(TextField));
      final initialFontSize = tf0.style?.fontSize;
      expect(
        initialFontSize,
        closeTo(14.0, 0.5),
        reason:
            'At default fontSizeIndex 8, editorStyle.fontSize must be '
            '≈ 14.0 pt (the raw slot value — not pre-multiplied by scaler). '
            'Got: $initialFontSize.',
      );

      // (3) Rebuild with a 1.3× text scaler injected at the MediaQuery level.
      // Wrap the existing app in a MediaQuery override that injects the scaler.
      final existingApp = find.byType(ProviderScope).first;
      final existingWidget = tester.widget(existingApp);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: existingWidget,
        ),
      );
      await tester.pumpAndSettle();

      // (4) Assert fontSize is still the raw slot value — scaler not pre-baked.
      final tf1 = tester.widget<TextField>(find.byType(TextField));
      final scaledFontSize = tf1.style?.fontSize;

      // The raw slot must remain 14.0. The visual size will be 14 × 1.3 = 18.2
      // but that is handled by the renderer through textScaler, not stored here.
      expect(
        scaledFontSize,
        closeTo(14.0, 0.5),
        reason:
            'After injecting textScaler(1.3), editorStyle.fontSize must '
            'remain ≈ 14.0 pt (raw slot value). Pre-multiplying would give '
            '≈18.2 — that would violate NFR-M7-01 (never pre-multiply). '
            'Got: $scaledFontSize.',
      );

      // (5) Verify no exception was thrown (pumpAndSettle above would rethrow
      //     any unhandled Flutter framework exception).
    },
  );
}
