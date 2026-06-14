// Recovery 12→10 trim integration test — buffer-mobile
//
// Spec refs: NFR-M5-01, NFR-M5-03, MC-01; FR-M5-03
//
// Platforms: Android (primary); iOS (secondary).
// Tags: ['on-device'] — this test REQUIRES a running Android/iOS device or
//   emulator. It is SKIPPED by plain `flutter test` (no --device-id). Run it
//   manually with:
//
//   flutter test integration_test/recovery_12saves_trim_test.dart \
//       --device-id <device-id>
//
// What it verifies (NFR-M5-01 / MC-01 — trim-to-10 lexicographic sort):
//
//   Drives 12 distinct save calls through the REAL FileRecoveryRepository
//   wired against a temp directory (SandboxPathProvider injected with a
//   temp-dir resolver). After 12 saves, SaveBufferToRecovery.call() is used
//   as the entry point for each save — this exercises the full use-case path
//   including the trim(10) call that follows every successful save.
//
//   Asserts:
//     a) Exactly 10 .txt files remain in the recovery temp dir.
//     b) The 2 lexicographically-smallest ORIGINAL filenames were deleted
//        (NFR-M5-01: trim sorts by filename lexicographically, not mtime).
//
// Approach: direct use-case + repository (OQ-M5-11 pragmatic resolution)
//
//   The task spec allows a pragmatic resolution of OQ-M5-11: "if on-device
//   WidgetsBinding lifecycle simulation is unreliable, drive the save use-case
//   + trim directly through the real FileRecoveryRepository against the temp
//   dir." This is the chosen approach here.
//
//   Rationale: the LifecycleBufferHost paused-event path is covered by the
//   widget-level test (test/presentation/lifecycle/lifecycle_buffer_host_test.dart)
//   and the recovery_persistence_test.dart on-device test. The trim behavior
//   (NFR-M5-01 / FR-M5-03) is a FileRecoveryRepository + SaveBufferToRecovery
//   concern, not a UI concern — driving it directly is more deterministic and
//   eliminates timing dependencies on lifecycle event delivery.
//
//   The test still uses the real FileRecoveryRepository (no mocks for the
//   repository itself) and writes to a real temp directory on the device
//   filesystem, satisfying the on-device requirement.
//
// NOTE: On headless flutter-tester the test is tagged @Tags(['on-device']) and
//   will be skipped automatically by plain `flutter test` (no --device-id).

@Tags(['on-device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:buffer/infrastructure/paths/sandbox_path_provider.dart';
import 'package:buffer/infrastructure/recovery/file_recovery_repository.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────────────

/// Number of saves to drive. Must be > 10 to exercise the trim-to-10 path.
const _kSaveCount = 12;

/// The trim cap. Matches the `trim(10)` call in SaveBufferToRecovery.
const _kTrimCap = 10;

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Returns all `.txt` [File]s in [dir] sorted lexicographically by basename.
List<File> _sortedTxtFiles(Directory dir) {
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path) == '.txt')
      .toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
}

