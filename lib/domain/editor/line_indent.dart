import 'package:meta/meta.dart';

/// Result of a [LineIndent.indent] or [LineIndent.outdent] operation.
@immutable
class IndentResult {
  /// Buffer text after the indent/outdent operation.
  final String text;

  /// Re-anchored selection base offset.
  final int selStart;

  /// Re-anchored selection extent offset.
  final int selExtent;

  const IndentResult(this.text, this.selStart, this.selExtent);
}

/// Pure, total indent/outdent helper. No Flutter import (NFR-04).
///
/// Indent unit per line:
///   - `"  "` (two spaces) for lines matching the bullet OR ordered regex.
///   - `"\t"` (one tab) for all other lines.
///
/// Regexes encoded verbatim from canon-extraction §2 / spec §5.5.
abstract final class LineIndent {
  // ── Canon constants (verbatim, canon-extraction §6) ──────────────────
  static final RegExp _bulletRegex = RegExp(
    r'^\s*(- \[ \] |- \[x\] |- |\+ |\* )',
  );
  static final RegExp _orderedRegex = RegExp(
    r'^(\s*)([a-zA-Z]{1}|[0-9]+)([\.\)]){1}[ ]+',
  );

  static const String _listUnit = '  '; // two spaces (FR-11)
  static const String _nonListUnit = '\t'; // one tab (FR-11)

  // ── Public API ───────────────────────────────────────────────────────

  /// Adds one indent unit at the start of each affected line.
  ///
  /// Collapsed / single-line selection → caret line only.
  /// Multi-line selection → every non-empty line; empty lines skipped (EC-16).
  /// Selection re-anchored via position-stable offsets (FR-13, R-10).
  static IndentResult indent(String text, int selStart, int selExtent) =>
      _modify(text, selStart, selExtent, increase: true);

  /// Removes exactly one leading indent unit IFF the line starts with it.
  /// Column-0 / no leading unit → no-op for that line (FR-12, EC-17).
  static IndentResult outdent(String text, int selStart, int selExtent) =>
      _modify(text, selStart, selExtent, increase: false);

  // ── Core ─────────────────────────────────────────────────────────────

  static IndentResult _modify(
    String text,
    int selStart,
    int selExtent, {
    required bool increase,
  }) {
    if (text.isEmpty) return IndentResult(text, selStart, selExtent);

    final lines = _splitLines(text);
    final isMultiLine = _spansMultipleLines(text, selStart, selExtent);
    final affected = _affectedLineIndices(
      lines,
      selStart,
      selExtent,
      isMultiLine,
    );

    return _applyToLines(
      lines: lines,
      affected: affected,
      selStart: selStart,
      selExtent: selExtent,
      increase: increase,
    );
  }

  // ── Line splitting ────────────────────────────────────────────────────

  static List<({int start, String content})> _splitLines(String text) {
    final result = <({int start, String content})>[];
    var offset = 0;
    for (final line in text.split('\n')) {
      result.add((start: offset, content: line));
      offset += line.length + 1;
    }
    return result;
  }

  // ── Selection helpers ─────────────────────────────────────────────────

  static bool _spansMultipleLines(String text, int selStart, int selExtent) {
    final lo = selStart < selExtent ? selStart : selExtent;
    final hi = selStart < selExtent ? selExtent : selStart;
    return text.substring(lo, hi).contains('\n');
  }

  static List<int> _affectedLineIndices(
    List<({int start, String content})> lines,
    int selStart,
    int selExtent,
    bool isMultiLine,
  ) {
    if (!isMultiLine) {
      final caretPos = selStart < selExtent ? selStart : selExtent;
      return [_lineIndexAt(lines, caretPos)];
    }

    final lo = selStart < selExtent ? selStart : selExtent;
    final hi = selStart < selExtent ? selExtent : selStart;
    final result = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final lineStart = lines[i].start;
      final lineEnd = lineStart + lines[i].content.length;
      if (lineEnd < lo) continue;
      if (lineStart > hi) break;
      if (lines[i].content.isEmpty) continue; // skip blank lines (EC-16)
      result.add(i);
    }
    return result;
  }

  static int _lineIndexAt(
    List<({int start, String content})> lines,
    int offset,
  ) {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].start <= offset) return i;
    }
    return 0;
  }

  // ── Mutation with position-stable re-anchoring ────────────────────────

  static IndentResult _applyToLines({
    required List<({int start, String content})> lines,
    required List<int> affected,
    required int selStart,
    required int selExtent,
    required bool increase,
  }) {
    final buffer = StringBuffer();
    var selStartShift = 0;
    var selExtentShift = 0;

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) buffer.write('\n');

      if (!affected.contains(i)) {
        buffer.write(lines[i].content);
        continue;
      }

      final shifts = increase
          ? _applyIndent(buffer, lines[i], selStart, selExtent)
          : _applyOutdent(buffer, lines[i], selStart, selExtent);

      selStartShift += shifts.$1;
      selExtentShift += shifts.$2;
    }

    final newText = buffer.toString();
    return IndentResult(
      newText,
      (selStart + selStartShift).clamp(0, newText.length),
      (selExtent + selExtentShift).clamp(0, newText.length),
    );
  }

  /// Writes the indented line to [buf]; returns (selStartDelta, selExtentDelta).
  static (int, int) _applyIndent(
    StringBuffer buf,
    ({int start, String content}) line,
    int selStart,
    int selExtent,
  ) {
    final unit = _unitFor(line.content);
    buf.write(unit);
    buf.write(line.content);

    // Shift points strictly after the line start (anchor at line start stays).
    final unitLen = unit.length;
    final startDelta = selStart > line.start ? unitLen : 0;
    final extentDelta = selExtent > line.start ? unitLen : 0;
    return (startDelta, extentDelta);
  }

  /// Writes the outdented (or unchanged) line to [buf]; returns deltas.
  static (int, int) _applyOutdent(
    StringBuffer buf,
    ({int start, String content}) line,
    int selStart,
    int selExtent,
  ) {
    final unit = _unitFor(line.content);
    if (!line.content.startsWith(unit)) {
      buf.write(line.content); // no-op (EC-17)
      return (0, 0);
    }

    buf.write(line.content.substring(unit.length));

    final unitLen = unit.length;
    final lineStart = line.start;
    final startDelta = _removeDelta(selStart, lineStart, unitLen);
    final extentDelta = _removeDelta(selExtent, lineStart, unitLen);
    return (startDelta, extentDelta);
  }

  /// Computes how much a selection point at [pos] should shift when [unitLen]
  /// bytes are removed from [lineStart].
  static int _removeDelta(int pos, int lineStart, int unitLen) {
    if (pos > lineStart + unitLen) return -unitLen;
    if (pos > lineStart) return -(pos - lineStart); // inside removed prefix
    return 0;
  }

  // ── Unit selector ─────────────────────────────────────────────────────

  static String _unitFor(String lineContent) {
    if (_bulletRegex.hasMatch(lineContent) ||
        _orderedRegex.hasMatch(lineContent)) {
      return _listUnit;
    }
    return _nonListUnit;
  }
}
