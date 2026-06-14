// TDD — TASK-05 (M5): FileRecoveryRepository list/read/delete/deleteAll/trim.
//
// Test strategy:
//   All tests use a real temp directory (no mocking of dart:io) so that
//   behaviour is identical to production. The `resolverFor(dir)` helper
//   mirrors the M2 pattern in the save tests: it injects the temp dir as the
//   recovery directory and a fixed NowUtc so collisions are predictable.
//
//   The _directoryFactory and _pathProvider seams from the M2 implementation
//   are reused without modification — no new seams added.
//
// Format: given_<context>_when_<action>_then_<outcome>

import 'dart:io';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/infrastructure/recovery/file_recovery_repository.dart';
import 'package:buffer/infrastructure/paths/sandbox_path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Harness helpers
// ---------------------------------------------------------------------------

/// Returns a [SandboxPathProvider] whose [recoveryDirectory] resolves to [dir].
///
/// Mirrors the M2 `resolverFor` pattern: the [SandboxPathProvider] is created
/// with a `resolver` that returns the parent of the injected recovery dir so
/// that `<parent>/recovery` resolves back to [dir] without invoking a platform
/// channel.
SandboxPathProvider _providerFor(Directory dir) =>
    SandboxPathProvider(resolver: () async => dir.parent);

/// Creates a [FileRecoveryRepository] wired to [recoveryDir].
///
/// [nowUtc] defaults to a fixed timestamp suitable for the test.
FileRecoveryRepository _repoFor(
  Directory recoveryDir, {
  DateTime Function()? nowUtc,
}) {
  return FileRecoveryRepository(
    pathProvider: _providerFor(recoveryDir),
    nowUtc: nowUtc,
  );
}

