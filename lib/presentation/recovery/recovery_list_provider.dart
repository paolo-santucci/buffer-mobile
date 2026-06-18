// TASK-07: recoveryListProvider — presentation state for the recovery list.
//
// Spec refs: FR-M5-01, FR-M5-07, FR-M5-10, FR-M5-11, FR-M5-12, NFR-M5-02
//
// Non-auto-disposed AsyncNotifierProvider (single-provider rule §5.3, mirrors
// findProvider / bufferProvider). Reads through the EXISTING
// recoveryRepositoryProvider in share_providers.dart — no new repo provider.
//
// SRP contract: [RecoveryListNotifier.restore] returns the note's text and
// does NOT touch [bufferProvider]. The screen (TASK-10) calls
// `ref.read(bufferProvider.notifier).populate(text)` then `Navigator.pop()`,
// keeping the buffer-write at the single sanctioned call site.
//
// NFR-M5-02: no method name in this file matches the regex
// \b(persist|write|store|share)\b — enforced by TASK-14 gate-7.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/presentation/editor/share_providers.dart';

/// Non-auto-disposed provider for the recovery list screen state.
///
/// Errors from the repository surface as [AsyncError] — the screen renders an
/// error/empty state. Never crashes on a missing recovery directory (the repo
/// returns `const []` when absent, per FR-M5-12).
final recoveryListProvider =
    AsyncNotifierProvider<RecoveryListNotifier, List<RecoveryNote>>(
      RecoveryListNotifier.new,
    );

/// Notifier managing the list of saved recovery notes.
///
/// **Verb surface** (NFR-M5-02: no name matches persist|write|store|share):
/// - [build] — loads the note list from the repository.
/// - [refresh] — re-fetches the list.
/// - [delete] — removes a single note, then refreshes.
/// - [deleteAll] — removes all notes, then refreshes.
/// - [restore] — reads a note's full text; the **caller** pipes it to
///   `bufferProvider.notifier.populate` (SRP: this notifier owns list state,
///   not buffer mutation).
class RecoveryListNotifier extends AsyncNotifier<List<RecoveryNote>> {
  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Future<List<RecoveryNote>> build() async {
    // Any FileSystemException from the repository propagates → AsyncError.
    // The screen renders an error/empty state (FR-M5-12 error contract).
    final repo = ref.read(recoveryRepositoryProvider);
    return repo.list();
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Re-fetches the note list from the repository.
  ///
  /// Sets state to [AsyncLoading] briefly then resolves to the new list.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(recoveryRepositoryProvider).list(),
    );
  }

  /// Deletes [note] from the repository and refreshes list state.
  ///
  /// A [FileSystemException] from the repo surfaces as [AsyncError].
  Future<void> delete(RecoveryNote note) async {
    await ref.read(recoveryRepositoryProvider).delete(note);
    await refresh();
  }

  /// Deletes all recovery notes from the repository and refreshes list state.
  ///
  /// After a successful call the list resolves to `[]` and the screen shows
  /// the empty state (FR-M5-11).
  Future<void> deleteAll() async {
    await ref.read(recoveryRepositoryProvider).deleteAll();
    await refresh();
  }

  /// Returns the full UTF-8 text of [note]'s backing file.
  ///
  /// The **caller** (RecoveryScreen, TASK-10) is responsible for writing the
  /// text to the buffer via `ref.read(bufferProvider.notifier).populate(text)`
  /// — this notifier deliberately does NOT touch the buffer (SRP / NFR-M5-02).
  ///
  /// A [FileSystemException] from the repo propagates to the caller.
  Future<String> restore(RecoveryNote note) async {
    return ref.read(recoveryRepositoryProvider).read(note);
  }
}
