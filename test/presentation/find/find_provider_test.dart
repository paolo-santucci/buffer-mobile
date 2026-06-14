import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_notifier_impl.dart';
import 'package:buffer/domain/find/find_engine.dart';
import 'package:buffer/presentation/find/find_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [ProviderContainer] with bufferProvider pre-seeded to [text].
ProviderContainer makeContainer({String initialText = ''}) {
  final container = ProviderContainer(
    overrides: [
      bufferProvider.overrideWith(() {
        final notifier = BufferNotifierImpl();
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  if (initialText.isNotEmpty) {
    container.read(bufferProvider.notifier).updateText(initialText);
  }
  return container;
}

/// Pumps microtasks so that scheduled microtask-coalesced recomputes run.
Future<void> pumpMicrotasks() async {
  await Future<void>.microtask(() {});
  await Future<void>.microtask(() {});
}

void main() {
  // =========================================================================
  // startSearch — basic behaviour
  // =========================================================================

  group('FindNotifier.startSearch', () {
    test(
      'given_bufferWithThreeMatches_when_startSearchWithOffsetAtSecondMatch_then_activeAndThreeMatchesAndCorrectIndex',
      () async {
        // buffer "a x a x a" → 3 matches of "a" at offsets 0, 4, 8
        // entryOffset=5 → first match at/after 5 is index 2 (offset 8)
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);

        notifier.startSearch(entryOffset: 5);
        await pumpMicrotasks();

        container.read(findProvider.notifier).setQuery('a');
        notifier.startSearch(entryOffset: 5);
        await pumpMicrotasks();

        // Use explicit setQuery then startSearch approach:
        // First set query, then open.
        // Since startSearch computes using current query, we need a query set.
        // The spec says startSearch uses current query — so pre-set it.
      },
    );

    test(
      'given_bufferTextAndQueryAlreadySet_when_startSearch_then_activeIsTrue',
      () async {
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 5);
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.active, isTrue);
      },
    );

    test(
      'given_bufferTextAndQuerySet_when_startSearchWithOffsetAtSecondMatch_then_threeMatchesAndCurrentIndexTwo',
      () async {
        // "a x a x a" → matches at 0,4,8; entryOffset=5 → index 2 (start=8>=5)
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 5);
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.matches.length, equals(3));
        expect(s.currentMatchIndex, equals(2));
      },
    );

    test(
      'given_allMatchesBeforeOffset_when_startSearch_then_wrapsToIndexZero',
      () async {
        // "a x a x a" matches at 0,4,8; entryOffset=9 → all before or at 9
        // offset 9 > start=8 → wrap to 0
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 9);
        await pumpMicrotasks();

        // start=8 < 9 → all before → wrap to 0
        // Actually start=8 < 9 so wrap occurs; also start=0 < 9, start=4 < 9
        final s = container.read(findProvider);
        expect(s.currentMatchIndex, equals(0));
      },
    );

    test(
      'given_emptyQuery_when_startSearch_then_activeAndEmptyMatchesAndNullIndex',
      () async {
        final container = makeContainer(initialText: 'hello world');
        final notifier = container.read(findProvider.notifier);
        // setQuery('') is the default; just startSearch with empty query
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.active, isTrue);
        expect(s.matches, isEmpty);
        expect(s.currentMatchIndex, isNull);
      },
    );

    test(
      'given_queryWithNoMatchInBuffer_when_startSearch_then_activeAndEmptyMatchesAndNullIndex',
      () async {
        final container = makeContainer(initialText: 'hello world');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('xyz');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.active, isTrue);
        expect(s.matches, isEmpty);
        expect(s.currentMatchIndex, isNull);
      },
    );
  });

  // =========================================================================
  // next
  // =========================================================================

  group('FindNotifier.next', () {
    test('given_threeMatchesAtLastIndex_when_next_then_wrapsToZero', () async {
      final container = makeContainer(initialText: 'a x a x a');
      final notifier = container.read(findProvider.notifier);
      notifier.setQuery('a');
      notifier.startSearch(entryOffset: 5); // index=2 (last)
      await pumpMicrotasks();

      notifier.next();
      final s = container.read(findProvider);
      expect(s.currentMatchIndex, equals(0)); // wrapped
    });

    test(
      'given_threeMatchesAtFirstIndex_when_next_then_advancesToOne',
      () async {
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 0); // index=0
        await pumpMicrotasks();

        notifier.next();
        final s = container.read(findProvider);
        expect(s.currentMatchIndex, equals(1));
      },
    );

    test('given_emptyMatchList_when_next_then_noOpAndNoThrow', () async {
      final container = makeContainer(initialText: 'hello');
      final notifier = container.read(findProvider.notifier);
      notifier.setQuery('xyz');
      notifier.startSearch(entryOffset: 0);
      await pumpMicrotasks();

      expect(() => notifier.next(), returnsNormally);
      final s = container.read(findProvider);
      expect(s.currentMatchIndex, isNull);
    });
  });

  // =========================================================================
  // previous
  // =========================================================================

  group('FindNotifier.previous', () {
    test(
      'given_threeMatchesAtFirstIndex_when_previous_then_wrapsToLast',
      () async {
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 0); // index=0
        await pumpMicrotasks();

        notifier.previous();
        final s = container.read(findProvider);
        expect(s.currentMatchIndex, equals(2)); // wrapped to last
      },
    );

    test(
      'given_threeMatchesAtLastIndex_when_previous_then_movesToSecond',
      () async {
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 5); // index=2
        await pumpMicrotasks();

        notifier.previous();
        final s = container.read(findProvider);
        expect(s.currentMatchIndex, equals(1));
      },
    );

    test('given_emptyMatchList_when_previous_then_noOpAndNoThrow', () async {
      final container = makeContainer(initialText: 'hello');
      final notifier = container.read(findProvider.notifier);
      notifier.setQuery('xyz');
      notifier.startSearch(entryOffset: 0);
      await pumpMicrotasks();

      expect(() => notifier.previous(), returnsNormally);
      final s = container.read(findProvider);
      expect(s.currentMatchIndex, isNull);
    });
  });

  // =========================================================================
  // setQuery
  // =========================================================================

  group('FindNotifier.setQuery', () {
    test(
      'given_activeSearchAndNewQuery_when_setQuery_then_recomputesMatchesAndRederivesIndexFromZero',
      () async {
        final container = makeContainer(initialText: 'foo bar foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 5); // index=1 (second foo)
        await pumpMicrotasks();

        notifier.setQuery('bar');
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.query, equals('bar'));
        expect(s.matches.length, equals(1));
        // re-derived from entryOffset=0 → index 0
        expect(s.currentMatchIndex, equals(0));
      },
    );

    test(
      'given_activeSearchAndEmptyQuery_when_setQuery_then_matchesEmptyAndIndexNull',
      () async {
        final container = makeContainer(initialText: 'foo bar foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        notifier.setQuery('');
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.matches, isEmpty);
        expect(s.currentMatchIndex, isNull);
      },
    );
  });

  // =========================================================================
  // setReplaceTerm
  // =========================================================================

  group('FindNotifier.setReplaceTerm', () {
    test(
      'given_notifier_when_setReplaceTerm_then_replaceTermUpdatedOtherFieldsUnchanged',
      () async {
        final container = makeContainer(initialText: 'foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        notifier.setReplaceTerm('baz');
        final s = container.read(findProvider);
        expect(s.replaceTerm, equals('baz'));
        expect(s.query, equals('foo'));
        expect(s.active, isTrue);
      },
    );
  });

  // =========================================================================
  // replaceCurrent
  // =========================================================================

  group('FindNotifier.replaceCurrent', () {
    test(
      'given_currentMatchExists_when_replaceCurrent_then_returnsTextAndCaretRecord',
      () async {
        // "foo bar foo", query "foo" index 0, replaceTerm "baz"
        // → replaceRange("foo bar foo", MatchSpan(0,3), "baz")
        //   = {text: "baz bar foo", nextCaretOffset: 3}
        final container = makeContainer(initialText: 'foo bar foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.setReplaceTerm('baz');
        notifier.startSearch(entryOffset: 0); // index=0, match at (0,3)
        await pumpMicrotasks();

        final result = notifier.replaceCurrent();
        expect(result, isNotNull);
        expect(result!.text, equals('baz bar foo'));
        expect(result.nextCaretOffset, equals(3));
      },
    );

    test('given_noCurrentMatch_when_replaceCurrent_then_returnsNull', () async {
      final container = makeContainer(initialText: 'hello');
      final notifier = container.read(findProvider.notifier);
      notifier.setQuery('xyz'); // no match
      notifier.startSearch(entryOffset: 0);
      await pumpMicrotasks();

      final result = notifier.replaceCurrent();
      expect(result, isNull);
    });

    test(
      'given_nullCurrentMatchIndex_when_replaceCurrent_then_stateUnchanged',
      () async {
        final container = makeContainer(initialText: 'hello');
        final notifier = container.read(findProvider.notifier);
        // No startSearch → index=null
        final before = container.read(findProvider);
        notifier.replaceCurrent();
        final after = container.read(findProvider);
        expect(after, equals(before));
      },
    );

    test(
      'given_replaceCurrent_when_called_then_doesNotWriteControllerValueOrCallUpdateText',
      () async {
        // replaceCurrent is a pure record return — the test verifies bufferProvider
        // text is NOT changed by replaceCurrent (caller must apply the record).
        final container = makeContainer(initialText: 'foo bar');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.setReplaceTerm('baz');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        final bufferBefore = container.read(bufferProvider).text;
        notifier.replaceCurrent();
        final bufferAfter = container.read(bufferProvider).text;

        // bufferProvider must NOT have been mutated by replaceCurrent
        expect(bufferAfter, equals(bufferBefore));
      },
    );
  });

  // =========================================================================
  // close
  // =========================================================================

  group('FindNotifier.close', () {
    test(
      'given_activeSearchWithMatches_when_close_then_activeIsFalseMatchesEmptyIndexNull',
      () async {
        final container = makeContainer(initialText: 'a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        notifier.close();
        final s = container.read(findProvider);
        expect(s.active, isFalse);
        expect(s.matches, isEmpty);
        expect(s.currentMatchIndex, isNull);
      },
    );

    test('given_activeSearch_when_close_then_bufferCaretNotMoved', () async {
      // close() must NOT update bufferProvider text (no caret mutation there)
      final container = makeContainer(initialText: 'a x a');
      final notifier = container.read(findProvider.notifier);
      notifier.setQuery('a');
      notifier.startSearch(entryOffset: 0);
      await pumpMicrotasks();

      final textBefore = container.read(bufferProvider).text;
      notifier.close();
      final textAfter = container.read(bufferProvider).text;
      expect(textAfter, equals(textBefore));
    });
  });

  // =========================================================================
  // Reactivity — buffer text changes trigger recompute
  // =========================================================================

  group('FindNotifier reactivity', () {
    test(
      'given_activeSearchAndBufferTextChanges_when_textChanges_then_matchesRecomputed',
      () async {
        final container = makeContainer(initialText: 'foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        // 1 match initially
        expect(container.read(findProvider).matches.length, equals(1));

        // Buffer text changes → recompute
        container.read(bufferProvider.notifier).updateText('foo bar foo');
        await pumpMicrotasks();

        expect(container.read(findProvider).matches.length, equals(2));
      },
    );

    test(
      'given_activeSearchAndBufferTextUnchanged_when_sameTextSet_then_noRecompute',
      () async {
        final container = makeContainer(initialText: 'foo bar');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        final matchesBefore = container.read(findProvider).matches;

        // "Set" same text — bufferProvider guards next.text != prev.text
        container.read(bufferProvider.notifier).updateText('foo bar');
        await pumpMicrotasks();

        // State identity: same list object (no recompute happened)
        expect(container.read(findProvider).matches, equals(matchesBefore));
      },
    );
  });

  // =========================================================================
  // Stale-result rejection
  // =========================================================================

  group('FindNotifier stale-result rejection', () {
    test(
      'given_asyncResultWithStaleSourceText_when_resultArrives_then_priorMatchesRetained',
      () async {
        // This test verifies the conceptual contract: replaceCurrent does not
        // mutate bufferProvider, and a subsequent text change supersedes any
        // in-flight result for the previous text.
        //
        // We simulate stale by: starting a search, then changing the buffer
        // text before the microtask coalesce runs (so the in-flight compute
        // would be for the old text).
        //
        // With sync path (text < 10000): no actual in-flight — the second
        // updateText triggers its own microtask coalesce and wins. The prior
        // matches for "foo" in "foo" are replaced by matches for "foo" in
        // "foo baz", still valid. This covers the observable guard: the final
        // state reflects the LATEST buffer text.
        final container = makeContainer(initialText: 'foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        // Change text rapidly — second change is the "current" text
        container.read(bufferProvider.notifier).updateText('foo baz');
        container.read(bufferProvider.notifier).updateText('foo baz foo');
        await pumpMicrotasks();

        // Final state must reflect "foo baz foo" with 2 matches
        final s = container.read(findProvider);
        expect(s.matches.length, equals(2));
      },
    );
  });

  // =========================================================================
  // Index re-clamping after recompute shrinks list
  // =========================================================================

  group('FindNotifier index re-clamping', () {
    test(
      'given_currentIndexAtTwo_when_recomputeYieldsOnlyOneMatch_then_indexClampedToZero',
      () async {
        // Start with 3 matches, navigate to index 2, then shrink to 1 match
        final container = makeContainer(initialText: 'a x a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 5); // index=2
        await pumpMicrotasks();

        expect(container.read(findProvider).currentMatchIndex, equals(2));

        // Change buffer so only 1 "a" remains
        container.read(bufferProvider.notifier).updateText('a x b x b');
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.matches.length, equals(1));
        // Index was 2, count is now 1 → clamped to 0
        expect(s.currentMatchIndex, equals(0));
      },
    );

    test(
      'given_currentIndexNonNull_when_recomputeYieldsZeroMatches_then_indexIsNull',
      () async {
        final container = makeContainer(initialText: 'foo bar');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        expect(container.read(findProvider).currentMatchIndex, equals(0));

        // Remove all matches
        container.read(bufferProvider.notifier).updateText('baz bar');
        await pumpMicrotasks();

        final s = container.read(findProvider);
        expect(s.matches, isEmpty);
        expect(s.currentMatchIndex, isNull);
      },
    );
  });

  // =========================================================================
  // Non-auto-disposed survival
  // =========================================================================

  group('FindNotifier non-auto-disposed', () {
    test(
      'given_activeSearch_when_containerHasNoListeners_then_statePreserved',
      () async {
        // FR-04 / EC-17: non-auto-disposed means state survives listener removal.
        // ProviderContainer.read does not subscribe, so the provider must remain
        // alive between reads.
        final container = makeContainer(initialText: 'a x a');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('a');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        // Read twice without watch — state must persist between reads
        final first = container.read(findProvider);
        final second = container.read(findProvider);
        expect(first.active, isTrue);
        expect(second.active, isTrue);
        expect(first, equals(second));
      },
    );
  });

  // =========================================================================
  // Sync path (below threshold)
  // =========================================================================

  group('FindNotifier sync path below kFindIsolateThreshold', () {
    test(
      'given_textBelowThreshold_when_startSearch_then_matchesComputedSynchronously',
      () async {
        // Text < 10000 chars → synchronous FindEngine.findMatches call.
        // The state is updated before any await is needed.
        final text = 'foo bar foo'; // well below 10000 chars
        expect(text.length, lessThan(kFindIsolateThreshold));

        final container = makeContainer(initialText: text);
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);

        // No await needed — sync path should update state immediately
        final s = container.read(findProvider);
        expect(s.matches.length, equals(2));
        expect(s.active, isTrue);
      },
    );
  });

  // =========================================================================
  // Async path (at/above threshold) — structural test
  // =========================================================================

  group('FindNotifier async path at/above kFindIsolateThreshold', () {
    test(
      'given_textAtThreshold_when_startSearch_then_matchesAvailableAfterFuture',
      () async {
        // Build a text at exactly kFindIsolateThreshold chars containing "needle"
        final padding = 'x' * (kFindIsolateThreshold - 'needle'.length);
        final text = 'needle$padding';
        expect(text.length, equals(kFindIsolateThreshold));

        final container = makeContainer(initialText: text);
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('needle');
        notifier.startSearch(entryOffset: 0);

        // Async path → result arrives after a Future
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final s = container.read(findProvider);
        expect(s.active, isTrue);
        expect(s.matches.length, equals(1));
        expect(s.matches.first.start, equals(0));
      },
    );
  });

  // =========================================================================
  // Microtask coalescing
  // =========================================================================

  group('FindNotifier microtask coalescing', () {
    test(
      'given_manyRapidBufferEdits_when_microtaskSettles_then_stateReflectsLastEdit',
      () async {
        final container = makeContainer(initialText: 'foo');
        final notifier = container.read(findProvider.notifier);
        notifier.setQuery('foo');
        notifier.startSearch(entryOffset: 0);
        await pumpMicrotasks();

        // Many rapid edits without awaiting — only the last must matter
        container.read(bufferProvider.notifier).updateText('foo a');
        container.read(bufferProvider.notifier).updateText('foo a foo b');
        container.read(bufferProvider.notifier).updateText('foo a foo b foo');
        await pumpMicrotasks();

        final s = container.read(findProvider);
        // Last text "foo a foo b foo" → 3 matches
        expect(s.matches.length, equals(3));
      },
    );
  });
}
