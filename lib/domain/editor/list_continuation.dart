import 'package:meta/meta.dart';

/// Result of a successful list continuation. `null` from [ListContinuation.process]
/// means "no continuation — caller inserts a plain \n".
@immutable
class ContinuationResult {
  /// Full buffer text AFTER the continuation is applied.
  final String text;

  /// Collapsed caret offset AFTER the inserted marker.
  final int caret;

  const ContinuationResult(this.text, this.caret);
}

// ---------------------------------------------------------------------------
// Canon-verbatim constants (canon-extraction.md §1 + §6).
// ---------------------------------------------------------------------------

/// Bullet-list regex — verbatim from BULLET_LIST_EXPRESSION.
/// Order: longer patterns first so `- [ ] ` and `- [x] ` match before `- `.
final RegExp _bulletRegex = RegExp(r'^\s*(- \[ \] |- \[x\] |- |\+ |\* )');

/// Ordered-list regex — verbatim from check_line_for_ordered_list_item.
final RegExp _orderedRegex = RegExp(r'^(\s*)([a-zA-Z]{1}|[0-9]+)([\.\)]) +');

/// Closed bullet token map (trimmed key → continuation token).
/// `- [x] ` continues as `- [ ] ` (checked → unchecked).
const Map<String, String> _bulletTokens = {
  '- [ ] ': '- [ ] ',
  '- [x] ': '- [ ] ',
  '- ': '- ',
  '+ ': '+ ',
  '* ': '* ',
};

// ---------------------------------------------------------------------------
// Public surface.
// ---------------------------------------------------------------------------

abstract final class ListContinuation {
  /// Returns a [ContinuationResult] (full post-continuation buffer text +
  /// collapsed caret offset) or `null` when no list rule fires (caller
  /// inserts a plain `\n`).
  ///
  /// Total: never throws at [caretOffset] == 0 or == [fullText].length.
  static ContinuationResult? process(String fullText, int caretOffset) {
    if (fullText.isEmpty) return null;

    final lineStart = _lineStartBefore(fullText, caretOffset);
    final previousLine = fullText.substring(lineStart, caretOffset);

    final bulletResult = _matchBullet(previousLine);
    if (bulletResult != null) {
      return _extendBullet(
        fullText: fullText,
        caretOffset: caretOffset,
        spacing: bulletResult.$1,
        token: bulletResult.$2,
      );
    }

    final orderedResult = _matchOrdered(previousLine);
    if (orderedResult != null) {
      return _extendOrdered(
        fullText: fullText,
        caretOffset: caretOffset,
        spacing: orderedResult.$1,
        index: orderedResult.$2,
        marker: orderedResult.$3,
      );
    }

    return null;
  }

  /// Pure helper: increments or decrements an ordered-list index.
  ///
  /// - Numeric: parse, add [direction], return result if > 0, else null.
  /// - Alpha single char: case-preserving; `Z`/`z` up ⇒ null; `A`/`a` down ⇒ null.
  ///
  /// [direction] must be +1 or -1.
  static String? calculateOrderedIndex(String index, int direction) {
    final numericValue = int.tryParse(index);
    if (numericValue != null) {
      final next = numericValue + direction;
      return next > 0 ? next.toString() : null;
    }

    // Alpha single-character path.
    if (index.length == 1) {
      final char = index.codeUnitAt(0);
      final upper = index.toUpperCase().codeUnitAt(0);
      if (direction > 0) {
        if (upper >= 90) return null; // 'Z' ceiling
        return String.fromCharCode(char + 1);
      } else {
        if (upper <= 65) return null; // 'A' floor
        return String.fromCharCode(char - 1);
      }
    }

    return null;
  }
}

// ---------------------------------------------------------------------------
// Private helpers.
// ---------------------------------------------------------------------------

/// Returns the code-unit offset of the start of the line that contains
/// [caretOffset]. The caret itself may be anywhere in [0, text.length].
int _lineStartBefore(String text, int caretOffset) {
  if (caretOffset == 0) return 0;
  final before = text.lastIndexOf('\n', caretOffset - 1);
  return before == -1 ? 0 : before + 1;
}

/// Returns the end-of-line offset (exclusive) starting from [from].
/// If there is no newline after [from], returns [text.length].
int _lineEndAfter(String text, int from) {
  final next = text.indexOf('\n', from);
  return next == -1 ? text.length : next;
}

/// Attempts to match [previousLine] against the bullet grammar.
/// Returns `(spacing, continuationToken)` or null.
(String, String)? _matchBullet(String previousLine) {
  final match = _bulletRegex.firstMatch(previousLine);
  if (match == null) return null;

  final fullMatch = match.group(0)!;
  // spacing = leading whitespace = everything before the token
  final tokenStart = fullMatch.length - match.group(1)!.length;
  final spacing = fullMatch.substring(0, tokenStart);
  final trimmedKey = match.group(1)!;
  final token = _bulletTokens[trimmedKey];
  if (token == null) return null;

  return (spacing, token);
}

