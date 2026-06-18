// TASK-06: FileRecoveryRepository test — RED phase.
//
// Tests are written first and must FAIL before the implementation is written.
//
// Injectable seam: FileRecoveryRepository accepts an AppSupportDirResolver
// (the typedef from SandboxPathProvider) so tests point at a fresh temp dir
// without any platform channel call.
//
// Spec refs: FR-M2-10, FR-M2-11, FR-M2-12, NFR-M2-03, EC-M2-07, EC-M2-08,
//            EC-M2-09, §5.2

import 'dart:convert';
import 'dart:io';

import 'package:foglietto/infrastructure/paths/sandbox_path_provider.dart';
import 'package:foglietto/infrastructure/recovery/file_recovery_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Creates a fresh temp directory per test and returns a resolver that
  /// points at it. Deletes the temp dir in tearDown.
  Directory? tempDir;

  AppSupportDirResolver resolverFor(Directory dir) =>
      () async => dir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_recovery_repo_test_');
  });

  tearDown(() {
    tempDir?.deleteSync(recursive: true);
    tempDir = null;
  });

  FileRecoveryRepository makeRepo() {
    return FileRecoveryRepository(
      pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
    );
  }

  // ---------------------------------------------------------------------------
  // Group 1 — directory creation
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.save — directory creation', () {
    test(
      'given_recovery_dir_absent_when_save_called_then_recovery_dir_created_recursively_and_file_written',
      () async {
        final repo = makeRepo();

        // The recovery subdirectory must NOT exist yet.
        final recoveryDir = Directory('${tempDir!.path}/recovery');
        expect(recoveryDir.existsSync(), isFalse);

        final file = await repo.save('hello');

        expect(
          recoveryDir.existsSync(),
          isTrue,
          reason: 'save() must create the recovery dir recursively',
        );
        expect(file.existsSync(), isTrue);
        expect(file.path.startsWith(recoveryDir.path), isTrue);
      },
    );

    test(
      'given_recovery_dir_already_exists_when_save_called_then_no_error_and_file_written',
      () async {
        // Pre-create the directory to verify save() does not fail if it exists.
        Directory('${tempDir!.path}/recovery').createSync(recursive: true);

        final repo = makeRepo();
        final file = await repo.save('content when dir exists');

        expect(file.existsSync(), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group 2 — filename format (FR-M2-11, NFR-M2-03)
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.save — filename format', () {
    test(
      'given_valid_text_when_save_called_then_filename_matches_utc_iso8601_colons_replaced_by_dash_ends_txt',
      () async {
        final repo = makeRepo();
        final file = await repo.save('text for filename test');

        final name = file.uri.pathSegments.last;
        // Pattern: YYYY-MM-DDTHH-MM-SS-mmmZ.txt
        final pattern = RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z\.txt$',
        );
        expect(
          pattern.hasMatch(name),
          isTrue,
          reason: 'filename "$name" does not match expected pattern',
        );
        expect(
          name.contains(':'),
          isFalse,
          reason: 'colons must be replaced by dashes',
        );
        expect(name.endsWith('.txt'), isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group 3 — UTF-8 round-trip (FR-M2-12)
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.save — UTF-8 round-trip', () {
    test(
      'given_text_with_unicode_when_save_called_then_readback_bytes_equal_utf8_encoded_input',
      () async {
        const input = 'Héllo wörld — 中文 — идея';
        final repo = makeRepo();
        final file = await repo.save(input);

        final readBack = await file.readAsString(encoding: utf8);
        expect(readBack, equals(input));
      },
    );

    test(
      'given_ascii_text_when_save_called_then_readback_string_equals_input',
      () async {
        const input = 'simple ascii text\nwith newline';
        final repo = makeRepo();
        final file = await repo.save(input);

        final readBack = await file.readAsString(encoding: utf8);
        expect(readBack, equals(input));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group 4 — lexicographic == chronological ordering (R-16)
  // ---------------------------------------------------------------------------

  group(
    'FileRecoveryRepository.save — lexicographic equals chronological order',
    () {
      test(
        'given_two_saves_with_clock_advanced_between_them_when_filenames_sorted_lexicographically_then_order_matches_write_time',
        () async {
          final repo = makeRepo();

          final file1 = await repo.save('first save');
          // Advance time by more than 1 ms to ensure distinct timestamps.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final file2 = await repo.save('second save');

          final name1 = file1.uri.pathSegments.last;
          final name2 = file2.uri.pathSegments.last;

          final sorted = [name1, name2]..sort();
          expect(
            sorted,
            equals([name1, name2]),
            reason:
                'lexicographic sort must match write order (lex==chron). '
                'name1=$name1 name2=$name2',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Group 5 — same-instant collision (EC-M2-07)
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.save — collision handling', () {
    test(
      'given_base_filename_already_exists_when_save_called_then_writes_dash_1_variant_original_not_overwritten',
      () async {
        final repo = makeRepo();

        // First save — creates the base file.
        final base = await repo.save('original content');
        final originalContent = await base.readAsString(encoding: utf8);
        expect(originalContent, equals('original content'));

        // Manually create the base filename again to force a collision on the
        // NEXT save by re-creating the file with a known name derived from the
        // first save — we simulate a collision by copying the base file and
        // then calling save with a custom timestamp clock. Since we cannot
        // control DateTime.now() directly, we instead pre-create the file that
        // would be generated for the CURRENT millisecond by copying the base
        // file path and then invoking save immediately, relying on the
        // collision loop.
        //
        // Simpler approach: pre-create a file at the exact same path as the
        // base file returned, write different content, then call save again
        // with the same timestamp. Because we cannot freeze time, we trigger
        // the loop by observing the collision logic directly: use a
        // FileRecoveryRepository subclass that always generates the same stem.
        //
        // The cleanest approach without a clock seam: pre-create the base file,
        // write a known variant file as well, and assert the -1 variant file
        // is created after a new save. We use a TimestampOverride repo.
        //
        // Since the task spec permits a DateTime provider injection for
        // testability (OQ-M2-08), we use that mechanism.
        final baseFilename = base.uri.pathSegments.last;
        final stem = baseFilename.replaceAll('.txt', '');

        // The '-1' file should not exist yet.
        final dash1File = File('${base.parent.path}/$stem-1.txt');
        expect(dash1File.existsSync(), isFalse);

        // Now pre-write the base file (it already exists from the first save)
        // and use the fixed-timestamp repo to force a collision.
        final fixedRepo = FileRecoveryRepository(
          pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
          nowUtc: () => _parseFilenameToDateTime(baseFilename),
        );
        final collisionFile = await fixedRepo.save('collision content');

        expect(
          collisionFile.path,
          equals(dash1File.path),
          reason: 'collision must write -1 variant',
        );
        expect(
          await base.readAsString(encoding: utf8),
          equals('original content'),
          reason: 'original file must not be overwritten',
        );
        expect(
          await collisionFile.readAsString(encoding: utf8),
          equals('collision content'),
        );
      },
    );

    test(
      'given_base_and_dash_1_already_exist_when_save_called_then_writes_dash_2_variant',
      () async {
        final repo = makeRepo();

        // First save creates the base file.
        final base = await repo.save('base');
        final baseFilename = base.uri.pathSegments.last;
        final stem = baseFilename.replaceAll('.txt', '');

        // Pre-create the -1 variant so that the next fixed-clock save must
        // write -2.
        final dash1File = File('${base.parent.path}/$stem-1.txt');
        dash1File.writeAsStringSync('pre-existing -1');

        final fixedRepo = FileRecoveryRepository(
          pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
          nowUtc: () => _parseFilenameToDateTime(baseFilename),
        );
        final dash2File = await fixedRepo.save('dash 2 content');

        expect(dash2File.path, equals('${base.parent.path}/$stem-2.txt'));
        expect(
          await dash2File.readAsString(encoding: utf8),
          equals('dash 2 content'),
        );
        // Base and -1 unchanged.
        expect(await base.readAsString(encoding: utf8), equals('base'));
        expect(
          await dash1File.readAsString(encoding: utf8),
          equals('pre-existing -1'),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group 6 — FileSystemException propagation (EC-M2-09)
  // ---------------------------------------------------------------------------

  group('FileRecoveryRepository.save — FileSystemException propagation', () {
    test(
      'given_a_repo_targeting_unwritable_path_when_save_called_then_FileSystemException_propagates_uncaught',
      () async {
        // Point the resolver at a path whose parent cannot be created.
        final unwritableRepo = FileRecoveryRepository(
          pathProvider: SandboxPathProvider(
            resolver: () async =>
                // Use a path inside a non-root file treated as a directory —
                // the create(recursive:true) will fail because a file
                // blocks directory creation.
                Directory(tempDir!.path),
          ),
          // Override the directory factory so that Directory.create throws.
          directoryFactory: (path) => _ThrowingDirectory(path),
        );

        expect(
          () => unwritableRepo.save('will fail'),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group 7 — concurrent saves never overwrite (BUG-004 / EC-M2-07)
  // ---------------------------------------------------------------------------
  //
  // TOCTOU risk: two save() calls that start before either completes can both
  // see the same stem absent in _resolveFile and both write to the same file,
  // causing the second writeAsString to overwrite the first (EC-M2-07 violated).
  //
  // Fix: save() serialises work on an internal _writeChain so the
  // resolve+write of the second call only begins after the first completes.
  //
  // Test strategy: force a deterministic stem collision by injecting a fixed
  // NowUtcProvider that always returns the same timestamp, then fire two
  // save() calls without awaiting the first.  Under the unfixed code both ops
  // see the base file absent, both resolve to <stem>.txt, and the second
  // writeAsString replaces the first content — only ONE file with ONE content
  // survives.  Under the fixed code the chain ensures the second op runs after
  // the first has already written <stem>.txt, so the collision loop advances
  // to <stem>-1.txt and TWO distinct files exist with their respective
  // contents.
  //
  // RED confirmation: without the _writeChain fix, the test below fails
  // because two files do NOT exist (or one file contains only the later
  // content, not the earlier one).
  group('FileRecoveryRepository.save — concurrent saves (BUG-004)', () {
    test(
      'given_two_concurrent_saves_with_forced_same_stem_when_both_complete_then_two_distinct_files_with_both_contents_exist',
      () async {
        // Fixed clock: always returns the same millisecond — guarantees
        // _buildStem produces the same value for both saves.
        final fixedNow = DateTime.utc(2026, 6, 14, 12, 0, 0, 0);
        final repo = FileRecoveryRepository(
          pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
          nowUtc: () => fixedNow,
        );

        // Pre-create the recovery dir (save() does this anyway, but doing it
        // here ensures both concurrent saves skip the create() race and we
        // test purely the resolve+write serialisation).
        Directory('${tempDir!.path}/recovery').createSync(recursive: true);

        // Fire both saves concurrently — do NOT await the first before
        // starting the second.  This is the scenario that triggers the TOCTOU
        // bug under the unfixed code.
        final f1 = repo.save('content-A');
        final f2 = repo.save('content-B');
        final results = await Future.wait([f1, f2]);

        final file1 = results[0];
        final file2 = results[1];

        // The two files must have DISTINCT paths.
        expect(
          file1.path,
          isNot(equals(file2.path)),
          reason: 'concurrent saves must write to different files (EC-M2-07)',
        );

        // Both files must exist.
        expect(
          file1.existsSync(),
          isTrue,
          reason: 'first save file must exist',
        );
        expect(
          file2.existsSync(),
          isTrue,
          reason: 'second save file must exist',
        );

        // Both original contents must be intact — neither was overwritten.
        final contents = {
          await file1.readAsString(encoding: utf8),
          await file2.readAsString(encoding: utf8),
        };
        expect(
          contents,
          containsAll(['content-A', 'content-B']),
          reason: 'both save contents must survive (neither overwritten)',
        );
      },
    );

    test(
      'given_failing_first_save_when_second_save_concurrent_then_second_save_still_completes',
      () async {
        // Arrange: first save fails due to a throwing directory factory on the
        // first call, then succeeds on subsequent calls.
        var callCount = 0;
        final fixedNow = DateTime.utc(2026, 6, 14, 12, 0, 0, 0);
        final repo = FileRecoveryRepository(
          pathProvider: SandboxPathProvider(resolver: resolverFor(tempDir!)),
          nowUtc: () => fixedNow,
          directoryFactory: (path) {
            callCount++;
            if (callCount == 1) return _ThrowingDirectory(path);
            return Directory(path);
          },
        );

        // First save must throw (its error propagates to the caller).
        final f1 = repo.save('will-fail');
        // Second save is enqueued immediately — it must not be poisoned by f1.
        final f2 = repo.save('will-succeed');

        // f1 throws; f2 must still succeed despite f1 failing.
        await expectLater(f1, throwsA(isA<FileSystemException>()));
        final file2 = await f2;
        expect(file2.existsSync(), isTrue);
        expect(
          await file2.readAsString(encoding: utf8),
          equals('will-succeed'),
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Parse a filename like `2026-06-13T19-20-05-123Z.txt` back to a [DateTime].
/// Used to supply the exact same timestamp to the fixed-clock repo.
DateTime _parseFilenameToDateTime(String filename) {
  // e.g. 2026-06-13T19-20-05-123Z.txt
  final noExt = filename.replaceAll('.txt', '');
  // Replace the three dashes in the time portion back to colons.
  // The format is: YYYY-MM-DDTHH-MM-SS-mmmZ
  // Replace first 2 dashes in time part (after T) with colons.
  final parts = noExt.split('T');
  if (parts.length != 2) return DateTime.now().toUtc();
  final datePart = parts[0]; // YYYY-MM-DD
  final timePart = parts[1]; // HH-MM-SS-mmmZ

  // timePart: HH-MM-SS-mmmZ → split by '-'
  final tp = timePart.replaceAll('Z', '').split('-');
  if (tp.length != 4) return DateTime.now().toUtc();
  final iso = '${datePart}T${tp[0]}:${tp[1]}:${tp[2]}.${tp[3]}Z';
  return DateTime.parse(iso);
}

/// A Directory subclass whose create() always throws [FileSystemException].
class _ThrowingDirectory implements Directory {
  _ThrowingDirectory(this.path);

  @override
  final String path;

  @override
  Future<Directory> create({bool recursive = false}) {
    throw FileSystemException('Simulated write failure', path);
  }

  // All other members delegate to a real Directory for any incidental use,
  // but in practice only create() is called by FileRecoveryRepository.save().
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
