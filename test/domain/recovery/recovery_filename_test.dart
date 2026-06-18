// Tests for RecoveryFilename.parse — inverse of FileRecoveryRepository._buildStem.
//
// Filename grammar (millisecond, §5.1.2, OQ-M5-02):
//   YYYY-MM-DDTHH-MM-SS-mmmZ[.txt]
//   YYYY-MM-DDTHH-MM-SS-mmmZ-<N>[.txt]
//
// Rejection rules:
//   - 6-digit fractional seconds (microsecond width) → null (foreign format)
//   - Any name not matching the millisecond grammar → null
//   - Empty string → null
//   - Must never throw; always returns DateTime? (UTC) or null.

import 'package:foglietto/domain/recovery/recovery_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecoveryFilename.parse', () {
    test(
      'given_validFilenameWithTxtExtension_when_parse_then_returnsCorrectUtcDateTime',
      () {
        final result = RecoveryFilename.parse('2026-06-14T10-30-00-123Z.txt');
        expect(result, equals(DateTime.utc(2026, 6, 14, 10, 30, 0, 123)));
      },
    );

    test(
      'given_validFilenameWithCollisionSuffix_when_parse_then_returnsSameDateTimeAsBase',
      () {
        final result = RecoveryFilename.parse('2026-06-14T10-30-00-123Z-2.txt');
        expect(result, equals(DateTime.utc(2026, 6, 14, 10, 30, 0, 123)));
      },
    );

    test(
      'given_validFilenameWithoutTxtExtension_when_parse_then_returnsCorrectUtcDateTime',
      () {
        final result = RecoveryFilename.parse('2026-06-14T10-30-00-123Z');
        expect(result, equals(DateTime.utc(2026, 6, 14, 10, 30, 0, 123)));
      },
    );

    test('given_notATimestampFilename_when_parse_then_returnsNull', () {
      final result = RecoveryFilename.parse('not-a-timestamp.txt');
      expect(result, isNull);
    });

    test(
      'given_microsecondFilename6DigitFractional_when_parse_then_returnsNull',
      () {
        final result = RecoveryFilename.parse(
          '2026-06-14T10-30-00-123456Z.txt',
        );
        expect(result, isNull);
      },
    );

    test('given_emptyString_when_parse_then_returnsNull', () {
      final result = RecoveryFilename.parse('');
      expect(result, isNull);
    });

    test('given_validFilename_when_parse_then_returnedDateTimeIsUtc', () {
      final result = RecoveryFilename.parse('2026-06-14T10-30-00-123Z.txt');
      expect(result?.isUtc, isTrue);
    });

    test(
      'given_collisionSuffixFilenameWithoutTxtExtension_when_parse_then_returnsCorrectUtcDateTime',
      () {
        final result = RecoveryFilename.parse('2026-06-14T10-30-00-123Z-5');
        expect(result, equals(DateTime.utc(2026, 6, 14, 10, 30, 0, 123)));
      },
    );
  });
}
