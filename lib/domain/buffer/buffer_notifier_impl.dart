import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/domain/buffer/buffer_notifier.dart';
import 'package:foglietto/domain/buffer/buffer_state.dart';

/// Concrete in-memory implementation of [BufferNotifier].
///
/// Registered as [bufferProvider] — a non-auto-disposed
/// `NotifierProvider<BufferNotifierImpl, BufferState>` — so that buffer
/// state survives zero-listener windows (FR-10, EC-05, §5.3).
///
/// Invariant: no method here writes buffer text to any persistent store
/// (NFR-09 / R-01).  Recovery persistence is wired externally on
/// background/detach, not through this class.
class BufferNotifierImpl extends Notifier<BufferState>
    implements BufferNotifier {
  @override
  BufferState build() => BufferState.empty();

  @override
  void updateText(String text) {
    state = state.copyWith(text: text);
  }

  @override
  void reset() {
    state = BufferState.empty();
  }

  @override
  void populate(String text) {
    state = state.copyWith(text: text);
  }
}
