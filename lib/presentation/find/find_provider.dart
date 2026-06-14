import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/buffer/buffer_provider.dart';
import 'package:buffer/domain/buffer/buffer_state.dart';
import 'package:buffer/domain/find/find_engine.dart';
import 'package:buffer/domain/find/find_state.dart';

/// Non-auto-disposed find/replace state provider (FR-04 / EC-17).
///
/// Mirrors the lifetime contract of [settingsProvider] and [bufferProvider]:
/// state survives zero-listener windows so an active search is not reset when
/// the widget tree rebuilds.
final findProvider = NotifierProvider<FindNotifier, FindState>(
  FindNotifier.new,
);

/// Notifier implementing the find/replace verb surface (spec §5.2).
///
/// **Internal scheduling state** (NOT on [FindState]):
///   - [_pending]: a microtask for the below-threshold coalesce has been
///     scheduled but not yet run.
///   - [_inflight]: an above-threshold [compute()] isolate is running.
///     When it finishes, the result is dropped if its [sourceText] no longer
///     matches [bufferProvider].text (FR-09 stale-result rejection).
///
/// **Constraint summary**:
///   - [replaceCurrent] returns a record for the caller (screen) to apply via
///     `_applyResult`; it MUST NOT write `_controller.value` or call
///     `updateText` (NFR-04 / spec §5.2).
///   - [close] deactivates without moving the buffer caret (FR-20 / EC-10).
class FindNotifier extends Notifier<FindState> {
  // ---------------------------------------------------------------------------
  // Internal scheduling state — kept OFF FindState (spec §5.2)
  // ---------------------------------------------------------------------------

  /// True while a microtask-coalesced recompute is pending for below-threshold
  /// text (NFR-02).
  bool _pending = false;

  /// Non-null while an above-threshold [compute()] call is in flight (NFR-02).
  /// Compared against [bufferProvider].text on arrival for stale-result
  /// rejection (FR-09).
  Future<void>? _inflight;

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  FindState build() {
    // React to every buffer edit; recompute keyed on changed text (FR-07).
    ref.listen<BufferState>(bufferProvider, _onBufferChanged);
    return const FindState();
  }

  // ---------------------------------------------------------------------------
  // Public verb surface
  // ---------------------------------------------------------------------------

  /// FR-06. Opens the search bar and auto-selects the first match at/after
  /// [entryOffset] (wrapping to index 0 when none follow).
  ///
  /// Uses the current [FindState.query]; callers should call [setQuery] first
  /// if the query needs updating.
  void startSearch({required int entryOffset}) {
    final text = ref.read(bufferProvider).text;
    final query = state.query;
    final matches = FindEngine.findMatches(text, query);
    final index = FindEngine.autoSelectIndex(matches, entryOffset);
    state = state.copyWith(
      active: true,
      matches: matches,
      currentMatchIndex: index,
    );
  }

  /// Live query edit. Recomputes matches and re-derives [currentMatchIndex]
  /// from offset 0 (spec §5.2).
  void setQuery(String query) {
    if (state.query == query) return;
    final text = ref.read(bufferProvider).text;
    final matches = FindEngine.findMatches(text, query);
    final index = matches.isEmpty
        ? null
        : FindEngine.autoSelectIndex(matches, 0);
    state = state.copyWith(
      query: query,
      matches: matches,
      currentMatchIndex: index,
    );
  }

  /// FR-10. Advances current-match index by one, wrapping at the end.
  /// No-op when the match list is empty.
  void next() {
    final count = state.count;
    if (count == 0) return;
    final current = state.currentMatchIndex ?? 0;
    state = state.copyWith(currentMatchIndex: (current + 1) % count);
  }

  /// FR-11. Moves current-match index back by one, wrapping at the start.
  /// No-op when the match list is empty.
  void previous() {
    final count = state.count;
    if (count == 0) return;
    final current = state.currentMatchIndex ?? 0;
    state = state.copyWith(currentMatchIndex: (current - 1 + count) % count);
  }

  /// Updates [FindState.replaceTerm] only.
  void setReplaceTerm(String term) {
    state = state.copyWith(replaceTerm: term);
  }

  /// FR-14 / FR-15. Computes the replace arithmetic and returns the result for
  /// the caller to apply through the `_applyResult` path.
  ///
  /// Returns null when there is no current match (Replace disabled, FR-15).
  /// MUST NOT write `_controller.value` or call `updateText`; those are the
  /// responsibility of the screen wiring layer (NFR-04 / spec §5.2).
  ({String text, int nextCaretOffset})? replaceCurrent() {
    final match = state.currentMatch;
    if (match == null) return null;

    final text = ref.read(bufferProvider).text;
    return FindEngine.replaceRange(text, match, state.replaceTerm);
  }

  /// FR-20. Deactivates search: clears active flag, matches, and
  /// currentMatchIndex. Does NOT move the buffer caret (EC-10).
  void close() {
    state = state.copyWith(
      active: false,
      matches: const [],
      currentMatchIndex: null,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal: buffer-change reaction + recompute scheduling
  // ---------------------------------------------------------------------------

  void _onBufferChanged(BufferState? prev, BufferState next) {
    // Keyed on text change only (FR-07). Ignore if text unchanged.
    if (prev != null && prev.text == next.text) return;
    // Only recompute when the search is active and has a query.
    if (!state.active || state.query.isEmpty) return;
    _scheduleRecompute();
  }

  /// Schedules a microtask-coalesced recompute (NFR-02).
  ///
  /// Multiple rapid buffer edits collapse into a single dispatch: the
  /// `_pending` flag prevents stacking microtasks; the final microtask
  /// always uses the latest [bufferProvider].text at the time it runs.
  void _scheduleRecompute() {
    if (_pending) return; // Already a microtask pending — collapse.
    _pending = true;
    scheduleMicrotask(_runRecompute);
  }

  /// Executes the recompute — either inline (below threshold) or via
  /// [compute()] (at/above threshold).
  Future<void> _runRecompute() async {
    _pending = false;
    final text = ref.read(bufferProvider).text;
    final query = state.query;

    if (text.length < kFindIsolateThreshold) {
      // Synchronous path (NFR-01 / FR-08).
      final matches = FindEngine.findMatches(text, query);
      _applyRecomputeResult(sourceText: text, matches: matches);
    } else {
      // Async path via compute() isolate (FR-08 / NFR-01).
      // Capture the source text for stale-result detection (FR-09).
      final sourceText = text;
      final future =
          compute(findMatchesIsolate, (text: sourceText, query: query)).then((
            matches,
          ) {
            _applyRecomputeResult(sourceText: sourceText, matches: matches);
          });
      _inflight = future;
      await future;
      if (_inflight == future) _inflight = null;
    }
  }

  /// Applies a recompute result, enforcing stale-result rejection (FR-09) and
  /// index re-clamping (spec §5.2).
  void _applyRecomputeResult({
    required String sourceText,
    required List<MatchSpan> matches,
  }) {
    // Stale-result rejection: drop if source text != current buffer text.
    final currentText = ref.read(bufferProvider).text;
    if (sourceText != currentText) return; // FR-09: retain prior matches

    final count = matches.length;
    final newIndex = _clampIndex(state.currentMatchIndex, count);
    state = state.copyWith(matches: matches, currentMatchIndex: newIndex);
  }

  /// Clamps [index] to `[0, count)`, or returns null when [count] is 0.
  static int? _clampIndex(int? index, int count) {
    if (count == 0) return null;
    if (index == null) return null;
    if (index < 0) return 0;
    if (index >= count) return count - 1;
    return index;
  }
}
