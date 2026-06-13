// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/editor/list_continuation.dart';

void main() {
  // =========================================================================
  // HIGH-RISK GRAMMAR BRANCHES — checked→unchecked, leading-whitespace,
  // closed bullet set, numeric +1 / multi-digit, alpha case+delimiter,
  // alpha ceiling→null, calculateOrderedIndex floors.
  // =========================================================================

  group('bullet grammar', () {
    group('checked task → unchecked continuation (EC-03)', () {
      test(
        'given_checkedTaskLine_when_process_then_continuesAsUncheckedAndCaretAfterToken',
        () {
          final fullText = '- [x] buy milk';
          final caretOffset = fullText.length; // EOL
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          expect(result!.text, contains('\n- [ ] '));
          // caret-invariant: the 6 chars before caret == '- [ ] '
          final token = '- [ ] ';
          expect(
            result.text.substring(result.caret - token.length, result.caret),
            equals(token),
          );
        },
      );
    });

    group('unchecked task → unchecked continuation', () {
      test(
        'given_uncheckedTaskLine_when_process_then_continuesAsUnchecked',
        () {
          final fullText = '- [ ] x';
          final caretOffset = fullText.length;
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          final token = '- [ ] ';
          expect(
            result!.text.substring(result.caret - token.length, result.caret),
            equals(token),
          );
        },
      );
    });

    group('leading-whitespace preserved verbatim (EC-04)', () {
      test(
        'given_twoSpaceIndentedStarBullet_when_process_then_preservesLeadingSpaces',
        () {
          final fullText = '  * item';
          final caretOffset = fullText.length;
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          expect(result!.text, contains('\n  * '));
          final token = '  * ';
          expect(
            result.text.substring(result.caret - token.length, result.caret),
            equals(token),
          );
        },
      );
    });

    group('closed bullet set — dash bullet', () {
      test('given_dashBulletLine_when_process_then_continuesWithSameToken', () {
        final fullText = '- x';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        final token = '- ';
        expect(
          result!.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      });
    });

    group('closed bullet set — plus bullet', () {
      test('given_plusBulletLine_when_process_then_continuesWithPlusToken', () {
        final fullText = '+ x';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        final token = '+ ';
        expect(
          result!.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      });
    });

    group('closed bullet set — star bullet', () {
      test('given_starBulletLine_when_process_then_continuesWithStarToken', () {
        final fullText = '* x';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        final token = '* ';
        expect(
          result!.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      });
    });
  });

  // =========================================================================
  // ORDERED GRAMMAR — numeric +1, multi-digit, alpha case+delimiter,
  // alpha ceiling→null.
  // =========================================================================

  group('ordered grammar', () {
    group('numeric +1', () {
      test(
        'given_singleDigitOrderedLine_when_process_then_incrementsToNextNumber',
        () {
          final fullText = '1. first';
          final caretOffset = fullText.length;
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          expect(result!.text, contains('\n2. '));
        },
      );
    });

    group('multi-digit numeric', () {
      test('given_nineOrderedLine_when_process_then_incrementsToTen', () {
        final fullText = '9. item';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        expect(result!.text, contains('\n10. '));
      });
    });

    group('alpha lowercase with dot delimiter (EC-07 lowercase)', () {
      test(
        'given_lowerAlphaDotLine_when_process_then_incrementsAlphaPreservingCase',
        () {
          final fullText = 'a. first';
          final caretOffset = fullText.length;
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          expect(result!.text, contains('\nb. '));
        },
      );
    });

    group('alpha uppercase with parenthesis delimiter (EC-07)', () {
      test(
        'given_upperAlphaParenLine_when_process_then_incrementsAlphaPreservingCaseAndDelimiter',
        () {
          final fullText = 'A) alpha';
          final caretOffset = fullText.length;
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          expect(result!.text, contains('\nB) '));
        },
      );
    });

    group('alpha ceiling — lowercase z (EC-05)', () {
      test('given_zLowerOrderedLine_when_process_then_returnsNullListEnds', () {
        final fullText = 'z. last';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNull);
      });
    });

    group('alpha ceiling — uppercase Z (EC-05)', () {
      test('given_zUpperOrderedLine_when_process_then_returnsNullListEnds', () {
        final fullText = 'Z. LAST';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNull);
      });
    });
  });

  // =========================================================================
  // calculateOrderedIndex — floor / ceiling invariants
  // =========================================================================

  group('calculateOrderedIndex', () {
    test('given_zeroIndex_when_incrementUp_then_returnsOne', () {
      // "0" is not a valid ordered-list index in practice, but the numeric
      // path adds direction; +1 from 0 = 1 which is > 0, so returns "1".
      expect(ListContinuation.calculateOrderedIndex('0', 1), equals('1'));
    });

    test('given_oneIndex_when_decrementDown_then_returnsNullFloorAtOne', () {
      expect(ListContinuation.calculateOrderedIndex('1', -1), isNull);
    });

    test('given_lowerAIndex_when_decrementDown_then_returnsNull', () {
      expect(ListContinuation.calculateOrderedIndex('a', -1), isNull);
    });

    test('given_upperAIndex_when_decrementDown_then_returnsNull', () {
      expect(ListContinuation.calculateOrderedIndex('A', -1), isNull);
    });
  });

  // =========================================================================
  // EMPTY-ITEM-ENDS-LIST — both list kinds (EC-08)
  // =========================================================================

  group('empty-item-ends-list', () {
    group('numeric ordered — empty second item (EC-08)', () {
      test(
        'given_firstLineThenEmptySecondMarker_when_process_then_removesMarkerInsertsPlainNewline',
        () {
          // "1. first\n2. " — caret after "2. " (at position 12)
          final fullText = '1. first\n2. ';
          final caretOffset = fullText.length; // caret at end of "2. "
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          // The empty "2. " line is removed; result should contain "1. first\n"
          // and the caret sits at the start of the new plain line.
          expect(result!.text, equals('1. first\n'));
          expect(result.caret, equals('1. first\n'.length));
        },
      );
    });

    group('bullet — empty dash item', () {
      test(
        'given_bulletLineThenEmptyBulletMarker_when_process_then_removesMarkerInsertsPlainNewline',
        () {
          // "- item\n- " — caret at end of the empty "- " (position 9)
          final fullText = '- item\n- ';
          final caretOffset = fullText.length;
          final result = ListContinuation.process(fullText, caretOffset);
          expect(result, isNotNull);
          expect(result!.text, equals('- item\n'));
          expect(result.caret, equals('- item\n'.length));
        },
      );
    });
  });

  // =========================================================================
  // LONE-MARKER-CONTINUES (EC-09) — no real list above, guard fails
  // =========================================================================

  group('lone-marker continues rather than terminates', () {
    test(
      'given_loneNumericMarkerOnFirstLine_when_process_then_continuesRatherThanTerminates',
      () {
        // "1. " — lone first line, no list above
        final fullText = '1. ';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        expect(result!.text, contains('\n2. '));
      },
    );

    test(
      'given_loneBulletMarkerOnFirstLine_when_process_then_continuesRatherThanTerminates',
      () {
        // "- " — lone first line
        final fullText = '- ';
        final caretOffset = fullText.length;
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        final token = '- ';
        expect(
          result!.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      },
    );
  });

  // =========================================================================
  // ALREADY-CONTINUES GUARD (EC-10)
  // =========================================================================

  group('already-continues guard', () {
    test('given_caretToEolAlreadyMatchesBullet_when_process_then_returnsNull', () {
      // fullText "- item\n- next", caret at the \n (offset 6)
      // caret-to-EOL = "- next" is NOT a bullet item without the trailing
      // space. Let's use a line where caret is at the \n and after it is
      // an already-started bullet item on the SAME line.
      // Per spec: "text from caretOffset to end-of-current-line already
      // matches a bullet item" → return null.
      // Scenario: buffer = "- start\n- continues here"
      //   caret is in the first line (just before the \n at offset 7),
      //   but caret-to-EOL of the CURRENT line after \n would be "- continues here".
      // Actually, according to the canon the guard checks caret-to-end-of-current-line
      // after the newline is being inserted. The "current line" is the one containing
      // the caret BEFORE the newline fires.
      // The guard fires when caret-to-EOL of the current line (from caretOffset to
      // the next \n or end-of-text) already matches a bullet.
      // Example: "- item\n- next" — if caret is placed at the start of "- next"
      // (offset 7), the line is "- next" and caret-to-EOL = "- next" which starts
      // a bullet. So process should return null (no double marker).
      final fullText = '- item\n- next';
      final caretOffset = 7; // caret at the start of "- next" line
      final result = ListContinuation.process(fullText, caretOffset);
      expect(result, isNull);
    });

    test('given_caretToEolIsPlainText_when_process_then_normalContinuation', () {
      // caret-to-EOL is plain "item" → normal "- " continuation
      final fullText = '- item';
      final caretOffset =
          2; // caret after "- ", so previous_line is "- ", caret-to-EOL is "item"
      final result = ListContinuation.process(fullText, caretOffset);
      expect(result, isNotNull);
    });
  });

  // =========================================================================
  // TOTALITY — no throw at offset 0, at length, or on empty string (FR-09)
  // =========================================================================

  group('totality', () {
    test('given_emptyString_when_processAtOffset0_then_returnsNull', () {
      expect(() => ListContinuation.process('', 0), returnsNormally);
      expect(ListContinuation.process('', 0), isNull);
    });

    test('given_nonListLine_when_processAtLength_then_returnsNullNoThrow', () {
      final fullText = 'hello world';
      expect(
        () => ListContinuation.process(fullText, fullText.length),
        returnsNormally,
      );
      expect(ListContinuation.process(fullText, fullText.length), isNull);
    });

    test('given_listLineAtEot_when_process_then_returnsValidResult', () {
      final fullText = '- last';
      expect(
        () => ListContinuation.process(fullText, fullText.length),
        returnsNormally,
      );
      expect(ListContinuation.process(fullText, fullText.length), isNotNull);
    });

    test(
      'given_nonEmptyText_when_processAtOffset0_then_returnsNullNoThrow',
      () {
        final fullText = '- item';
        // caret at offset 0 means previous_line is empty — no list match
        expect(() => ListContinuation.process(fullText, 0), returnsNormally);
        expect(ListContinuation.process(fullText, 0), isNull);
      },
    );
  });

  // =========================================================================
  // CARET INVARIANT — newText.substring(caret-token.length, caret) == token
  // =========================================================================

  group('caret invariant', () {
    test(
      'given_uncheckedTaskBullet_when_process_then_caretImmediatelyAfterToken',
      () {
        final fullText = '- [ ] task';
        final result = ListContinuation.process(fullText, fullText.length)!;
        const token = '- [ ] ';
        expect(
          result.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      },
    );

    test(
      'given_orderedNumericLine_when_process_then_caretImmediatelyAfterInsertedMarker',
      () {
        final fullText = '3. item';
        final result = ListContinuation.process(fullText, fullText.length)!;
        const token = '4. ';
        expect(
          result.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      },
    );

    test(
      'given_alphaOrderedLine_when_process_then_caretImmediatelyAfterInsertedMarker',
      () {
        final fullText = 'b) item';
        final result = ListContinuation.process(fullText, fullText.length)!;
        const token = 'c) ';
        expect(
          result.text.substring(result.caret - token.length, result.caret),
          equals(token),
        );
      },
    );
  });

  // =========================================================================
  // MULTI-LINE BUFFER — caret within first line, second line below
  // =========================================================================

  group('multi-line buffer — caret on first line', () {
    test(
      'given_multiLineBuffer_when_caretAtEndOfFirstListLine_then_continuesFirstLine',
      () {
        // "- first\nsecond" — caret at end of "- first" (offset 7)
        final fullText = '- first\nsecond';
        final caretOffset = 7; // end of "- first"
        final result = ListContinuation.process(fullText, caretOffset);
        expect(result, isNotNull);
        // result.text should insert "\n- " between "- first" and "second"
        expect(result!.text, startsWith('- first\n- '));
      },
    );
  });
}
