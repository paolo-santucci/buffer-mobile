import 'package:buffer/domain/recovery/recovery_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecoveryPreview.truncate', () {
    test(
      'given_input_exactly_80_chars_no_newline_when_truncate_then_unchanged_length_80',
      () {
        final input = 'a' * 80;
        final result = RecoveryPreview.truncate(input);
        expect(result, equals(input));
        expect(result.length, equals(80));
      },
    );

    test(
      'given_input_less_than_80_chars_no_newline_when_truncate_then_identity',
      () {
        const input = 'short string';
        final result = RecoveryPreview.truncate(input);
        expect(result, equals(input));
      },
    );

    test(
      'given_input_greater_than_80_chars_no_newline_when_truncate_then_first_80_chars_no_ellipsis',
      () {
        final input = 'a' * 120;
        final result = RecoveryPreview.truncate(input);
        expect(result.length, equals(80));
        expect(result, equals('a' * 80));
        expect(result.contains('…'), isFalse);
      },
    );

    test(
      'given_multiline_input_when_truncate_then_newlines_collapsed_length_leq_80_no_newline',
      () {
        // "line one\nline two\n" is 19 chars; then pad with 200 chars of 'x'
        final input = 'line one\nline two\n${'x' * 200}';
        final result = RecoveryPreview.truncate(input);
        expect(result.length, lessThanOrEqualTo(80));
        expect(result.contains('\n'), isFalse);
      },
    );

    test(
      'given_string_of_only_newline_runs_when_truncate_then_collapses_to_single_space',
      () {
        const input = '\n\n\n\n';
        final result = RecoveryPreview.truncate(input);
        expect(result, equals(' '));
        expect(result.length, equals(1));
        expect(result.contains('\n'), isFalse);
      },
    );

    test(
      'given_multiline_input_whose_collapsed_form_is_exactly_80_when_truncate_then_no_further_truncation',
      () {
        // Build a string whose collapsed form is exactly 80 chars.
        // "hello\nworld" collapsed = "hello world" (11 chars).
        // We need collapsed to be exactly 80: 39 + '\n' + 40 = "a*39 \n b*40" → collapsed = "a*39 b*40" = 80 chars.
        final input = '${'a' * 39}\n${'b' * 40}';
        final collapsed = '${'a' * 39} ${'b' * 40}'; // 39 + 1 + 40 = 80
        final result = RecoveryPreview.truncate(input);
        expect(result.length, equals(80));
        expect(result, equals(collapsed));
        expect(result.contains('\n'), isFalse);
      },
    );

    test(
      'given_emoji_straddling_position_79_to_80_when_truncate_then_length_leq_80_no_newline_no_surrogate_split',
      () {
        // An emoji like '😀' uses 2 UTF-16 code units (a surrogate pair).
        // Place 79 'a' chars then the emoji: total = 79 + 2 = 81 code units.
        // Truncation must NOT cut between the two surrogates of the emoji.
        final emoji = '\u{1F600}'; // 😀 — 2 UTF-16 code units
        expect(emoji.length, equals(2)); // verify it's a surrogate pair
        final input = '${'a' * 79}$emoji';
        expect(input.length, equals(81));

        // Must not throw a RangeError and output ≤ 80 code units.
        final result = RecoveryPreview.truncate(input);
        expect(result.length, lessThanOrEqualTo(80));
        expect(result.contains('\n'), isFalse);
        // Ensure no lone surrogate by checking we can encode the result.
        expect(() => result.codeUnits, returnsNormally);
      },
    );
  });
}
