import 'dart:io';

import 'package:buffer/domain/recovery/recovery_repository.dart';

/// Use case: save the current buffer text to the recovery store.
///
/// ## Trim-guard (EC-M2-02, §5.1.2)
///
/// When [text] is empty or whitespace-only after trimming, returns `null`
/// immediately — no filesystem I/O is performed. This guard lives HERE at the
/// use-case boundary, not in [RecoveryRepository] and not gated on any
/// `isDirty` flag.
///
/// The RAW (un-trimmed) [text] is passed to [RecoveryRepository.save] — only
/// the empty/non-empty DECISION uses trim.
///
/// ## Return value
///
/// Returns `null` when nothing was saved (empty/whitespace input).
/// Returns the written [File] when the save succeeds.
///
/// ## Error contract
///
/// A [FileSystemException] from the repository propagates to the caller
/// unchanged; the lifecycle host (EC-M2-08) is responsible for catching it.
class SaveBufferToRecovery {
  const SaveBufferToRecovery(this._repository);

  final RecoveryRepository _repository;

  /// Saves [text] to the recovery store, or returns `null` if [text] is
  /// empty/whitespace-only.
  Future<File?> call(String text) async {
    if (text.trim().isEmpty) return null;
    return _repository.save(text);
  }
}
