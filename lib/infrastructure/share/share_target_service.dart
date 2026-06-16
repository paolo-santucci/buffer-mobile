// TASK-03: ShareTargetService — OS share-sheet dispatch interface.
// Spec refs: FR-06, FR-07, NFR-01, §5.1.1.
//
// Isolates the share_plus package so the concrete SharePlusService adapter
// (TASK-06) can be swapped without touching any consumer. No share_plus type
// — in particular no ShareResult — may appear in this file's public signatures
// (EC-M2-13, FR-07).
//
// OQ-02 resolution: the return type is Future<void>, not Future<bool>. The
// caller has no actionable response to a share-sheet cancellation; the concrete
// adapter awaits and discards the ShareResult internally.
//
// Interface members:
//   shareText(String) — dispatch text to the OS share sheet.

/// Abstracts the platform share-dispatch channel.
///
/// Consumers depend only on Dart-native types ([Future], [String]).
/// No type from `share_plus` leaks through this signature (EC-M2-13).
abstract interface class ShareTargetService {
  /// Dispatches [text] to the OS share sheet.
  ///
  /// Returns a [Future] that completes when the share operation has been
  /// handed off to the platform. The caller does not receive the user's
  /// share-target selection or cancellation — see OQ-02.
  Future<void> shareText(String text);
}
