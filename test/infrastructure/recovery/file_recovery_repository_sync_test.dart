// T-02: FileRecoveryRepository.saveSync — RED phase.
//
// Tests are written first and must FAIL before the implementation is written.
//
// Contract ref: RecoveryRepository.saveSync(String text, {int keep = 10}) §3.1
// of qp-20260614-fix-android-newline-recovery.md
//
// Setup idiom mirrors test/infrastructure/recovery/file_recovery_repository_test.dart:
// temp dir + injectable NowUtcProvider for deterministic filenames.
//
// Spec refs: C-04, C-05, EC-M2-07, EC-M2-08, NFR-M5-01

import 'dart:convert';
import 'dart:io';

import 'package:foglietto/infrastructure/paths/sandbox_path_provider.dart';
import 'package:foglietto/infrastructure/recovery/file_recovery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Directory? tempDir;

  AppSupportDirResolver resolverFor(Directory dir) =>
      () async => dir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'file_recovery_repo_sync_test_',
    );
  });

  tearDown(() {
    tempDir?.deleteSync(recursive: true);
    tempDir = null;
  });

  /// Seeds [count] .txt files in the recovery dir using distinct lexicographic
  /// timestamps starting from [base] with [stepMs] millisecond increments.
  /// Returns the list of created File objects, oldest-first.
  List<File> seedFiles(
    Directory recoveryDir,
    int count, {
    DateTime? base,
    int stepMs = 1,
  }) {
    recoveryDir.createSync(recursive: true);
    final start = base ?? DateTime.utc(2026, 1, 1, 0, 0, 0, 0);
    final created = <File>[];
    for (var i = 0; i < count; i++) {
      final ts = start.add(Duration(milliseconds: i * stepMs));
      final stem = _buildStem(ts);
      final file = File('${recoveryDir.path}/$stem.txt');
      file.writeAsStringSync('seed-$i', encoding: utf8);
      created.add(file);
    }
    return created;
  }

  FileRecoveryRepository makeRepo({DateTime? fixedNow}) {
    return FileRecoveryRepository(
      pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
      nowUtc: fixedNow != null ? () => fixedNow : null,
      syncRecoveryDir: () => Directory('${tempDir!.path}/recovery'),
    );
  }

  // ---------------------------------------------------------------------------
  // Group 1 — durable write + lexicographic trim
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.saveSync — durable write and trim', () {
    test('saveSync_writes_file_durably_and_trims_to_keep', () {
      // Arrange: pre-seed 10 existing files with distinct timestamps.
      final recoveryDir = Directory('${tempDir!.path}/recovery');
      final seeded = seedFiles(
        recoveryDir,
        10,
        base: DateTime.utc(2026, 1, 1, 0, 0, 0, 0),
        stepMs: 1,
      );

      // Use a fixed "now" that is AFTER all seeds so the new file is the
      // newest (lexicographically largest).
      final fixedNow = DateTime.utc(2026, 1, 1, 0, 0, 0, 20);
      final repo = makeRepo(fixedNow: fixedNow);

      // Act — synchronous call; no await.
      final written = repo.saveSync('recovered text', keep: 10);

      // Assert 1: returned File exists immediately (before any microtask drain).
      expect(
        written.existsSync(),
        isTrue,
        reason: 'saveSync must write the file before returning',
      );

      // Assert 2: content is correct, UTF-8.
      expect(
        written.readAsStringSync(encoding: utf8),
        equals('recovered text'),
      );

      // Assert 3: exactly 10 .txt files remain.
      final remaining = recoveryDir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.txt')
          .toList();
      expect(
        remaining.length,
        equals(10),
        reason: 'saveSync must trim to keep=10 after writing (was 10+1=11)',
      );

      // Assert 4: the OLDEST file (seeds[0]) was deleted; the 9 newer seeds
      // + the new file survive (newest-10 by lexicographic filename).
      expect(
        seeded.first.existsSync(),
        isFalse,
        reason: 'oldest file must be deleted to stay within keep=10',
      );

      // All later seeds (indices 1..9) must survive.
      for (final f in seeded.skip(1)) {
        expect(
          f.existsSync(),
          isTrue,
          reason: '${p.basename(f.path)} should survive the trim',
        );
      }

      // The newly written file must also survive.
      expect(
        written.existsSync(),
        isTrue,
        reason: 'the just-written file must survive the trim',
      );
    });

    test('saveSync_with_fewer_than_keep_files_does_not_delete_any', () {
      // Arrange: pre-seed 5 files; keep=10 — no trim expected.
      final recoveryDir = Directory('${tempDir!.path}/recovery');
      final seeded = seedFiles(
        recoveryDir,
        5,
        base: DateTime.utc(2026, 1, 1),
        stepMs: 1,
      );

      final fixedNow = DateTime.utc(2026, 1, 1, 0, 0, 0, 10);
      final repo = makeRepo(fixedNow: fixedNow);

      repo.saveSync('text', keep: 10);

      // All 5 seeds + new file = 6, all must exist.
      for (final f in seeded) {
        expect(
          f.existsSync(),
          isTrue,
          reason: '${p.basename(f.path)} must survive (total < keep)',
        );
      }

      final remaining = recoveryDir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.txt')
          .toList();
      expect(remaining.length, equals(6));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2 — collision handling
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.saveSync — collision suffix', () {
    test('saveSync_on_collision_appends_dash_1_never_overwrites', () {
      // Arrange: pre-create the base file for a fixed timestamp.
      final fixedNow = DateTime.utc(2026, 6, 14, 12, 0, 0, 0);
      final stem = _buildStem(fixedNow);
      final recoveryDir = Directory('${tempDir!.path}/recovery');
      recoveryDir.createSync(recursive: true);
      final existing = File('${recoveryDir.path}/$stem.txt');
      existing.writeAsStringSync('original', encoding: utf8);

      final repo = makeRepo(fixedNow: fixedNow);

      // Act — saveSync with same timestamp → must resolve to -1 variant.
      final written = repo.saveSync('collision content', keep: 10);

      // Assert: written to -1 variant.
      expect(
        p.basename(written.path),
        equals('$stem-1.txt'),
        reason: 'collision must produce -1 suffix',
      );

      // Original not overwritten.
      expect(existing.readAsStringSync(encoding: utf8), equals('original'));

      // -1 variant has the new content.
      expect(
        written.readAsStringSync(encoding: utf8),
        equals('collision content'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3 — FileSystemException propagation
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.saveSync — FileSystemException propagation', () {
    test(
      'saveSync_throws_FileSystemException_unchanged_when_createSync_fails',
      () {
        // Arrange: inject a DirectoryFactory whose createSync throws.
        final repo = FileRecoveryRepository(
          pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
          directoryFactory: (path) => _ThrowingDirectory(path),
          syncRecoveryDir: () => Directory('${tempDir!.path}/recovery'),
        );

        // Act + Assert: FileSystemException propagates unchanged — NOT swallowed.
        expect(
          () => repo.saveSync('will fail', keep: 10),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Replicates FileRecoveryRepository._buildStem for test stem generation.
/// Format: YYYY-MM-DDTHH-MM-SS-mmmZ
String _buildStem(DateTime now) {
  String pad(int v, int w) => v.toString().padLeft(w, '0');
  final y = pad(now.year, 4);
  final mo = pad(now.month, 2);
  final d = pad(now.day, 2);
  final h = pad(now.hour, 2);
  final mi = pad(now.minute, 2);
  final s = pad(now.second, 2);
  final ms = pad(now.millisecond, 3);
  return '$y-$mo-${d}T$h-$mi-$s-${ms}Z';
}

/// A Directory stub whose [createSync] always throws [FileSystemException].
/// Used to verify that saveSync propagates the error unchanged.
class _ThrowingDirectory implements Directory {
  _ThrowingDirectory(this.path);

  @override
  final String path;

  @override
  void createSync({bool recursive = false}) {
    throw FileSystemException('Simulated createSync failure', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
