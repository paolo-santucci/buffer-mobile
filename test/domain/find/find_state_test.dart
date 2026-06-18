// ignore_for_file: prefer_const_constructors
import 'package:foglietto/domain/find/find_engine.dart';
import 'package:foglietto/domain/find/find_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FindState', () {
    group('default factory', () {
      test('given_noArguments_when_defaultCtor_then_queryIsEmptyString', () {
        final state = FindState();
        expect(state.query, '');
      });

      test(
        'given_noArguments_when_defaultCtor_then_replaceTermIsEmptyString',
        () {
          final state = FindState();
          expect(state.replaceTerm, '');
        },
      );

      test('given_noArguments_when_defaultCtor_then_matchesIsEmptyList', () {
        final state = FindState();
        expect(state.matches, isEmpty);
      });

      test(
        'given_noArguments_when_defaultCtor_then_currentMatchIndexIsNull',
        () {
          final state = FindState();
          expect(state.currentMatchIndex, isNull);
        },
      );

      test('given_noArguments_when_defaultCtor_then_activeIsFalse', () {
        final state = FindState();
        expect(state.active, isFalse);
      });
    });

    group('count getter', () {
      test('given_emptyMatches_when_count_then_returnsZero', () {
        final state = FindState();
        expect(state.count, 0);
      });

      test('given_twoMatches_when_count_then_returnsTwo', () {
        final state = FindState(matches: [MatchSpan(0, 3), MatchSpan(4, 7)]);
        expect(state.count, 2);
      });

      test('given_matches_when_count_then_equalsMatchesLength', () {
        final matches = [MatchSpan(0, 2), MatchSpan(5, 7), MatchSpan(10, 12)];
        final state = FindState(matches: matches);
        expect(state.count, equals(matches.length));
      });
    });

    group('hasCurrent getter', () {
      test('given_currentMatchIndexNull_when_hasCurrent_then_returnsFalse', () {
        final state = FindState();
        expect(state.hasCurrent, isFalse);
      });

      test(
        'given_currentMatchIndexNonNull_when_hasCurrent_then_returnsTrue',
        () {
          final state = FindState(
            matches: [MatchSpan(0, 3)],
            currentMatchIndex: 0,
          );
          expect(state.hasCurrent, isTrue);
        },
      );
    });

    group('position getter', () {
      test('given_currentMatchIndexNull_when_position_then_returnsNull', () {
        final state = FindState();
        expect(state.position, isNull);
      });

      test('given_currentMatchIndexZero_when_position_then_returnsOne', () {
        final state = FindState(
          matches: [MatchSpan(0, 3), MatchSpan(5, 8)],
          currentMatchIndex: 0,
        );
        expect(state.position, 1);
      });

      test('given_currentMatchIndexTwo_when_position_then_returnsThree', () {
        final state = FindState(
          matches: [MatchSpan(0, 2), MatchSpan(5, 7), MatchSpan(10, 12)],
          currentMatchIndex: 2,
        );
        expect(state.position, 3);
      });
    });

    group('currentMatch getter', () {
      test(
        'given_currentMatchIndexNull_when_currentMatch_then_returnsNull',
        () {
          final state = FindState(matches: [MatchSpan(0, 3)]);
          expect(state.currentMatch, isNull);
        },
      );

      test(
        'given_validCurrentMatchIndex_when_currentMatch_then_returnsCorrectSpan',
        () {
          final span = MatchSpan(5, 8);
          final state = FindState(
            matches: [MatchSpan(0, 3), span],
            currentMatchIndex: 1,
          );
          expect(state.currentMatch, equals(span));
        },
      );

      test(
        'given_outOfRangeCurrentMatchIndex_when_currentMatch_then_returnsNullWithoutThrow',
        () {
          // currentMatchIndex points beyond the matches list — no throw (null-safe).
          final state = FindState(
            matches: [MatchSpan(0, 3)],
            currentMatchIndex: 5,
          );
          expect(() => state.currentMatch, returnsNormally);
          expect(state.currentMatch, isNull);
        },
      );

      test(
        'given_emptyMatchesWithNonNullIndex_when_currentMatch_then_returnsNullWithoutThrow',
        () {
          final state = FindState(matches: [], currentMatchIndex: 0);
          expect(() => state.currentMatch, returnsNormally);
          expect(state.currentMatch, isNull);
        },
      );
    });

    group('copyWith', () {
      test('given_state_when_copyWithQuery_then_onlyQueryChanges', () {
        final original = FindState(
          matches: [MatchSpan(0, 3)],
          currentMatchIndex: 0,
          active: true,
        );
        final copy = original.copyWith(query: 'hello');
        expect(copy.query, 'hello');
        expect(copy.replaceTerm, original.replaceTerm);
        expect(copy.matches, equals(original.matches));
        expect(copy.currentMatchIndex, original.currentMatchIndex);
        expect(copy.active, original.active);
      });

      test('given_state_when_copyWithActive_then_onlyActiveChanges', () {
        final original = FindState(query: 'foo', active: false);
        final copy = original.copyWith(active: true);
        expect(copy.active, isTrue);
        expect(copy.query, original.query);
        expect(copy.currentMatchIndex, original.currentMatchIndex);
      });

      test(
        'given_state_when_copyWithCurrentMatchIndex_then_onlyIndexChanges',
        () {
          final original = FindState(
            matches: [MatchSpan(0, 3), MatchSpan(5, 8)],
            currentMatchIndex: 0,
          );
          final copy = original.copyWith(currentMatchIndex: 1);
          expect(copy.currentMatchIndex, 1);
          expect(copy.matches, equals(original.matches));
          expect(copy.query, original.query);
        },
      );
    });

    group('value equality (freezed)', () {
      test(
        'given_twoStatesWithIdenticalFields_when_equality_then_areEqual',
        () {
          final a = FindState(
            query: 'foo',
            replaceTerm: 'bar',
            matches: [MatchSpan(0, 3)],
            currentMatchIndex: 0,
            active: true,
          );
          final b = FindState(
            query: 'foo',
            replaceTerm: 'bar',
            matches: [MatchSpan(0, 3)],
            currentMatchIndex: 0,
            active: true,
          );
          expect(a, equals(b));
        },
      );

      test(
        'given_twoStatesWithDifferentQuery_when_equality_then_areNotEqual',
        () {
          final a = FindState(query: 'foo');
          final b = FindState(query: 'bar');
          expect(a, isNot(equals(b)));
        },
      );

      test('given_twoDefaultStates_when_equality_then_areEqual', () {
        final a = FindState();
        final b = FindState();
        expect(a, equals(b));
      });
    });
  });
}
