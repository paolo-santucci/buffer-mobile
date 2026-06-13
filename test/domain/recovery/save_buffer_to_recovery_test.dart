// TDD — TASK-05 (M2): SaveBufferToRecovery use case.
//
// Test strategy:
//   A fake RecoveryRepository records every call to save() and returns a
//   sentinel File. The four scenarios from the spec (§5.1.2, EC-M2-02):
//
//   1. Non-empty text  → delegates RAW text to repo.save; returns the sentinel.
//   2. Empty string    → returns null; repo.save NEVER called.
//   3. Whitespace-only → returns null; repo.save NEVER called.
//   4. Padded text     → trim is non-empty, so delegates the RAW (un-trimmed)
//                        text to repo.save; NOT the trimmed version.
//
// Format: given_<context>_when_<action>_then_<outcome>

import 'dart:io';

import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/domain/recovery/save_buffer_to_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

class _FakeRecoveryRepository implements RecoveryRepository {
  final List<String> calls = [];
  final File sentinel;

  _FakeRecoveryRepository(this.sentinel);

  @override
  Future<File> save(String text) async {
    calls.add(text);
    return sentinel;
  }
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
    // Non-empty text → delegates raw text, returns sentinel (FR-M2-13, §5.1.2)
    // -------------------------------------------------------------------------

    test(
      'given_non_empty_text_when_called_then_delegates_raw_text_to_repository_and_returns_file',
      () async {
        final result = await useCase('hello');

        expect(fakeRepo.calls, equals(['hello']));
        expect(result, equals(sentinel));
      },
    );

    // -------------------------------------------------------------------------
    // Empty string → null, zero I/O (EC-M2-02)
    // -------------------------------------------------------------------------

    test(
      'given_empty_string_when_called_then_returns_null_with_zero_repository_calls',
      () async {
        final result = await useCase('');

        expect(result, isNull);
        expect(fakeRepo.calls, isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // Whitespace-only → null, zero I/O (EC-M2-02)
    // -------------------------------------------------------------------------

    test(
      'given_whitespace_only_text_when_called_then_returns_null_with_zero_repository_calls',
      () async {
        final result = await useCase('   \n\t');

        expect(result, isNull);
        expect(fakeRepo.calls, isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // Padded text → trim decides empty/non-empty, but RAW text is delegated
    // -------------------------------------------------------------------------

    test(
      'given_padded_non_empty_text_when_called_then_delegates_raw_untrimed_text_to_repository',
      () async {
        final result = await useCase('  hi  ');

        expect(fakeRepo.calls, equals(['  hi  ']));
        expect(result, equals(sentinel));
      },
    );
  });
}