/// Attempts to match [previousLine] against the ordered grammar.
/// Returns `(spacing, index, markerChar)` or null.
(String, String, String)? _matchOrdered(String previousLine) {
  final match = _orderedRegex.firstMatch(previousLine);
  if (match == null) return null;

  final spacing = match.group(1)!;
  final index = match.group(2)!;
  final marker = match.group(3)!;
  return (spacing, index, marker);
}

/// Executes the bullet-list continuation.
ContinuationResult? _extendBullet({
  required String fullText,
  required int caretOffset,
  required String spacing,
  required String token,
}) {
  // Already-continues guard (spec §5.1 / EC-10):
  // if caret-to-end-of-current-line already matches a bullet item → null.
  final lineEnd = _lineEndAfter(fullText, caretOffset);
  final caretToEol = fullText.substring(caretOffset, lineEnd);
  if (_bulletRegex.hasMatch(caretToEol)) return null;

  // Empty-item-ends-list check.
  final lineStart = _lineStartBefore(fullText, caretOffset);
  final previousLine = fullText.substring(lineStart, caretOffset);
  // The "just-entered" line's trimmed content vs marker trimmed.
  final trimmedLine = previousLine.trim();
  final trimmedToken = (spacing + token).trim();

  if (trimmedLine == trimmedToken) {
    // Check the line two above starts with the previous sequence item.
    // For bullets the "previous" item is the same marker.
    if (_twoAboveStartsWith(fullText, lineStart, spacing + token)) {
      // Remove the empty marker line. Caret sits at the start of the now-
      // last line (lineStart), which is the "plain new-line start" per spec.
      final newText =
          fullText.substring(0, lineStart) + fullText.substring(lineEnd);
      return ContinuationResult(newText, lineStart);
    }
  }

  // Normal continuation: insert '\n{spacing}{token}'.
  final insertion = '\n$spacing$token';
  final newText =
      fullText.substring(0, caretOffset) +
      insertion +
      fullText.substring(caretOffset);
  final newCaret = caretOffset + insertion.length;
  return ContinuationResult(newText, newCaret);
}

/// Executes the ordered-list continuation.
ContinuationResult? _extendOrdered({
  required String fullText,
  required int caretOffset,
  required String spacing,
  required String index,
  required String marker,
}) {
  final lineStart = _lineStartBefore(fullText, caretOffset);
  final previousLine = fullText.substring(lineStart, caretOffset);
  final lineEnd = _lineEndAfter(fullText, caretOffset);

  // The full marker text used for empty-item check.
  // previousLine should start with spacing+index+marker+' '
  final trimmedLine = previousLine.trim();

  // Empty-item-ends-list check for ordered lists.
  // The "just-entered" line's trimmed content vs the matched marker trimmed.
  final markerText = '$spacing$index$marker ';
  final trimmedMarker = markerText.trim();
  if (trimmedLine == trimmedMarker) {
    // Check the previous sequence item in the line two above.
    final prevIndex = ListContinuation.calculateOrderedIndex(index, -1);
    if (prevIndex != null) {
      final prevMarkerText = '$spacing$prevIndex$marker ';
      if (_twoAboveStartsWith(fullText, lineStart, prevMarkerText)) {
        // Remove empty marker line, insert plain '\n'.
        final newText =
            fullText.substring(0, lineStart) + fullText.substring(lineEnd);
        return ContinuationResult(newText, lineStart);
      }
    }
    // If prevIndex is null (i.e. "1. " — there is no item 0), fall through
    // to lone-marker-continues path below.
  }

  // Compute next index.
  final nextIndex = ListContinuation.calculateOrderedIndex(index, 1);
  if (nextIndex == null) return null; // list ends

  final insertion = '\n$spacing$nextIndex$marker ';
  final newText =
      fullText.substring(0, caretOffset) +
      insertion +
      fullText.substring(caretOffset);
  final newCaret = caretOffset + insertion.length;
  return ContinuationResult(newText, newCaret);
}

/// Returns true iff the line two above [lineStart] in [text] starts with
/// [prefix]. The "line two above" is the line immediately before the line
/// that starts at [lineStart].
bool _twoAboveStartsWith(String text, int lineStart, String prefix) {
  if (lineStart == 0) return false;
  // The '\n' at lineStart-1 ends the line above. Find that line's start.
  final aboveLineEnd = lineStart - 1; // points at the '\n'
  if (aboveLineEnd == 0) return false;
  final aboveLineStart = _lineStartBefore(text, aboveLineEnd);
  final aboveLine = text.substring(aboveLineStart, aboveLineEnd);
  return aboveLine.startsWith(prefix);
}