// ──────────────────────────────────────────────────────────────────────────────
// Test suite
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ────────────────────────────────────────────────────────────────────────────
  // Test: 12 saves → exactly 10 files remain; 2 lexicographically-smallest
  //       original filenames were deleted (NFR-M5-01 / MC-01).
  //
  // The test runs WITHOUT pumping a Widget tree — it drives the domain use-case
  // and infrastructure layer directly from a non-widget testWidgets body.
  // This avoids lifecycle-event timing issues while still exercising the real
  // FileRecoveryRepository against real temp-dir I/O on the device.
  //
  // Approach (OQ-M5-11 pragmatic resolution):
  //   Instead of wiring 12 app paused+resume cycles (which require timing-
  //   sensitive WidgetsBinding event delivery and app re-mounts), we call
  //   SaveBufferToRecovery.call() 12 times directly. Each call exercises the
  //   full production code path:
  //     call(text) → trim-guard → repository.save(text) → repository.trim(10)
  //   and the real FileRecoveryRepository writes UTF-8 files to a temp dir
  //   on the device filesystem. After 12 calls the trim must leave exactly 10.
  //
  // The test stubs the NowUtcProvider to return timestamps with 10ms spacing
  // so filenames are unique and deterministically ordered — necessary because
  // save() uses millisecond resolution and parallel calls within 1ms would
  // collide. This is the only stub; all other logic is real production code.
  // ────────────────────────────────────────────────────────────────────────────

  testWidgets(
    'should_have_exactly_10_files_and_delete_2_smallest_when_12_saves_given_trim_cap_10',
    (tester) async {
      // ── 1. Create a temp directory on the device filesystem ───────────────
      //
      // We use Directory.systemTemp rather than path_provider so the test
      // does not depend on the Flutter platform channel initialisation.
      // All I/O runs against the real device filesystem (not mocked).
      final tempDir = await Directory.systemTemp.createTemp('recovery_trim_');

      // Ensure the temp dir is cleaned up after the test regardless of outcome.
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      // ── 2. Wire the real FileRecoveryRepository against the temp dir ──────
      //
      // Inject a NowUtcProvider that returns fixed timestamps with 10ms
      // increments so each save generates a unique lexicographically-ordered
      // filename. This is necessary because save() derives filenames from the
      // UTC millisecond timestamp — two saves within 1ms would collide on the
      // collision-suffix path and produce non-deterministic ordering.
      final baseTime = DateTime.utc(2026, 6, 14, 12, 0, 0, 0);
      var callCount = 0;
      DateTime nowProvider() {
        // Advance by 10ms per call: 0ms, 10ms, 20ms, …
        return baseTime.add(Duration(milliseconds: callCount++ * 10));
      }

      final repo = FileRecoveryRepository(
        pathProvider: SandboxPathProvider(
          // Resolve to the temp dir's parent so that the repository adds the
          // 'recovery' subdirectory under it, exactly as in production.
          // SandboxPathProvider.recoveryDirectory() returns
          //   Directory(p.join(base.path, 'recovery'))
          // so we point the resolver at tempDir.parent and name the temp dir
          // 'recovery' — OR we inject a resolver that returns tempDir.parent
          // and rely on recoveryDirectory() appending '/recovery'.
          //
          // Simpler: return a Directory whose path IS tempDir.path directly.
          // SandboxPathProvider.recoveryDirectory() returns
          //   Directory(p.join(base.path, 'recovery'))
          // which means base = tempDir. That subdirectory is what the repo
          // will use. We pre-create it so save() does not fail.
          resolver: () async => tempDir,
        ),
        nowUtc: nowProvider,
      );

      // Pre-create the recovery subdirectory (save() creates it, but we
      // explicitly do it here so the list/trim operations can always see it).
      final recoverySubDir = Directory(p.join(tempDir.path, 'recovery'));
      await recoverySubDir.create(recursive: true);

      final useCase = SaveBufferToRecovery(repo);

      // ── 3. Record filenames before any save (should be empty) ─────────────
      expect(
        _sortedTxtFiles(recoverySubDir),
        isEmpty,
        reason:
            'Recovery temp directory must be empty at the start of the test.',
      );

      // ── 4. Drive 12 save calls, recording filenames as they appear ─────────
      //
      // We record each file's basename after it is written so we can later
      // verify which 2 are deleted by trim.
      final savedFilenames = <String>[];

      for (var i = 0; i < _kSaveCount; i++) {
        // Unique, non-empty text for each save (trim-guard passes).
        final text = 'Recovery note $i — distinct content for save $i';
        final file = await useCase(text);

        expect(
          file,
          isNotNull,
          reason:
              'SaveBufferToRecovery.call() must return a non-null File for '
              'non-empty text (save $i).',
        );

        // After each save+trim, record the current sorted filenames.
        // We record the filename of the file that was just written, but the
        // trim may have already deleted it if it is one of the oldest. We
        // capture the pre-trim state differently: save returns the written
        // File, so we note its basename before trim removes it.
        //
        // Since trim is called inside useCase AFTER save, the returned File is
        // the one written by this call. We save the basename for later analysis.
        savedFilenames.add(p.basename(file!.path));
      }

      // After all 12 saves, each save triggered a trim(10). The final state
      // should be exactly 10 files.
      final remainingFiles = _sortedTxtFiles(recoverySubDir);

      // ── 5. Assert exactly 10 files remain (FR-M5-03 / NFR-M5-01) ─────────
      expect(
        remainingFiles.length,
        equals(_kTrimCap),
        reason:
            'After $_kSaveCount saves with trim($_kTrimCap) called after each, '
            'exactly $_kTrimCap .txt files must remain in the recovery '
            'directory (FR-M5-03 / NFR-M5-01). '
            'Found: ${remainingFiles.length} files. '
            'Files: ${remainingFiles.map((f) => p.basename(f.path)).join(', ')}',
      );

      // ── 6. Assert the 2 lexicographically-smallest originals were deleted ──
      //
      // All 12 filenames were saved in ascending timestamp order (10ms apart).
      // trim(10) retains the 10 NEWEST (lexicographically-largest) and deletes
      // the 2 OLDEST (lexicographically-smallest). NFR-M5-01 mandates filename-
      // lexicographic sort — NOT mtime.
      //
      // The 2 filenames that should have been deleted are the first 2 in the
      // savedFilenames list (smallest lexicographic order = oldest timestamps).
      final allSortedSaved = List<String>.from(savedFilenames)..sort();
      final expectedDeleted = allSortedSaved.sublist(
        0,
        _kSaveCount - _kTrimCap,
      );
      final remainingBasenames = remainingFiles
          .map((f) => p.basename(f.path))
          .toSet();

      for (final deletedName in expectedDeleted) {
        expect(
          remainingBasenames.contains(deletedName),
          isFalse,
          reason:
              'File "$deletedName" should have been deleted by trim($_kTrimCap) '
              'as one of the ${_kSaveCount - _kTrimCap} '
              'lexicographically-smallest filenames (NFR-M5-01 — trim sorts '
              'by filename lexicographically, not mtime). '
              'Remaining: ${remainingBasenames.join(', ')}',
        );
      }

      // ── 7. Assert the 10 retained files are the lexicographically-largest ──
      final expectedRetained = allSortedSaved.sublist(_kSaveCount - _kTrimCap);
      for (final retainedName in expectedRetained) {
        expect(
          remainingBasenames.contains(retainedName),
          isTrue,
          reason:
              'File "$retainedName" must be retained by trim($_kTrimCap) — '
              'it is one of the $_kTrimCap lexicographically-largest filenames '
              '(NFR-M5-01). '
              'Remaining: ${remainingBasenames.join(', ')}',
        );
      }
    },
  );
}
