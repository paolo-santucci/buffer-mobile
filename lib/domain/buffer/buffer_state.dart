import 'package:freezed_annotation/freezed_annotation.dart';

part 'buffer_state.freezed.dart';

@freezed
class BufferState with _$BufferState {
  const factory BufferState({
    @Default('') String text,
    @Default(false) bool isDirty,
  }) = _BufferState;

  factory BufferState.empty() => const BufferState();
}
