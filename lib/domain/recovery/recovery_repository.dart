import 'dart:io';

/// Domain port (repository interface) for the recovery persistence boundary.
///
/// ## M2 surface (FR-M2-09, §5.1.1)
///
/// The sole M2 member is [save]. The Emergency-Recovery milestone (M5 /
/// Phase 4) extends this SAME interface additively with `list`, `restore`,
/// `delete`, and `trim` — do NOT add those members here (OCP: new behaviour
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
/// This file imports only `dart:io` for [File]. It must never import the
/// Flutter SDK or any infrastructure package.
abstract interface class RecoveryRepository {
  /// Persists [text] to the recovery store and returns the written [File].
  ///
  /// Precondition: `text.trim().isNotEmpty` — enforced by the use case.
  /// On [FileSystemException]: propagates to the caller unchanged (not
  /// swallowed).
  Future<File> save(String text);
}