/// Writes a minimal `.txt` file named [filename] in [dir] with [content].
File _writeFile(Directory dir, String filename, {String content = 'hello'}) {
  final f = File(p.join(dir.path, filename));
  f.writeAsStringSync(content);
  return f;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FileRecoveryRepository.trim', () {
    late Directory tempDir;
    late Directory recoveryDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frr_trim_test_');
      recoveryDir = Directory(p.join(tempDir.path, 'recovery'))..createSync();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // -----------------------------------------------------------------------
    // Core trim: 12 → 10
    // -----------------------------------------------------------------------

    test(
      'given_12_lexicographic_txt_files_when_trim_10_then_10_newest_by_filename_remain',
      () async {
        // Create 12 files with lexicographically ordered names (simulating 12
        // saves at different timestamps).
        final names = List.generate(
          12,
          (i) => '2026-06-14T10-00-${i.toString().padLeft(2, '0')}-000Z.txt',
        );
        for (final name in names) {
          _writeFile(recoveryDir, name);
        }

        final repo = _repoFor(recoveryDir);
        await repo.trim(10);

        final remaining =
            recoveryDir
                .listSync()
                .whereType<File>()
                .map((f) => p.basename(f.path))
                .toList()
              ..sort();

        // The 2 lexicographically smallest (oldest) should be deleted.
        // Smallest: '2026-06-14T10-00-00-000Z.txt' and '2026-06-14T10-00-01-000Z.txt'
        expect(remaining.length, equals(10));
        expect(
          remaining.contains('2026-06-14T10-00-00-000Z.txt'),
          isFalse,
          reason: 'Oldest file must be deleted',
        );
        expect(
          remaining.contains('2026-06-14T10-00-01-000Z.txt'),
          isFalse,
          reason: 'Second-oldest file must be deleted',
        );
        // Newest should survive
        expect(
          remaining.contains('2026-06-14T10-00-11-000Z.txt'),
          isTrue,
          reason: 'Newest file must survive',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Suffix edge: base.txt, base-1.txt … base-10.txt  (12 files total)
    // -----------------------------------------------------------------------

    test(
      'given_12_files_with_collision_suffix_when_trim_10_then_2_lexicographically_smallest_deleted',
      () async {
        // Simulate collision-suffix naming: base stem + -1 … -11 suffixes.
        // base.txt + base-1.txt through base-11.txt = 12 files total.
        // This validates the determinism edge: '-10' < '-2' lexicographically
        // (because '1' < '2'), so base-10.txt sorts before base-2.txt.
        const stem = '2026-06-14T10-00-00-000Z';
        _writeFile(recoveryDir, '$stem.txt');
        for (var i = 1; i <= 11; i++) {
          _writeFile(recoveryDir, '$stem-$i.txt');
        }

        final repo = _repoFor(recoveryDir);
        await repo.trim(10);

        final remaining =
            recoveryDir
                .listSync()
                .whereType<File>()
                .map((f) => p.basename(f.path))
                .toList()
              ..sort();

        // Lexicographically sorted, the 2 smallest are:
        //   2026-06-14T10-00-00-000Z-1.txt
        //   2026-06-14T10-00-00-000Z-10.txt
        // (because '-1' < '-10' < '-2' ... < '-9' < '.txt' alphabetically)
        // Full lexicographic sort of the 12 names (ASCII '-' = 0x2D, '.' = 0x2E,
        // digits 0x30-0x39; '-' < '.' < digits):
        //   $stem-1.txt, $stem-10.txt, $stem-11.txt, $stem-2.txt, ...,
        //   $stem-9.txt, $stem.txt
        // trim(10) deletes the 2 lexicographically smallest:
        //   $stem-1.txt (index 0) and $stem-10.txt (index 1).
        expect(remaining.length, equals(10));
        expect(
          remaining.contains('$stem-1.txt'),
          isFalse,
          reason: 'Lexicographically smallest ($stem-1.txt) must be deleted',
        );
        expect(
          remaining.contains('$stem-10.txt'),
          isFalse,
          reason:
              'Second lexicographically smallest ($stem-10.txt) must be deleted',
        );
        // The base (no suffix), -11.txt and -2 through -9 should survive
        expect(remaining.contains('$stem.txt'), isTrue);
        expect(remaining.contains('$stem-11.txt'), isTrue);
        expect(remaining.contains('$stem-2.txt'), isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // No-op: exactly keep count
    // -----------------------------------------------------------------------

    test(
      'given_exactly_10_txt_files_when_trim_10_then_all_10_remain_no_op',
      () async {
        for (var i = 0; i < 10; i++) {
          _writeFile(
            recoveryDir,
            '2026-06-14T10-00-${i.toString().padLeft(2, '0')}-000Z.txt',
          );
        }

        final repo = _repoFor(recoveryDir);
        await repo.trim(10);

        final count = recoveryDir.listSync().whereType<File>().length;
        expect(count, equals(10));
      },
    );

    // -----------------------------------------------------------------------
    // No-op: fewer than keep count
    // -----------------------------------------------------------------------

    test('given_9_txt_files_when_trim_10_then_all_9_remain_no_op', () async {
      for (var i = 0; i < 9; i++) {
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-${i.toString().padLeft(2, '0')}-000Z.txt',
        );
      }

      final repo = _repoFor(recoveryDir);
      await repo.trim(10);

      final count = recoveryDir.listSync().whereType<File>().length;
      expect(count, equals(9));
    });

    // -----------------------------------------------------------------------
    // Absent directory → no throw, dir NOT created
    // -----------------------------------------------------------------------

    test(
      'given_absent_recovery_dir_when_trim_then_no_throw_and_dir_not_created',
      () async {
        final absentDir = Directory(p.join(tempDir.path, 'absent_recovery'));
        expect(absentDir.existsSync(), isFalse);

        final repo = _repoFor(absentDir);
        await expectLater(repo.trim(10), completes);

        expect(
          absentDir.existsSync(),
          isFalse,
          reason: 'trim must not create the recovery directory',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.list', () {
    late Directory tempDir;
    late Directory recoveryDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frr_list_test_');
      recoveryDir = Directory(p.join(tempDir.path, 'recovery'))..createSync();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // -----------------------------------------------------------------------
    // Absent directory → const [], no throw, dir NOT created
    // -----------------------------------------------------------------------

    test(
      'given_absent_recovery_dir_when_list_then_returns_empty_and_dir_not_created',
      () async {
        final absentDir = Directory(p.join(tempDir.path, 'absent_recovery'));
        expect(absentDir.existsSync(), isFalse);

        final repo = _repoFor(absentDir);
        final notes = await repo.list();

        expect(notes, isEmpty);
        expect(
          absentDir.existsSync(),
          isFalse,
          reason: 'list must not create the recovery directory',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 3 well-formed .txt → 3 RecoveryNotes, newest-first, savedAt from filename,
    // every preview ≤80 and no \n
    // -----------------------------------------------------------------------

    test(
      'given_3_wellformed_txt_files_when_list_then_3_notes_newest_first_with_valid_preview',
      () async {
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-01-000Z.txt',
          content: 'First note',
        );
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-02-000Z.txt',
          content: 'Second note',
        );
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-03-000Z.txt',
          content: 'Third note',
        );

        final repo = _repoFor(recoveryDir);
        final notes = await repo.list();

        expect(notes.length, equals(3));
        // Newest first (descending by savedAt)
        expect(notes[0].savedAt, equals(DateTime.utc(2026, 6, 14, 10, 0, 3)));
        expect(notes[1].savedAt, equals(DateTime.utc(2026, 6, 14, 10, 0, 2)));
        expect(notes[2].savedAt, equals(DateTime.utc(2026, 6, 14, 10, 0, 1)));
        // All previews ≤80 and no \n
        for (final note in notes) {
          expect(note.preview.length, lessThanOrEqualTo(80));
          expect(note.preview.contains('\n'), isFalse);
        }
      },
    );

    // -----------------------------------------------------------------------
    // 1 malformed + 2 well-formed → only 2 well-formed returned
    // -----------------------------------------------------------------------

    test(
      'given_1_malformed_and_2_wellformed_txt_when_list_then_only_2_wellformed_returned',
      () async {
        _writeFile(recoveryDir, 'not-a-timestamp.txt', content: 'bad');
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-01-000Z.txt',
          content: 'Good one',
        );
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-02-000Z.txt',
          content: 'Good two',
        );

        final repo = _repoFor(recoveryDir);
        final notes = await repo.list();

        expect(notes.length, equals(2));
        // savedAt fields are parseable (malformed was skipped)
        for (final note in notes) {
          expect(note.savedAt.isUtc, isTrue);
        }
      },
    );

    // -----------------------------------------------------------------------
    // Multiline content → preview has no \n and is ≤ 80
    // -----------------------------------------------------------------------

    test(
      'given_multiline_file_content_when_list_then_preview_has_no_newline_and_le_80',
      () async {
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-01-000Z.txt',
          content: 'Line one\nLine two\nLine three\n${'x' * 200}',
        );

        final repo = _repoFor(recoveryDir);
        final notes = await repo.list();

        expect(notes.length, equals(1));
        expect(notes[0].preview.contains('\n'), isFalse);
        expect(notes[0].preview.length, lessThanOrEqualTo(80));
      },
    );
  });

  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.delete', () {
    late Directory tempDir;
    late Directory recoveryDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frr_delete_test_');
      recoveryDir = Directory(p.join(tempDir.path, 'recovery'))..createSync();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // -----------------------------------------------------------------------
    // 3 notes → delete middle → 2 siblings intact, only target removed
    // -----------------------------------------------------------------------

    test(
      'given_3_notes_when_delete_middle_then_only_target_removed_and_siblings_intact',
      () async {
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-01-000Z.txt',
          content: 'first',
        );
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-02-000Z.txt',
          content: 'second',
        );
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-03-000Z.txt',
          content: 'third',
        );

        final repo = _repoFor(recoveryDir);
        final notes = await repo.list();
        // notes is newest-first: [10-00-03, 10-00-02, 10-00-01]
        final middleNote = notes[1]; // 10-00-02

        await repo.delete(middleNote);

        final remaining = recoveryDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toSet();

        expect(remaining.length, equals(2));
        expect(remaining.contains('2026-06-14T10-00-02-000Z.txt'), isFalse);
        expect(remaining.contains('2026-06-14T10-00-01-000Z.txt'), isTrue);
        expect(remaining.contains('2026-06-14T10-00-03-000Z.txt'), isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // Absent dir → no-op, no throw
    // -----------------------------------------------------------------------

    test(
      'given_absent_recovery_dir_when_delete_then_no_throw_and_dir_not_created',
      () async {
        final absentDir = Directory(p.join(tempDir.path, 'absent_recovery'));
        final note = RecoveryNote(
          path: p.join(absentDir.path, '2026-06-14T10-00-01-000Z.txt'),
          savedAt: DateTime.utc(2026, 6, 14, 10, 0, 1),
          preview: 'x',
        );

        final repo = _repoFor(absentDir);
        await expectLater(repo.delete(note), completes);

        expect(absentDir.existsSync(), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // Target absent but siblings present → no throw, siblings intact
    // -----------------------------------------------------------------------

    test(
      'given_target_absent_but_siblings_present_when_delete_then_no_throw_siblings_intact',
      () async {
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-01-000Z.txt',
          content: 'first',
        );
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-03-000Z.txt',
          content: 'third',
        );

        // Create a note pointing at a non-existent file
        final absentNote = RecoveryNote(
          path: p.join(recoveryDir.path, '2026-06-14T10-00-02-000Z.txt'),
          savedAt: DateTime.utc(2026, 6, 14, 10, 0, 2),
          preview: 'absent',
        );

        final repo = _repoFor(recoveryDir);
        await expectLater(repo.delete(absentNote), completes);

        final remaining = recoveryDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toSet();

        expect(remaining.length, equals(2));
        expect(remaining.contains('2026-06-14T10-00-01-000Z.txt'), isTrue);
        expect(remaining.contains('2026-06-14T10-00-03-000Z.txt'), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.deleteAll', () {
    late Directory tempDir;
    late Directory recoveryDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frr_deleteall_test_');
      recoveryDir = Directory(p.join(tempDir.path, 'recovery'))..createSync();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // -----------------------------------------------------------------------
    // 3 notes → dir empty afterward
    // -----------------------------------------------------------------------

    test('given_3_txt_files_when_deleteAll_then_dir_is_empty', () async {
      _writeFile(recoveryDir, '2026-06-14T10-00-01-000Z.txt');
      _writeFile(recoveryDir, '2026-06-14T10-00-02-000Z.txt');
      _writeFile(recoveryDir, '2026-06-14T10-00-03-000Z.txt');

      final repo = _repoFor(recoveryDir);
      await repo.deleteAll();

      final remaining = recoveryDir.listSync().whereType<File>().toList();
      expect(remaining, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Absent dir → no-op, no throw
    // -----------------------------------------------------------------------

    test(
      'given_absent_recovery_dir_when_deleteAll_then_no_throw_and_dir_not_created',
      () async {
        final absentDir = Directory(p.join(tempDir.path, 'absent_recovery'));

        final repo = _repoFor(absentDir);
        await expectLater(repo.deleteAll(), completes);

        expect(absentDir.existsSync(), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.read', () {
    late Directory tempDir;
    late Directory recoveryDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frr_read_test_');
      recoveryDir = Directory(p.join(tempDir.path, 'recovery'))..createSync();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'given_note_with_content_when_read_then_returns_full_utf8_text',
      () async {
        const content = 'Full content\nwith multiple lines\nand émojis 🎉';
        _writeFile(
          recoveryDir,
          '2026-06-14T10-00-01-000Z.txt',
          content: content,
        );

        final repo = _repoFor(recoveryDir);
        final notes = await repo.list();
        expect(notes.length, equals(1));

        final text = await repo.read(notes[0]);
        expect(text, equals(content));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // NFR-M5-01 source scan — no mtime/lastModifiedSync in the impl file
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository NFR source scans', () {
    test(
      'given_impl_source_when_scanned_then_no_mtime_or_stat_api_calls_present',
      () {
        const sourcePath =
            'lib/infrastructure/recovery/file_recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        // Check for actual API call patterns (method invocations, not words in
        // comments). Matches .<method>( or .<method>; style access.
        // These are the filesystem mtime/stat API calls forbidden by NFR-M5-01.
        final forbiddenPatterns = <RegExp>[
          RegExp(r'\.lastModifiedSync\s*\('),
          RegExp(r'\.lastModified\s*\('),
          RegExp(r'\.statSync\s*\('),
          RegExp(r'\.stat\s*\('),
          RegExp(r'\.changed\s*\('),
        ];
        for (final pattern in forbiddenPatterns) {
          expect(
            pattern.hasMatch(source),
            isFalse,
            reason:
                'NFR-M5-01: file_recovery_repository.dart must not call '
                '`${pattern.pattern}` — trim sort must use lexicographic '
                'filename only, never filesystem timestamps.',
          );
        }
      },
    );

    test('given_impl_source_when_scanned_then_no_print_calls_present', () {
      const sourcePath =
          'lib/infrastructure/recovery/file_recovery_repository.dart';
      final source = File(sourcePath).readAsStringSync();

      expect(
        RegExp(r'\bprint\s*\(').hasMatch(source),
        isFalse,
        reason: 'NFR-M5-04: No print() allowed in implementation file.',
      );
    });

    test(
      'given_impl_source_when_scanned_then_no_member_creates_the_recovery_dir_outside_save',
      () {
        const sourcePath =
            'lib/infrastructure/recovery/file_recovery_repository.dart';
        final source = File(sourcePath).readAsStringSync();

        // The only place `.create(` may appear is inside the `save` method body.
        // We detect by confirming that every `.create(` line appears after
        // `Future<File> save(` in the file (a simple structural check).
        final lines = source.split('\n');
        final saveMethodIndex = lines.indexWhere(
          (l) => l.contains('Future<File> save('),
        );
        final createCallIndices = lines
            .asMap()
            .entries
            .where((e) => e.value.contains('.create('))
            .map((e) => e.key)
            .toList();

        for (final idx in createCallIndices) {
          expect(
            idx > saveMethodIndex,
            isTrue,
            reason:
                'No-create invariant: `.create(` at line ${idx + 1} must '
                'appear AFTER the `save` method declaration at line '
                '${saveMethodIndex + 1}. New read-side members must not '
                'create the recovery directory.',
          );
        }
      },
    );
  });
}
