// TASK-06: ShareIntentService — platform-share intake interface.
// Spec refs: FR-17, EC-12, OQ-14/R-21.
//
// Isolates the receive_sharing_intent package so the concrete implementation
// can be swapped without touching any consumer. No receive_sharing_intent type
// may appear in this file's public signatures (EC-12).
//
// M1 ships this interface only. The concrete implementation (which imports
// receive_sharing_intent and adapts SharedMediaFile → String) is wired in M2.
//
// Interface members:
//   initialSharedText() — cold-start: text delivered before the app was running.
//   sharedTextStream()  — warm-start: stream of text shared while the app is live.
//   dispose()           — release platform channel resources.

/// Abstracts the platform share-intake channel.
///
/// Consumers depend only on Dart-native types ([Future], [Stream], [String]).
/// No type from `receive_sharing_intent` leaks through these signatures.
abstract interface class ShareIntentService {
  /// Returns the text that was shared to the app during a cold start, or
  /// `null` if the app was launched normally.
  ///
  /// Called once at app start-up by the M2 share-intake use case.
  Future<String?> initialSharedText();

  /// A stream of text values shared to the app while it is already running
  /// (warm-start / resume).
  ///
  /// M2 subscribes to this stream; M1 does not wire any subscriber.
  Stream<String> sharedTextStream();

  /// Releases the underlying platform channel subscription.
  ///
  /// Must be called when the owning object is disposed to avoid resource leaks.
  void dispose();
}
