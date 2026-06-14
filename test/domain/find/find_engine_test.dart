import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/find/find_engine.dart';

void main() {
  // ===========================================================================
  // MatchSpan — value type contract
  // ===========================================================================

  group('MatchSpan value equality', () {
    test(
      'given_twoMatchSpansWithSameStartAndEnd_when_equalityChecked_then_equalAndSameHashCode',
      () {
        const a = MatchSpan(3, 7);
        const b = MatchSpan(3, 7);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      },
    );

    test(
      'given_twoMatchSpansWithDifferentValues_when_equalityChecked_then_notEqual',
      () {
        const a = MatchSpan(3, 7);
        const b = MatchSpan(3, 8);
        expect(a, isNot(equals(b)));
      },
    );
  });

  // ===========================================================================
  // FindEngine.findMatches — happy path
  // ===========================================================================

  group('FindEngine.findMatches happy path', () {
    test(
      'given_textWithThreeOccurrencesOfQuery_when_findMatches_then_returnsThreeSpansInDocumentOrder',
      () {
        // "The cat sat on the mat" — "at" inside cat(@5), sat(@9), mat(word@19,
        // so the "at" substring starts at 20: m=19, a=20, t=21).
        const text = 'The cat sat on the mat';
        final spans = FindEngine.findMatches(text, 'at');
        expect(spans.length, equals(3));
        expect(spans[0].start, equals(5));
        expect(spans[0].end, equals(7));
        expect(spans[1].start, equals(9));
        expect(spans[1].end, equals(11));
        expect(spans[2].start, equals(20));
        expect(spans[2].end, equals(22));
      },
    );

    test(
      'given_textWithMixedCaseOccurrences_when_findMatchesCaseInsensitive_then_returnsThreeSpans',
      () {
        // "Hello HELLO hello" starts: 0, 6, 12 — all match "hello"
        const text = 'Hello HELLO hello';
        final spans = FindEngine.findMatches(text, 'hello');
        expect(spans.length, equals(3));
        expect(spans[0].start, equals(0));
        expect(spans[1].start, equals(6));
        expect(spans[2].start, equals(12));
      },
    );

    test(
      'given_textWithTwoNonOverlappingOccurrences_when_findMatches_then_returnsTwoNonOverlappingSpans',
      () {
        // "abcabc" — two "abc" matches at 0 and 3; search resumes at end
        const text = 'abcabc';
        final spans = FindEngine.findMatches(text, 'abc');
        expect(spans.length, equals(2));
        expect(spans[0].start, equals(0));
        expect(spans[0].end, equals(3));
        expect(spans[1].start, equals(3));
        expect(spans[1].end, equals(6));
      },
    );

    test(
      'given_overlappingFamily_when_findMatches_then_returnsExactlyOneSpanAtStart',
      () {
        // "aaa" / "aa" — match at 0→2, resume at 2; "a" alone is not "aa"
        const text = 'aaa';
        final spans = FindEngine.findMatches(text, 'aa');
        expect(spans.length, equals(1));
        expect(spans[0].start, equals(0));
        expect(spans[0].end, equals(2));
      },
    );

    test('given_mixedCaseQuery_when_findMatches_then_queryIsAlsoFolded', () {
      // "fooFOOfoo" / "FOO" — query is case-folded too, so 3 matches
      const text = 'fooFOOfoo';
      final spans = FindEngine.findMatches(text, 'FOO');
      expect(spans.length, equals(3));
    });

    test(
      'given_textWithEmojiSurrogatePair_when_findMatchesByteAfterEmoji_then_startIsCorrectUtf16Offset',
      () {
        // "hi 😀 bye": 'h'=0,'i'=1,' '=2, '😀'=3+4 (surrogate pair = 2 UTF-16 units),
        // ' '=5, 'b'=6, 'y'=7, 'e'=8 → "bye" starts at offset 6
        const text = 'hi 😀 bye';
        final spans = FindEngine.findMatches(text, 'bye');
        expect(spans.length, equals(1));
        // The emoji occupies 2 UTF-16 code units (surrogate pair).
        // Dart string offsets: h=0, i=1, ' '=2, high-surrogate=3, low-surrogate=4,
        // ' '=5, b=6, y=7, e=8.
        expect(spans[0].start, equals(6));
        expect(spans[0].end, equals(9));
      },
    );

    test(
      'given_textWithNonAsciiCharacter_when_findMatchesNonAsciiQuery_then_returnsCorrectSpan',
      () {
        // "café" / "é" — non-ASCII; 'c'=0,'a'=1,'f'=2,'é'=3 (single UTF-16 unit)
        const text = 'café';
        final spans = FindEngine.findMatches(text, 'é');
        expect(spans.length, equals(1));
        expect(spans[0].start, equals(3));
        expect(spans[0].end, equals(4));
      },
    );

    test(
      'given_nonEmptyResultList_when_findMatches_then_spansAreNonOverlappingAndOrdered',
      () {
        // Invariant: start < end for every span; spans[i].end <= spans[i+1].start
        const text = 'The cat sat on the mat';
        final spans = FindEngine.findMatches(text, 'at');
        for (final s in spans) {
          expect(s.start, lessThan(s.end));
        }
        for (var i = 0; i < spans.length - 1; i++) {
          expect(spans[i].end, lessThanOrEqualTo(spans[i + 1].start));
        }
      },
    );
  });

  // ===========================================================================
  // FindEngine.findMatches — degenerate / empty inputs
  // ===========================================================================

  group('FindEngine.findMatches degenerate inputs', () {
    test(
      'given_nonEmptyTextAndEmptyQuery_when_findMatches_then_returnsEmptyList',
      () {
        final spans = FindEngine.findMatches('hello world', '');
        expect(spans, isEmpty);
      },
    );

    test(
      'given_emptyTextAndNonEmptyQuery_when_findMatches_then_returnsEmptyList',
      () {
        final spans = FindEngine.findMatches('', 'hello');
        expect(spans, isEmpty);
      },
    );

    test(
      'given_queryLongerThanText_when_findMatches_then_returnsEmptyListNoError',
      () {
        final spans = FindEngine.findMatches('hi', 'hello world');
        expect(spans, isEmpty);
      },
    );

    test(
      'given_queryExactlyLongerThanText_when_findMatches_then_returnsEmptyList',
      () {
        final spans = FindEngine.findMatches('hello', 'hello world');
        expect(spans, isEmpty);
      },
    );
  });

  // ===========================================================================
  // FindEngine.autoSelectIndex — happy path
  // ===========================================================================

  group('FindEngine.autoSelectIndex happy path', () {
    // spans with starts [2, 10, 30]
    final spans = [MatchSpan(2, 5), MatchSpan(10, 13), MatchSpan(30, 33)];

    test(
      'given_matchListAndEntryOffsetBetweenSecondAndThird_when_autoSelectIndex_then_returnsThirdIndex',
      () {
        // entryOffset=11 → first match at/after 11 is MatchSpan(30,..) at index 2
        expect(FindEngine.autoSelectIndex(spans, 11), equals(2));
      },
    );

    test(
      'given_matchListAndEntryOffsetExactlyAtFirstMatchStart_when_autoSelectIndex_then_returnsZero',
      () {
        // entryOffset=2 → exact match at/after 2 is index 0
        expect(FindEngine.autoSelectIndex(spans, 2), equals(0));
      },
    );

    test(
      'given_matchListAndEntryOffsetPastAllMatches_when_autoSelectIndex_then_wrapsToZero',
      () {
        // entryOffset=40 → no match at/after 40 → wrap to 0
        expect(FindEngine.autoSelectIndex(spans, 40), equals(0));
      },
    );

    test(
      'given_matchListAndEntryOffsetPastLastMatchStart_when_autoSelectIndex_then_wrapsToZero',
      () {
        // entryOffset=31 → all starts (2,10,30) are < 31 → wrap to 0
        expect(FindEngine.autoSelectIndex(spans, 31), equals(0));
      },
    );

    test(
      'given_singleMatchAndEntryOffsetAtMatchStart_when_autoSelectIndex_then_returnsZero',
      () {
        // single element start=5, entryOffset=5 → at boundary → 0
        final single = [MatchSpan(5, 8)];
        expect(FindEngine.autoSelectIndex(single, 5), equals(0));
      },
    );

    test(
      'given_singleMatchAndEntryOffsetAfterMatchStart_when_autoSelectIndex_then_wrapsToZero',
      () {
        // single element start=5, entryOffset=6 → only match is before offset → wrap to 0
        final single = [MatchSpan(5, 8)];
        expect(FindEngine.autoSelectIndex(single, 6), equals(0));
      },
    );

    test(
      'given_nonEmptyMatchListAndEntryOffsetZero_when_autoSelectIndex_then_returnsZero',
      () {
        // entryOffset=0 → first match is always at/after 0 → index 0
        expect(FindEngine.autoSelectIndex(spans, 0), equals(0));
      },
    );
  });

  // ===========================================================================
  // FindEngine.autoSelectIndex — degenerate inputs
  // ===========================================================================

  group('FindEngine.autoSelectIndex degenerate inputs', () {
    test(
      'given_emptyMatchListAndAnyOffset_when_autoSelectIndex_then_returnsNull',
      () {
        expect(FindEngine.autoSelectIndex([], 5), isNull);
        expect(FindEngine.autoSelectIndex([], 0), isNull);
      },
    );

    test(
      'given_entryOffsetBelowZero_when_autoSelectIndex_then_doesNotThrowAndReturnsValidResult',
      () {
        final spans = [MatchSpan(2, 5), MatchSpan(10, 13)];
        // defensive clamp: must not throw; returns a valid index or null
        expect(() => FindEngine.autoSelectIndex(spans, -1), returnsNormally);
        final result = FindEngine.autoSelectIndex(spans, -1);
        expect(result, anyOf(isNull, isA<int>()));
      },
    );

    test(
      'given_entryOffsetEqualToTextLength_when_autoSelectIndex_then_wrapsToZeroOrNullWhenNoMatches',
      () {
        // one-past-end offset treats as past-last-match
        const textLength = 20;
        final spans = [MatchSpan(2, 5), MatchSpan(10, 13)];
        // all matches start before textLength=20 → wrap to 0
        expect(FindEngine.autoSelectIndex(spans, textLength), equals(0));

        // empty list → null regardless
        expect(FindEngine.autoSelectIndex([], textLength), isNull);
      },
    );
  });

  // ===========================================================================
  // FindEngine.replaceRange — happy path
  // ===========================================================================

  group('FindEngine.replaceRange happy path', () {
    test(
      'given_textAndMatchInMiddle_when_replaceRange_then_returnsCorrectTextAndCaretOffset',
      () {
        // "foo bar foo", MatchSpan(8,11), "baz" → "foo bar baz", caret=11
        const text = 'foo bar foo';
        const match = MatchSpan(8, 11);
        final result = FindEngine.replaceRange(text, match, 'baz');
        expect(result.text, equals('foo bar baz'));
        expect(result.nextCaretOffset, equals(11)); // 8 + 3
      },
    );

    test(
      'given_textAndMatchOverFullText_when_replaceRange_then_returnsReplacementAndCaretAtEnd',
      () {
        // "hello", MatchSpan(0,5), "world" → "world", caret=5
        const text = 'hello';
        const match = MatchSpan(0, 5);
        final result = FindEngine.replaceRange(text, match, 'world');
        expect(result.text, equals('world'));
        expect(result.nextCaretOffset, equals(5));
      },
    );

    test(
      'given_replacementLongerThanMatchSpan_when_replaceRange_then_textIsLongerAndCaretCorrect',
      () {
        // "abc", MatchSpan(1,2), "XYZ" → "aXYZc", caret = 1+3 = 4
        const text = 'abc';
        const match = MatchSpan(1, 2);
        final result = FindEngine.replaceRange(text, match, 'XYZ');
        expect(result.text, equals('aXYZc'));
        expect(result.text.length, greaterThan(text.length));
        expect(result.nextCaretOffset, equals(4));
      },
    );

    test(
      'given_replacementShorterThanMatchSpan_when_replaceRange_then_textIsShorterAndCaretCorrect',
      () {
        // "abcde", MatchSpan(1,4), "X" → "aXe", caret = 1+1 = 2
        const text = 'abcde';
        const match = MatchSpan(1, 4);
        final result = FindEngine.replaceRange(text, match, 'X');
        expect(result.text, equals('aXe'));
        expect(result.text.length, lessThan(text.length));
        expect(result.nextCaretOffset, equals(2));
      },
    );
  });

  // ===========================================================================
  // FindEngine.replaceRange — degenerate inputs
  // ===========================================================================

  group('FindEngine.replaceRange degenerate inputs', () {
    test(
      'given_emptyReplacement_when_replaceRange_then_deletesMatchSpanAndCaretAtMatchStart',
      () {
        // EC-13: empty replacement deletes the match span; caret at match.start
        const text = 'hello world';
        const match = MatchSpan(5, 11); // " world"
        final result = FindEngine.replaceRange(text, match, '');
        expect(result.text, equals('hello'));
        expect(result.nextCaretOffset, equals(5)); // match.start
      },
    );

    test(
      'given_matchAtStartOfText_when_replaceRangeWithLongerReplacement_then_returnsCorrectResult',
      () {
        // "abc", MatchSpan(0,1), "XY" → "XYbc", caret=2
        const text = 'abc';
        const match = MatchSpan(0, 1);
        final result = FindEngine.replaceRange(text, match, 'XY');
        expect(result.text, equals('XYbc'));
        expect(result.nextCaretOffset, equals(2));
      },
    );

    test(
      'given_matchAtEndOfText_when_replaceRange_then_returnsCorrectResult',
      () {
        // "abc", MatchSpan(2,3), "Z" → "abZ", caret=3
        const text = 'abc';
        const match = MatchSpan(2, 3);
        final result = FindEngine.replaceRange(text, match, 'Z');
        expect(result.text, equals('abZ'));
        expect(result.nextCaretOffset, equals(3));
      },
    );
  });

  // ===========================================================================
  // findMatchesIsolate — top-level isolate entry point parity
  // ===========================================================================

  group('findMatchesIsolate isolate entry point', () {
    test(
      'given_validArgs_when_findMatchesIsolate_then_returnsSameResultAsFindEngineDirectly',
      () {
        // FR-08: top-level entry point must delegate faithfully to FindEngine.findMatches
        const text = 'hello world';
        const query = 'world';
        final FindArgs args = (text: text, query: query);
        final isolateResult = findMatchesIsolate(args);
        final directResult = FindEngine.findMatches(text, query);
        expect(isolateResult.length, equals(directResult.length));
        for (var i = 0; i < isolateResult.length; i++) {
          expect(isolateResult[i], equals(directResult[i]));
        }
      },
    );

    test('given_emptyQuery_when_findMatchesIsolate_then_returnsEmptyList', () {
      // EC-02: empty-query guard is honoured through the isolate path
      const FindArgs args = (text: 'some text', query: '');
      expect(findMatchesIsolate(args), isEmpty);
    });
  });

  // ===========================================================================
  // kFindIsolateThreshold — named constant exposed
  // ===========================================================================

  group('kFindIsolateThreshold constant', () {
    test(
      'given_kFindIsolateThreshold_when_inspected_then_equalsExpectedValue',
      () {
        expect(kFindIsolateThreshold, equals(10000));
      },
    );
  });
}
