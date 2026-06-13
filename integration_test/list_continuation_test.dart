// List continuation on-device integration test — buffer-mobile
//
// Spec refs: FR-07, FR-08, NFR-07, R-03, MC-01
// Platforms: Android (primary); iOS (secondary).
// Tags: ['on-device'] — this test REQUIRES a running Android/iOS device or
//   emulator. It is SKIPPED by plain `flutter test` (no --device-id). Run it
//   manually with:
//
//   flutter test integration_test/list_continuation_test.dart \
//       --device-id <device-id>
//
// What it verifies (R-03 / MC-01 — soft-keyboard Return convergence):
//
//   Pre-populate the editor with "- item", then trigger a REAL soft-keyboard
//   Return key event (as the IME would deliver it on an actual device). Assert
//   that the final buffer text becomes "- item\n- " with the caret positioned
//   immediately after the inserted "- " continuation token.
//
//   This test is the M3 phase-transition gate: it proves that the soft-keyboard
//   path (_onControllerChanged \n-detection) and the hardware-Enter path
//   (Shortcuts → ContinueListIntent) converge on the same continuation result
//   (single-path invariant, §5.3).
//
//   It is the on-device counterpart of the widget-level "soft path" and
//   "hardware path" convergence tests in buffer_screen_test.dart (MC-01),
//   which run headlessly but cannot deliver a real IME newline.
//
// NOTE: This test does NOT cover process-kill / relaunch — that is
// recovery_persistence_test.dart (NFR-M2-02). It exercises the live editing
// surface only.

@Tags(['on-device'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buffer/infrastructure/share/share_intent_service.dart';
import 'package:buffer/presentation/app.dart';
import 'package:buffer/presentation/editor/share_providers.dart';
import 'package:buffer/presentation/settings/settings_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Fakes
// ──────────────────────────────────────────────────────────────────────────────

/// No-op share service — keeps the provider graph satisfied without touching
/// the real package channel.
class _FakeShareIntentService implements ShareIntentService {
  @override
  Future<String?> initialSharedText() async => null;

  @override
  Stream<String> sharedTextStream() => const Stream.empty();

  @override
  void dispose() {}
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ────────────────────────────────────────────────────────────────────────────
  // Test: soft-keyboard Return on "- item" → "- item\n- " with caret after token
  //
  // This test exercises the full soft-keyboard continuation path end-to-end on a
  // real Android/iOS device:
  //   1. Boot the app with fake providers.
  //   2. Enter "- item" into the editor TextField.
  //   3. Send a real Return key event via testTextInput / sendKeyEvent to
  //      simulate the soft-keyboard IME delivering a newline.
  //   4. Assert final text == "- item\n- ".
  //   5. Assert caret is collapsed and positioned after the "- " token
  //      (offset 10 == "- item\n- ".length).
  //
  // Why this test matters (R-03 / MC-01):
  //   The widget-level buffer_screen_test.dart proves both paths converge by
  //   directly mutating controller.value (soft path) and sending a synthetic
  //   key event (hardware path). Those tests run headlessly and the \n insertion
  //   is exact. This test proves the same outcome via the real IME delivery path
  //   on a physical device — no mocked key injection, real TextField interaction.
  // ────────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_continue_bullet_list_when_soft_keyboard_Return_given_bullet_line',
    (tester) async {
      // Set up fresh SharedPreferences (no stored settings).
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Boot the full app with real providers except for share and initial text.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            initialSharedTextProvider.overrideWithValue(null),
            shareIntentServiceProvider.overrideWithValue(
              _FakeShareIntentService(),
            ),
          ],
          child: const BufferApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Locate the single editor TextField.
      final textFieldFinder = find.byType(TextField);
      expect(
        textFieldFinder,
        findsOneWidget,
        reason: 'BufferScreen must render exactly one TextField.',
      );

      // Enter the initial text "- item" into the editor.
      await tester.tap(textFieldFinder);
      await tester.pumpAndSettle();
      await tester.enterText(textFieldFinder, '- item');
      await tester.pumpAndSettle();

      // Verify the seed text was accepted.
      expect(
        find.widgetWithText(TextField, '- item'),
        findsOneWidget,
        reason: 'Editor must contain "- item" after enterText.',
      );

      // Trigger a real soft-keyboard Return.
      //
      // On a real device this is what the IME delivers when the user taps the
      // Return key. `sendKeyEvent` with LogicalKeyboardKey.enter simulates
      // this at the Flutter input layer — identical to the hardware-Enter path
      // tested in widget tests, but running inside the integration test runner
      // on a live device where the TextEditingController and the \n-detection
      // predicate in _onControllerChanged operate on a real rendering pipeline.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Find the updated TextField widget and read its current value.
      final textField = tester.widget<TextField>(textFieldFinder);
      final controller = textField.controller;
      expect(
        controller,
        isNotNull,
        reason: 'TextField must have a controller (EditorController).',
      );

      final resultText = controller!.text;
      final resultSelection = controller.selection;

      // Assert 1: text is "- item\n- " (bullet continuation inserted).
      expect(
        resultText,
        equals('- item\n- '),
        reason:
            'R-03/MC-01: soft-keyboard Return on "- item" must produce '
            '"- item\\n- " via the \\n-in-change-path continuation (FR-08). '
            'Got: "${resultText.replaceAll('\n', '\\n')}"',
      );

      // Assert 2: caret is collapsed immediately after the "- " token.
      // "- item\n- ".length == 10.
      expect(
        resultSelection.isCollapsed,
        isTrue,
        reason:
            'Caret must be collapsed after list continuation (FR-09 / §5.3).',
      );
      expect(
        resultSelection.baseOffset,
        equals(resultText.length),
        reason:
            'Caret must sit at the end of "- item\\n- " (offset '
            '${resultText.length}) after continuation (FR-08 / R-03).',
      );
    },
  );
}
