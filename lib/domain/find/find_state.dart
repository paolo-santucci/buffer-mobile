import 'package:foglietto/domain/find/find_engine.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'find_state.freezed.dart';

/// Immutable find/replace state (NFR-03: in-memory only, no persistence).
///
/// Holds the full search session: query text, replace term, the ordered
/// match list, the index of the current match (nullable — null means no
/// current match, FR-05/FR-15), and whether the search bar is active.
///
/// Derived getters (`count`, `hasCurrent`, `position`, `currentMatch`)
/// compute from stored fields without redundant storage. The private const
/// constructor enables these getters while preserving the @freezed invariant.
@freezed
class FindState with _$FindState {
  const FindState._();

  const factory FindState({
    @Default('') String query,
    @Default('') String replaceTerm,
    @Default(<MatchSpan>[]) List<MatchSpan> matches,
    int? currentMatchIndex, // null ⇒ no current match (FR-05/FR-15)
    @Default(false) bool active, // search bar shown / find engaged
  }) = _FindState;

  /// Total match count — equals [matches.length].
  int get count => matches.length;

  /// Whether a current match exists (currentMatchIndex is non-null).
  bool get hasCurrent => currentMatchIndex != null;

  /// 1-based match position for the `{position} of {count}` label (FR-12),
  /// or null when there is no current match.
  int? get position =>
      currentMatchIndex == null ? null : currentMatchIndex! + 1;

  /// The current [MatchSpan], or null when [currentMatchIndex] is null or
  /// out of range. Never throws — guards against stale indices defensively.
  MatchSpan? get currentMatch {
    final idx = currentMatchIndex;
    if (idx == null || idx < 0 || idx >= matches.length) return null;
    return matches[idx];
  }
}
