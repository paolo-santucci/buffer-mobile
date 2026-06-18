import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foglietto/domain/buffer/buffer_notifier_impl.dart';
import 'package:foglietto/domain/buffer/buffer_state.dart';

/// The single, non-auto-disposed buffer-state hub (FR-10, EC-05, §5.3).
///
/// Declared as a top-level constant so that every consumer references the
/// SAME provider instance — one hub, one state.  Non-auto-disposed means
/// state survives windows where there are zero active listeners (e.g., when
/// the editor is briefly unmounted during a navigation transition).
///
/// Usage:
///   ```dart
///   // Read current state:
///   final text = ref.watch(bufferProvider).text;
///
///   // Mutate:
///   ref.read(bufferProvider.notifier).updateText('hello');
///   ref.read(bufferProvider.notifier).reset();
///   ```
final bufferProvider = NotifierProvider<BufferNotifierImpl, BufferState>(
  BufferNotifierImpl.new,
);
