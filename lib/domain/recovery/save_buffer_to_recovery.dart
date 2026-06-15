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
  ///
  /// On a successful save, `trim(10)` is called to ensure the recovery
  /// directory never retains more than 10 files (FR-M5-03, §5.1.4).
  /// If [RecoveryRepository.save] throws, the exception propagates before
  /// `trim` runs — no catch, lifecycle host is responsible (EC-M2-08).
  Future<File?> call(String text) async {
    if (text.trim().isEmpty) return null;
    final file = await _repository.save(text);
    await _repository.trim(10);
    return file;
  }

  /// Synchronous entry point for the `paused`/`detached` lifecycle path.
  ///
  /// ## Why synchronous (T-03 fix)
  ///
  /// On Android (and iOS), the OS may freeze the Dart isolate immediately
  /// after the [AppLifecycleState.paused] callback returns. Any pending
  /// microtasks — including the continuation of an `async` save — are never
  /// scheduled, so async I/O is silently dropped. Calling [callSync] from
  /// inside [LifecycleBufferHost.didChangeAppLifecycleState] guarantees the
  /// bytes hit disk before the callback returns.
  ///
  /// ## Trim guard (EC-M2-02)
  ///
  /// Returns `null` immediately when [text] is empty or whitespace-only.
  /// The raw [text] (un-trimmed) is passed to
  /// [RecoveryRepository.saveSync], which also performs the synchronous
  /// trim-to-10 step internally (C-05 / NFR-M5-01).
  ///
  /// ## Error contract
  ///
  /// A [FileSystemException] propagates unchanged to the caller. The
  /// lifecycle host (EC-M2-08) wraps the call in try/catch and logs the
  /// error — this use-case method never swallows it.
  File? callSync(String text) {
    if (text.trim().isEmpty) return null;
    // The repository performs its own synchronous trim-to-10 after writing;
    // we do NOT also call trim() here (no async trim on the sync path).
    return _repository.saveSync(text);
  }
}
