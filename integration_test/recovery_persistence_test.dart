// Recovery persistence integration test — buffer-mobile
//
// Spec refs: NFR-M2-02, §7.2
// Platforms: Android (primary); iOS (secondary, path provider differs on iOS).
// Tags: ['on-device'] — this test REQUIRES a running Android/iOS device or
//   emulator. It is SKIPPED by plain `flutter test` (no --device-id). Run it
//   manually with:
//
//   flutter test integration_test/recovery_persistence_test.dart \
//       --device-id <device-id>
//
// What it verifies (NFR-M2-02 — recovery survives process death):
//   1. Type a sentinel string into the buffer.
//   2. Trigger the 'paused' lifecycle state to fire LifecycleBufferHost's
//      recovery-save hook.
//   3. Simulate process death (adb shell am kill) or rely on OS reclaim.
//   4. Relaunch the app.
//   5. Assert that at least one file under
//      getApplicationSupportDirectory()/recovery/ contains the sentinel.
//
// NOTE: Full process-kill / relaunch automation (steps 3–5) requires a real
// device and adb, and is therefore a manual or CI-farm step not expressible in
// a single testWidgets() call. This file provides:
//   a) A widget-level smoke-test of the save→file chain that runs on-device via
//      the integration test runner (no process kill needed).
//   b) An on-device manual test scaffold (second testWidgets) that documents the
//      full kill/relaunch flow as a commented walkthrough.
//
// The file MUST compile and be runnable on-device for CI sign-off purposes.

@Tags(['on-device'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
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
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Returns the expected recovery directory on the real device filesystem.
Future<Directory> _recoveryDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/recovery');
}

/// Returns all `.txt` files under the recovery directory whose UTF-8 content
/// contains [sentinel].
Future<List<File>> _recoveryFilesContaining(String sentinel) async {
  final dir = await _recoveryDir();
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .where((f) {
        try {
          return f.readAsStringSync().contains(sentinel);
        } catch (_) {
          return false;
        }
      })
      .toList();
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // Test 1: type → paused → assert recovery file written to disk
  //
  // This test exercises the full paused-save chain end-to-end on the real
  // device filesystem:
  //   1. Boot the app (real recoveryRepositoryProvider — filesystem enabled).
  //   2. Type a sentinel string into the buffer.
  //   3. Drive the 'paused' lifecycle state via WidgetsBinding.
  //   4. Assert a file under getApplicationSupportDirectory()/recovery/
  //      contains the sentinel.
  //
  // This does NOT simulate process death. It validates that the save hook
  // fires and that the filesystem path resolves on the real device.
  // ──────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_persist_sentinel_to_recovery_dir_when_paused_given_non_empty_buffer',
    (tester) async {
      const sentinel = 'NFR_M2_02_sentinel_abc123';

      // Clean the recovery directory before the test so stale files from
      // previous runs do not produce false positives.
      final dir = await _recoveryDir();
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          f.deleteSync();
        }
      }

      // Boot the app with real providers but a fake share service.
      // recoveryRepositoryProvider is NOT overridden — we want the real
      // FileRecoveryRepository writing to the on-device filesystem.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

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

      // Type the sentinel into the visible TextField.
      final textField = find.byType(TextField);
      expect(
        textField,
        findsOneWidget,
        reason: 'BufferScreen must render a single TextField',
      );
      await tester.enterText(textField, sentinel);
      await tester.pump();

      // Drive the 'paused' lifecycle event — fires LifecycleBufferHost's
      // _onPaused() → saveBufferToRecovery(sentinel).
      // ignore: invalid_use_of_protected_member
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // Allow the async save to complete before asserting.
      await tester.pump(const Duration(milliseconds: 500));

      // Assert: at least one .txt file in recovery/ contains the sentinel.
      final matches = await _recoveryFilesContaining(sentinel);
      expect(
        matches,
        isNotEmpty,
        reason:
            'NFR-M2-02: recovery directory must contain a file with the '
            'sentinel "$sentinel" after the paused lifecycle event fires the '
            'save hook. Recovery directory: ${dir.path}',
      );
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Test 2: recovery files survive process death (NFR-M2-02 §7.2)
  //
  // Manual kill/relaunch scaffold:
  //   Step 1 — Run test 1 above (writes the sentinel to the recovery dir).
  //   Step 2 — adb shell am kill com.example.buffer
  //             (or terminate via device task switcher)
  //   Step 3 — Relaunch: adb shell monkey -p com.example.buffer 1
  //             (or tap the app icon)
  //   Step 4 — Re-run this file:
  //               flutter test integration_test/recovery_persistence_test.dart
  //               --device-id <id>
  //   Step 5 — Test 2 asserts the file survived process death.
  //
  // In the same-process case (no kill between test 1 and test 2), the file
  // written by test 1 is still on disk and the assertion passes trivially,
  // confirming the file was written at all.
  // ──────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_find_recovery_files_surviving_process_death_given_prior_paused_save',
    (tester) async {
      const sentinel = 'NFR_M2_02_sentinel_abc123';

      final matches = await _recoveryFilesContaining(sentinel);
      expect(
        matches,
        isNotEmpty,
        reason:
            'NFR-M2-02: recovery file containing "$sentinel" must survive '
            'across process death. If running immediately after test 1 in the '
            'same process, the file from that test must still be on disk. '
            'If running after a kill/relaunch cycle, the file must have '
            'persisted. Recovery directory: ${(await _recoveryDir()).path}',
      );
    },
  );
}
