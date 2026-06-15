import 'dart:io';

import 'package:buffer/domain/recovery/recovery_note.dart';

/// Domain port (repository interface) for the recovery persistence boundary.
///
/// ## M2 surface (FR-M2-09, §5.1.1)
///
/// The sole M2 member is [save]. The Emergency-Recovery milestone (M5 /
/// Phase 4) extends this SAME interface additively with `list`, `read`,
/// `delete`, `deleteAll`, and `trim` — added below (OCP: new behaviour
/// via additive implementation, not edits to this interface).
///
/// ## Precondition (caller-enforced)
///
/// The caller (the `SaveBufferToRecovery` use case) guarantees that [text]
/// is non-empty after trimming before delegating to [save]. The repository
/// does NOT re-validate emptiness — that guard lives at the use-case boundary.
///
/// ## Error contract
///
/// A [FileSystemException] thrown by the underlying I/O MUST propagate to
/// the caller unchanged. Implementations must NOT swallow, wrap, or convert
/// it; the lifecycle host is responsible for catching and logging it so the
/// app never crashes on backgrounding (EC-M2-08).
///
/// ## Domain purity
///
/// This file imports only `dart:io` for [File] and the co-located
/// [RecoveryNote] domain entity. It must never import the Flutter SDK or any
/// infrastructure package.
abstract interface class RecoveryRepository {
  /// Persists [text] to the recovery store and returns the written [File].
  ///
  /// Precondition: `text.trim().isNotEmpty` — enforced by the use case.
  /// On [FileSystemException]: propagates to the caller unchanged (not
  /// swallowed).
  Future<File> save(String text);

  // --- M5, ADDED (additive; no breaking change) ---

  /// Returns saved notes NEWEST-FIRST. When the recovery directory is absent,
  /// returns const []. Never creates the directory. savedAt parsed from the
  /// filename. Malformed filenames are skipped. Propagates FileSystemException
  /// (UI-path caller catches and renders).
  Future<List<RecoveryNote>> list();

  /// Returns the full UTF-8 text of the note's backing file. Used by restore.
  /// Propagates FileSystemException (UI-path caller catches).
  Future<String> read(RecoveryNote note);

  /// Deletes exactly the one file identified by [note] (siblings untouched).
  /// No-op when the directory or the file is absent. Never creates the
  /// directory. Propagates FileSystemException (UI-path caller catches).
  Future<void> delete(RecoveryNote note);

  /// Deletes every recovery `.txt` file. No-op when the directory is absent.
  /// Never creates the directory. Propagates FileSystemException.
  Future<void> deleteAll();

  /// Retains the newest [keep] files by LEXICOGRAPHIC FILENAME, deletes the
  /// rest. No-op when the directory is absent or file count <= keep. Tie-break
  /// by filename, NEVER mtime. Called as trim(10) from SaveBufferToRecovery
  /// AFTER a successful save. Propagates FileSystemException UNCHANGED like
  /// save (background path — lifecycle host catches/logs).
  Future<void> trim(int keep);

  // --- NEW (additive, Defect B, C-04) ---

  /// Persists [text] to the recovery store SYNCHRONOUSLY and returns the
  /// written [File]. Used on the `paused`/`detached` lifecycle path where the
  /// OS may freeze the isolate before any async I/O flushes. Implementations
  /// MUST complete the directory-create + write + collision-resolution + the
  /// trim-to-keep step before returning (no awaits, no queued microtasks).
  ///
  /// Precondition: `text.trim().isNotEmpty` — enforced by the caller.
  /// On [FileSystemException]: propagates to the caller UNCHANGED (the
  /// lifecycle host catches and logs; never crashes — EC-M2-08).
  /// Retention: trims to the newest [keep] files (default 10) by LEXICOGRAPHIC
  /// filename AFTER the write succeeds, NEVER mtime (NFR-M5-01).
  File saveSync(String text, {int keep = 10});
}
