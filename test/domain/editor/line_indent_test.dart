// Tests for LineIndent.indent / LineIndent.outdent pure functions.
// TDD: these tests are written FIRST — before any implementation.
// Order: highest-risk offset-drift round-trip cases first (R-10 / EC-15),
// then re-anchoring, then per-line unit, then mode, then outdent no-op.
// Convention: given_<context>_when_<action>_then_<outcome>

import 'package:flutter_test/flutter_test.dart';
import 'package:foglietto/domain/editor/line_indent.dart';

void main() {
  // ─── HIGHEST-RISK: offset-drift round-trip (R-10, EC-15, NFR-03) ───

  group('indent then outdent round-trip', () {
    test(
      'given_10_line_mixed_list_non_list_selection_when_indent_then_outdent_then_text_and_selection_restored_byte_for_byte',
      () {
        const text =
            '- list one\n'
            'plain one\n'
            '1. ordered\n'
            'plain two\n'
            '+ bullet plus\n'
            'plain three\n'
            '* asterisk\n'
            'plain four\n'
            '- list two\n'
            'plain five';
        // Selection spans all 10 lines: from start to end.
        const selStart = 0;
        const selExtent = text.length;

        final indented = LineIndent.indent(text, selStart, selExtent);
        final roundTrip = LineIndent.outdent(
          indented.text,
          indented.selStart,
          indented.selExtent,
        );

        expect(
          roundTrip.text,
          equals(text),
          reason: 'Text must be byte-for-byte restored after indent→outdent',
        );
        expect(
          roundTrip.selStart,
          equals(selStart),
          reason: 'selStart must be exactly restored',
        );
        expect(
          roundTrip.selExtent,
          equals(selExtent),
          reason: 'selExtent must be exactly restored',
        );
      },
    );

    test(
      'given_mixed_indent_units_when_indent_then_outdent_then_no_cumulative_drift',
      () {
        // Alternating list / non-list lines so different units are applied.
        const text =
            '- item a\n'
            'non-list b\n'
            '1. ordered c\n'
            'non-list d\n'
            '* star e';
        const selStart = 0;
        const selExtent = text.length;

        final indented = LineIndent.indent(text, selStart, selExtent);
        final roundTrip = LineIndent.outdent(
          indented.text,
          indented.selStart,
          indented.selExtent,
        );

        expect(roundTrip.text, equals(text));
        expect(roundTrip.selStart, equals(selStart));
        expect(roundTrip.selExtent, equals(selExtent));
      },
    );
  });

  // ─── SELECTION RE-ANCHORING (FR-13, EC-15) ───

  group('indent selection re-anchoring', () {
    test(
      'given_multi_line_selection_when_indent_then_selStart_accounts_for_inserted_chars',
      () {
        // Two non-list lines; selStart at start of first, selExtent at end.
        const text = 'line one\nline two';
        const selStart = 0;
        const selExtent = text.length; // 17

        final result = LineIndent.indent(text, selStart, selExtent);

        // Both lines gain '\t' (non-list), so 2 tabs inserted total.
        expect(result.text, equals('\tline one\n\tline two'));
        // selStart: start of first line — tab prepended before it, so stays 0
        // selExtent: end of last line — two tabs inserted, so 17 + 2 = 19
        expect(result.selStart, equals(0));
        expect(result.selExtent, equals(19));
        expect(result.text.length, equals(19));
      },
    );

    test(
      'given_multi_line_selection_when_outdent_then_selExtent_re_anchored_to_same_lines',
      () {
        const text = '\tline one\n\tline two';
        const selStart = 0;
        const selExtent = text.length; // 19

        final result = LineIndent.outdent(text, selStart, selExtent);

        expect(result.text, equals('line one\nline two'));
        // Two tabs removed, so selExtent decreases by 2.
        expect(result.selStart, equals(0));
        expect(result.selExtent, equals(17));
      },
    );

    test(
      'given_collapsed_caret_when_indent_then_selStart_equals_selExtent_after_unit_length',
      () {
        // Non-list line: unit is '\t' (length 1).
        const text = 'plain text';
        const selStart = 5;
        const selExtent = 5;

        final result = LineIndent.indent(text, selStart, selExtent);

        // Tab prepended at line start; caret was at col 5, now at col 6.
        expect(result.text, equals('\tplain text'));
        expect(result.selStart, equals(6));
        expect(result.selExtent, equals(6));
      },
    );

    test(
      'given_list_line_collapsed_caret_when_indent_then_selection_shifts_by_two',
      () {
        // List line: unit is '  ' (length 2).
        const text = '- item';
        const selStart = 3;
        const selExtent = 3;

        final result = LineIndent.indent(text, selStart, selExtent);

        expect(result.text, equals('  - item'));
        // Caret was at 3; two spaces prepended → now at 5.
        expect(result.selStart, equals(5));
        expect(result.selExtent, equals(5));
      },
    );
  });

  // ─── PER-LINE UNIT: list lines get '  ', non-list get '\t' (FR-11, EC-18) ───

  group('indent per-line unit selection', () {
    test('given_bullet_line_dash_when_indent_then_two_spaces_prepended', () {
      final result = LineIndent.indent('- item', 3, 3);

      expect(
        result.text,
        equals('  - item'),
        reason: 'List line (bullet) must use two-space indent unit',
      );
    });

    test('given_non_list_line_when_indent_then_tab_prepended', () {
      final result = LineIndent.indent('plain text', 2, 2);

      expect(
        result.text,
        equals('\tplain text'),
        reason: 'Non-list line must use tab indent unit',
      );
    });

    test('given_ordered_list_line_when_indent_then_two_spaces_prepended', () {
      final result = LineIndent.indent('1. ordered', 0, 0);

      expect(
        result.text,
        equals('  1. ordered'),
        reason: 'Ordered list line must use two-space indent unit',
      );
    });

    test('given_task_checkbox_line_when_indent_then_two_spaces_prepended', () {
      final result = LineIndent.indent('- [ ] task', 0, 0);

      expect(result.text, equals('  - [ ] task'));
    });

    test('given_checked_task_line_when_indent_then_two_spaces_prepended', () {
      final result = LineIndent.indent('- [x] done', 0, 0);

      expect(result.text, equals('  - [x] done'));
    });

    test('given_plus_bullet_line_when_indent_then_two_spaces_prepended', () {
      final result = LineIndent.indent('+ item', 0, 0);

      expect(result.text, equals('  + item'));
    });

    test(
      'given_asterisk_bullet_line_when_indent_then_two_spaces_prepended',
      () {
        final result = LineIndent.indent('* item', 0, 0);

        expect(result.text, equals('  * item'));
      },
    );
  });

  // ─── MIXED-UNIT MULTI-LINE (EC-18) ───

  group('indent mixed units in multi-line selection', () {
    test(
      'given_list_line_and_non_list_line_when_indent_then_mixed_units_applied',
      () {
        const text = '- list\nplain';
        // selStart = 0, selExtent spans both lines.
        final result = LineIndent.indent(text, 0, text.length);

        expect(
          result.text,
          equals('  - list\n\tplain'),
          reason: 'List line gains two spaces, non-list line gains tab (EC-18)',
        );
      },
    );

    test(
      'given_ordered_and_plain_lines_when_indent_then_two_spaces_and_tab',
      () {
        const text = '1. ordered\nnon-list';
        final result = LineIndent.indent(text, 0, text.length);

        expect(result.text, equals('  1. ordered\n\tnon-list'));
      },
    );
  });

  // ─── ALWAYS ADDS ONE UNIT (FR-11 invariant) ───

  group('indent always adds exactly one unit', () {
    test(
      'given_line_already_indented_with_tab_when_indent_then_second_tab_prepended',
      () {
        final result = LineIndent.indent('\talready', 0, 0);

        expect(
          result.text,
          equals('\t\talready'),
          reason: 'Indent always adds one unit, never skips existing indent',
        );
      },
    );

    test(
      'given_list_line_already_with_two_spaces_when_indent_then_another_two_spaces',
      () {
        final result = LineIndent.indent('  - item', 0, 0);

        expect(result.text, equals('    - item'));
      },
    );
  });

  // ─── SELECTION MODES (FR-11, FR-13) ───

  group('indent selection modes', () {
    test('given_collapsed_caret_when_indent_then_only_caret_line_indented', () {
      const text = 'line one\nline two\nline three';
      // Caret in the middle of line two (offset 13 = 9 + 4).
      final result = LineIndent.indent(text, 13, 13);

      expect(
        result.text,
        equals('line one\n\tline two\nline three'),
        reason:
            'Only the caret line must be indented when selection is collapsed',
      );
    });

    test(
      'given_single_line_selection_when_indent_then_only_that_line_indented',
      () {
        const text = 'line one\nline two\nline three';
        // Selection entirely within line two: offsets 9..17.
        final result = LineIndent.indent(text, 9, 17);

        expect(result.text, equals('line one\n\tline two\nline three'));
      },
    );

    test(
      'given_three_non_empty_lines_selected_when_indent_then_all_three_indented',
      () {
        const text = 'one\ntwo\nthree';
        final result = LineIndent.indent(text, 0, text.length);

        expect(result.text, equals('\tone\n\ttwo\n\tthree'));
      },
    );

    test(
      'given_multi_line_selection_with_blank_line_when_indent_then_blank_line_skipped',
      () {
        const text = 'one\n\nthree';
        final result = LineIndent.indent(text, 0, text.length);

        // 'one' gets '\t', blank line stays blank, 'three' gets '\t'.
        expect(
          result.text,
          equals('\tone\n\n\tthree'),
          reason: 'Blank lines must be skipped in multi-line mode (EC-16)',
        );
      },
    );
  });

  // ─── OUTDENT: remove exactly one leading unit (FR-12, EC-17) ───

  group('outdent removes exactly one leading unit', () {
    test(
      'given_list_line_with_one_two_space_unit_when_outdent_then_unit_removed',
      () {
        final result = LineIndent.outdent('  - item', 0, 8);

        expect(result.text, equals('- item'));
      },
    );

    test('given_non_list_line_with_one_tab_when_outdent_then_tab_removed', () {
      final result = LineIndent.outdent('\tplain', 0, 6);

      expect(result.text, equals('plain'));
    });

    test(
      'given_list_line_with_two_units_when_outdent_then_exactly_one_unit_removed',
      () {
        final result = LineIndent.outdent('    - item', 0, 10);

        expect(
          result.text,
          equals('  - item'),
          reason: 'Only one two-space unit must be removed, not both (FR-12)',
        );
      },
    );
  });

  // ─── OUTDENT NO-OP: column 0 / no leading unit (FR-12, EC-17) ───

  group('outdent no-op cases', () {
    test(
      'given_list_line_at_column_0_with_no_unit_when_outdent_then_no_change',
      () {
        const text = '- item';
        final result = LineIndent.outdent(text, 0, text.length);

        expect(
          result.text,
          equals(text),
          reason: 'Outdent at column 0 must be a no-op (EC-17)',
        );
        expect(result.selStart, equals(0));
        expect(result.selExtent, equals(text.length));
      },
    );

    test(
      'given_line_with_one_space_not_matching_two_space_unit_when_outdent_then_no_change',
      () {
        const text = ' - item';
        final result = LineIndent.outdent(text, 0, text.length);

        expect(
          result.text,
          equals(text),
          reason:
              'One space does not match the two-space unit — must not strip (EC-17)',
        );
      },
    );

    test('given_non_list_line_with_one_space_when_outdent_then_no_change', () {
      const text = ' plain';
      final result = LineIndent.outdent(text, 0, text.length);

      expect(
        result.text,
        equals(text),
        reason: 'Single space is not a valid unit — outdent is no-op',
      );
    });

    test('given_non_list_line_at_column_0_when_outdent_then_no_change', () {
      const text = 'plain';
      final result = LineIndent.outdent(text, 0, text.length);

      expect(result.text, equals(text));
    });
  });

  // ─── TOTALITY: must not throw at boundary offsets ───

  group('totality at boundary offsets', () {
    test('given_empty_text_when_indent_then_returns_without_throwing', () {
      expect(() => LineIndent.indent('', 0, 0), returnsNormally);
    });

    test('given_empty_text_when_outdent_then_returns_without_throwing', () {
      expect(() => LineIndent.outdent('', 0, 0), returnsNormally);
    });

    test(
      'given_single_line_text_when_indent_with_caret_at_end_then_returns_without_throwing',
      () {
        const text = 'plain';
        expect(
          () => LineIndent.indent(text, text.length, text.length),
          returnsNormally,
        );
      },
    );

    test(
      'given_multi_line_text_when_indent_with_full_span_selection_then_returns_without_throwing',
      () {
        const text = 'a\nb\nc';
        expect(() => LineIndent.indent(text, 0, text.length), returnsNormally);
      },
    );
  });

  // ─── INDENTRESULT IS @immutable VALUE OBJECT ───

  group('IndentResult value object', () {
    test(
      'given_indent_result_when_inspecting_fields_then_text_selStart_selExtent_present',
      () {
        final result = LineIndent.indent('plain', 0, 0);

        expect(result.text, isA<String>());
        expect(result.selStart, isA<int>());
        expect(result.selExtent, isA<int>());
      },
    );
  });
}
