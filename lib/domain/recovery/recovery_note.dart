import 'package:meta/meta.dart';

/// Immutable value entity representing a single saved recovery note (M5, §5.1.1).
///
/// Carries the stable file identity ([path]), the UTC timestamp parsed from
/// the filename ([savedAt]), and an ~80-char single-line preview ([preview]).
///
/// ## Documented invariants (producer-guaranteed, NOT constructor-enforced)
///
/// - `preview.length <= 80` — [RecoveryPreview.truncate] guarantees this.
/// - `preview` contains no `\n` — collapsed by [RecoveryPreview.truncate].
/// - `savedAt.isUtc == true` — [RecoveryFilename.parse] always returns UTC.
/// - `savedAt` is derived solely from the filename, never from filesystem mtime.
///
/// No `copyWith` is provided: this entity is read-only. No I/O; the file path
/// is carried as a plain [String]. Flutter-free (no `package:flutter` import).
@immutable
class RecoveryNote {
  const RecoveryNote({
    required this.path,
    required this.savedAt,
    required this.preview,
  });

  /// Absolute file path — stable file identity used by delete/read operations.
  final String path;

  /// UTC timestamp parsed from the filename (inverse of `_buildStem`).
  /// Never derived from filesystem mtime.
  final DateTime savedAt;

  /// Single-line preview: at most 80 UTF-16 code units, no newlines.
  final String preview;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecoveryNote &&
          other.path == path &&
          other.savedAt == savedAt &&
          other.preview == preview;

  @override
  int get hashCode => Object.hash(path, savedAt, preview);
}
