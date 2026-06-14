import 'package:meta/meta.dart';

/// Isolate-safe match span. Plain ints only (serializable across the
/// compute() boundary). NOT flutter's TextRange (which is fine to construct
/// at the presentation boundary, but the engine stays flutter-free).
///
/// Offsets are UTF-16 code-unit indices into the source text, matching
/// TextEditingController/TextSelection semantics (EC-12).
@immutable
class MatchSpan {
  /// Inclusive UTF-16 code-unit offset of the match start.
  final int start;

  /// Exclusive UTF-16 code-unit offset of the match end.
  final int end;

  const MatchSpan(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Serializable argument bundle for compute() (FR-08).
/// Records are sendable in Dart; fields are String + String → safe across
/// the isolate port.
typedef FindArgs = ({String text, String query});

/// Named character-count threshold above which match recomputation is
/// offloaded to a compute() isolate (NFR-01 / FR-08).
const int kFindIsolateThreshold = 10000;

/// Pure, Flutter-import-free search engine (NFR-05).
///
/// All methods are static and total: they never throw on degenerate inputs
/// and carry zero Flutter dependency. Offsets use UTF-16 code units to match
/// TextEditingController / TextSelection semantics 1:1 (EC-12).
abstract final class FindEngine {
  /// FR-01. Returns the ordered, non-overlapping, case-insensitive plain-text
  /// matches of [query] in [text], scanning left→right and resuming after
  /// each match end (so overlapping families like "aa" in "aaa" yield one
  /// match at offset 0).
  ///
  /// Degenerate inputs all return `const []` without throwing:
  ///   - empty [query]           (EC-02)
  ///   - empty [text]
  ///   - [query] longer than [text]
  ///
  /// No regex, no whole-word matching (parent §5.3 / Non-Goal 3).
  static List<MatchSpan> findMatches(String text, String query) {
    if (query.isEmpty || text.isEmpty || query.length > text.length) {
      return const [];
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final results = <MatchSpan>[];
    var searchFrom = 0;

    while (searchFrom <= lowerText.length - lowerQuery.length) {
      final index = lowerText.indexOf(lowerQuery, searchFrom);
      if (index == -1) break;
      results.add(MatchSpan(index, index + lowerQuery.length));
      searchFrom = index + lowerQuery.length;
    }

    return results;
  }

  /// FR-02 / FR-06. Returns the index of the first match in [matches] whose
  /// `start` is >= [entryOffset]; wraps to index 0 when none follow; returns
  /// null when [matches] is empty (EC-04).
  ///
  /// Defensive clamping: [entryOffset] values below 0 or above the last
  /// match start are handled without throwing.
  static int? autoSelectIndex(List<MatchSpan> matches, int entryOffset) {
    if (matches.isEmpty) return null;

    final clampedOffset = entryOffset < 0 ? 0 : entryOffset;

    for (var i = 0; i < matches.length; i++) {
      if (matches[i].start >= clampedOffset) return i;
    }

    // No match at/after the entry offset → wrap to first (FR-02).
    return 0;
  }

  /// FR-03. Splices [replacement] over [match] in [text] and returns the
  /// updated text plus the caret offset placed at the end of the replacement
  /// (== match.start + replacement.length).
  ///
  /// Empty [replacement] deletes the match span and places the caret at
  /// match.start (EC-13). Pure string arithmetic — no knowledge of the
  /// controller or the buffer.
  static ({String text, int nextCaretOffset}) replaceRange(
    String text,
    MatchSpan match,
    String replacement,
  ) {
    final newText =
        text.substring(0, match.start) +
        replacement +
        text.substring(match.end);
    final nextCaretOffset = match.start + replacement.length;
    return (text: newText, nextCaretOffset: nextCaretOffset);
  }
}

/// FR-08. Top-level isolate entry point for compute(). MUST be top-level
/// (not a closure / not an instance method) to be sendable across the
/// isolate port. Delegates to FindEngine.findMatches so both the sync and
/// async paths run identical logic.
List<MatchSpan> findMatchesIsolate(FindArgs args) =>
    FindEngine.findMatches(args.text, args.query);
