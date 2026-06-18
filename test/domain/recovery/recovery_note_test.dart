// TDD — TASK-01 (M5): RecoveryNote immutable value entity.
//
// Test strategy:
//   RecoveryNote is a plain @immutable class with three fields:
//   path (String), savedAt (DateTime), preview (String).
//   It enforces value equality and hashCode on all three fields.
//   No copyWith (read-only entity). No Flutter import.
//
// Invariants documented but NOT enforced by the constructor (producer guarantees):
//   - preview.length <= 80
//   - preview contains no '\n'
//   - savedAt.isUtc == true
//   - savedAt derived from the filename, never from mtime

import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecoveryNote', () {
    // -----------------------------------------------------------------------
    // Construction — field storage
    // -----------------------------------------------------------------------

    test(
      'given_preview_of_exactly_80_chars_when_constructed_then_preview_length_is_80',
      () {
        final preview80 = 'a' * 80;
        final note = RecoveryNote(
          path: '/recovery/2026-06-14T10-30-00-123Z.txt',
          savedAt: DateTime.utc(2026, 6, 14, 10, 30, 0, 123),
          preview: preview80,
        );

        expect(note.preview.length, equals(80));
      },
    );

    test('given_utc_savedAt_when_constructed_then_savedAt_isUtc_is_true', () {
      final note = RecoveryNote(
        path: '/recovery/2026-06-14T10-30-00-123Z.txt',
        savedAt: DateTime.utc(2026, 6, 14, 10, 30, 0, 123),
        preview: 'hello',
      );

      expect(note.savedAt.isUtc, isTrue);
    });

    // -----------------------------------------------------------------------
    // Value equality
    // -----------------------------------------------------------------------

    test(
      'given_two_notes_with_identical_path_savedAt_preview_when_compared_then_they_are_equal',
      () {
        final savedAt = DateTime.utc(2026, 6, 14, 10, 30, 0, 123);
        final a = RecoveryNote(
          path: '/recovery/2026-06-14T10-30-00-123Z.txt',
          savedAt: savedAt,
          preview: 'hello',
        );
        final b = RecoveryNote(
          path: '/recovery/2026-06-14T10-30-00-123Z.txt',
          savedAt: savedAt,
          preview: 'hello',
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      },
    );

    test(
      'given_two_notes_differing_only_in_path_when_compared_then_they_are_not_equal',
      () {
        final savedAt = DateTime.utc(2026, 6, 14, 10, 30, 0, 123);
        final a = RecoveryNote(
          path: '/recovery/2026-06-14T10-30-00-123Z.txt',
          savedAt: savedAt,
          preview: 'hello',
        );
        final b = RecoveryNote(
          path: '/recovery/2026-06-14T10-30-00-456Z.txt',
          savedAt: savedAt,
          preview: 'hello',
        );

        expect(a, isNot(equals(b)));
      },
    );
  });
}
