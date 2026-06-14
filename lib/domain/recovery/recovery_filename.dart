/// Pure filename→DateTime parser that is the inverse of
/// `FileRecoveryRepository._buildStem`.
///
/// Accepted grammar (millisecond, OQ-M5-02):
///   `YYYY-MM-DDTHH-MM-SS-mmmZ[.txt]`
///   `YYYY-MM-DDTHH-MM-SS-mmmZ-<N>[.txt]`
///
/// Returns `null` for any name that does not match, including names with
/// 6-digit (microsecond) fractional seconds — those are silently rejected,
/// never truncated.
abstract final class RecoveryFilename {
  // Matches the exact millisecond stem — \d{3}Z is the key discriminator that
  // rejects 6-digit microsecond variants (\d{6}Z would also match \d{3}Z if
  // we used a non-anchored pattern, so the regex anchors the fractional width).
  static final _stemPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z'
    r'(?:-\d+)?' // optional collision suffix  -1, -2, …
    r'(?:\.txt)?$', // optional .txt extension
  );

  /// Parses [filename] and returns the corresponding UTC [DateTime], or `null`
  /// if the name does not match the millisecond grammar.
  ///
  /// Never throws.
  static DateTime? parse(String filename) {
    final match = _stemPattern.firstMatch(filename);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final millisecond = int.parse(match.group(7)!);

    return DateTime.utc(year, month, day, hour, minute, second, millisecond);
  }
}
