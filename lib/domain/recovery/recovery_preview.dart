/// Pure, Flutter-free preview truncation helper (FR-M5-04, NFR-M5-07).
///
/// Mirrors the `abstract final class` + static-fn pattern used by
/// `FindEngine` and `LineIndent` throughout this project.
abstract final class RecoveryPreview {
  static const int _maxLength = 80;

  /// Collapses every run of newline(s) — and any whitespace immediately
  /// surrounding the newline run — to a single space, then truncates the
  /// result to at most 80 UTF-16 code units.
  ///
  /// Invariants of the returned string:
  ///   • `result.length <= 80`
  ///   • `result` contains no `\n`
  ///   • No surrogate pair is split (UTF-16 safe truncation).
  ///   • No ellipsis is appended — ellipsis is a UI concern (spec §5.1.2).
  ///   • Input shorter than 80 code units with no newline is returned
  ///     unchanged (identity path, no padding).
  static String truncate(String head) {
    final collapsed = _collapseNewlines(head);
    return _safeTruncate(collapsed);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Replaces every sequence of `\s*\n+\s*` (optional whitespace, one or
  /// more newlines, optional whitespace) with a single space.
  static final RegExp _newlineRun = RegExp(r'\s*\n+\s*');

  static String _collapseNewlines(String text) {
    if (!text.contains('\n')) return text;
    return text.replaceAll(_newlineRun, ' ');
  }

  /// Hard-cuts [text] to at most [_maxLength] UTF-16 code units without
  /// splitting a surrogate pair.
  static String _safeTruncate(String text) {
    if (text.length <= _maxLength) return text;

    var cutAt = _maxLength;
    // A high surrogate is 0xD800–0xDBFF; if the cut lands on a high
    // surrogate, step back one code unit so the pair is preserved.
    if (_isHighSurrogate(text.codeUnitAt(cutAt - 1))) {
      cutAt -= 1;
    }
    return text.substring(0, cutAt);
  }

  /// Returns true when [codeUnit] is a UTF-16 high surrogate (0xD800–0xDBFF).
  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
}
