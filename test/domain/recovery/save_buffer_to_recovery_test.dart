// TDD — TASK-05 (M2) + TASK-06 (M5): SaveBufferToRecovery use case.
//
// Test strategy:
//   A fake RecoveryRepository records the CALL ORDER across save() and trim()
//   so TASK-06 tests can assert trim(10) always runs AFTER save — and never
//   when save throws or when the trim-empty guard fires.
//
//   M2 scenarios (§5.1.2, EC-M2-02):
//   1. Non-empty text  → delegates RAW text to repo.save; returns the sentinel.
//   2. Empty string    → returns null; repo.save NEVER called.
//   3. Whitespace-only → returns null; repo.save NEVER called.
//   4. Padded text     → trim is non-empty, so delegates the RAW (un-trimmed)
//                        text to repo.save; NOT the trimmed version.
//
//   M5 scenarios (FR-M5-03, §5.1.4):
//   5. Non-empty text  → call order is ['save:<text>', 'trim:10'].
//   6. save() throws   → exception propagates; trim NOT called.
//   7. Whitespace-only → returns null; neither save nor trim called.
//
// Format: given_<context>_when_<action>_then_<outcome>

import 'dart:io';

import 'package:buffer/domain/recovery/recovery_note.dart';
import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  /// Ordered record of every call made. Entries have the form:
  ///   `save:<text>`  — for save(text)
  ///   `trim:<keep>`  — for trim(keep)
  final List<String> callLog = [];

  /// When non-null, save() throws this exception instead of returning.
  Object? saveError;

  final File sentinel;

  _FakeRecoveryRepository(this.sentinel);

  @override
  Future<File> save(String text) async {
    if (saveError != null) throw saveError!;
    callLog.add('save:$text');
    return sentinel;
  }

  @override
  Future<void> trim(int keep) async {
    callLog.add('trim:$keep');
  }

  // --- stubs for M5 members not exercised by this use case ---

  @override
  Future<List<RecoveryNote>> list() async => const [];

  @override
  Future<String> read(RecoveryNote note) async => '';

  @override
  Future<void> delete(RecoveryNote note) async {}

  @override
  Future<void> deleteAll() async {}

  // Defect-B sync stub — not exercised by use-case unit tests.
  @override
  File saveSync(String text, {int keep = 10}) => sentinel;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late File sentinel;
  late _FakeRecoveryRepository fakeRepo;
  late SaveBufferToRecovery useCase;

  setUp(() {
    sentinel = File('sentinel.txt');
    fakeRepo = _FakeRecoveryRepository(sentinel);
    useCase = SaveBufferToRecovery(fakeRepo);
  });

  group('SaveBufferToRecovery', () {
    // -------------------------------------------------------------------------
    // M2: Non-empty text → delegates raw text, returns sentinel (FR-M2-13, §5.1.2)
    // -------------------------------------------------------------------------

    test(
      'given_non_empty_text_when_called_then_delegates_raw_text_to_repository_and_returns_file',
      () async {
        final result = await useCase('hello');

        expect(fakeRepo.callLog, contains('save:hello'));
        expect(result, equals(sentinel));
      },
    );

    // -------------------------------------------------------------------------
    // M2: Empty string → null, zero I/O (EC-M2-02)
    // -------------------------------------------------------------------------

    test(
      'given_empty_string_when_called_then_returns_null_with_zero_repository_calls',
      () async {
        final result = await useCase('');

        expect(result, isNull);
        expect(fakeRepo.callLog, isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // M2: Whitespace-only → null, zero I/O (EC-M2-02)
    // -------------------------------------------------------------------------

    test(
      'given_whitespace_only_text_when_called_then_returns_null_with_zero_repository_calls',
      () async {
        final result = await useCase('   \n\t');

        expect(result, isNull);
        expect(fakeRepo.callLog, isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // M2: Padded text → trim decides empty/non-empty, but RAW text is delegated
    // -------------------------------------------------------------------------

    test(
      'given_padded_non_empty_text_when_called_then_delegates_raw_untrimed_text_to_repository',
      () async {
        final result = await useCase('  hi  ');

        expect(fakeRepo.callLog, contains('save:  hi  '));
        expect(result, equals(sentinel));
      },
    );

    // -------------------------------------------------------------------------
    // M5: trim(10) called AFTER save, in that order (FR-M5-03, §5.1.4)
    // -------------------------------------------------------------------------

    test(
      'given_non_empty_text_when_called_then_trim10_invoked_strictly_after_save',
      () async {
        await useCase('hello');

        expect(fakeRepo.callLog, equals(['save:hello', 'trim:10']));
      },
    );

    // -------------------------------------------------------------------------
    // M5: save throws → trim NOT called; exception propagates (§5.1.4)
    // -------------------------------------------------------------------------

    test(
      'given_repository_save_throws_when_called_then_exception_propagates_and_trim_is_not_called',
      () async {
        fakeRepo.saveError = const FileSystemException('disk full');

        await expectLater(
          () => useCase('hello'),
          throwsA(isA<FileSystemException>()),
        );
        expect(fakeRepo.callLog, isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // M5: whitespace-only → M2 guard fires; neither save nor trim invoked
    // -------------------------------------------------------------------------

    test(
      'given_whitespace_only_text_when_called_then_neither_save_nor_trim_invoked',
      () async {
        final result = await useCase('   ');

        expect(result, isNull);
        expect(fakeRepo.callLog, isEmpty);
      },
    );
  });
}
