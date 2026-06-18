import 'package:foglietto/domain/buffer/buffer_state.dart';

/// Abstract contract for the single in-memory buffer.
///
/// Exposes exactly the minimal state surface required by FR-09 / FR-M2-09:
///   - [state]      — current snapshot of the buffer (read-only).
///   - [updateText] — replace the buffer text from a keystroke source; never persisted.
///   - [reset]      — restore the buffer to [BufferState.empty()].
///   - [populate]   — replace the buffer text from a non-keystroke source
///                    (e.g. recovery load); distinct from [updateText] semantically.
///
/// Inviolable-ephemerality invariant (NFR-09 / R-01):
///   No implementation of this interface may write buffer text to any
///   persistent store.  The sole sanctioned exception is the recovery hook
///   wired in TASK-12 (`bufferProvider`), which writes ONLY to the recovery
///   directory on background/detach — never through this interface.
///
/// Concrete implementation and Riverpod wiring live in TASK-12.
abstract interface class BufferNotifier {
  /// The current state of the buffer.
  BufferState get state;

  /// Replace the buffer text with [text] from a keystroke source.
  ///
  /// [text] may be empty (`""`); implementations must not throw.
  void updateText(String text);

  /// Reset the buffer to [BufferState.empty()].
  ///
  /// Idempotent: calling [reset] on an already-empty buffer is a no-op.
  void reset();

  /// Replace the buffer text with [text] from a non-keystroke source
  /// (e.g. loading a recovery entry).
  ///
  /// Semantically distinct from [updateText]: signals that the text origin
  /// is external rather than direct user keystrokes.
  /// [text] may be empty (`""`); implementations must not throw.
  void populate(String text);
}
