// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'buffer_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$BufferState {
  String get text => throw _privateConstructorUsedError;
  bool get isDirty => throw _privateConstructorUsedError;

  /// Create a copy of BufferState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BufferStateCopyWith<BufferState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BufferStateCopyWith<$Res> {
  factory $BufferStateCopyWith(
    BufferState value,
    $Res Function(BufferState) then,
  ) = _$BufferStateCopyWithImpl<$Res, BufferState>;
  @useResult
  $Res call({String text, bool isDirty});
}

/// @nodoc
class _$BufferStateCopyWithImpl<$Res, $Val extends BufferState>
    implements $BufferStateCopyWith<$Res> {
  _$BufferStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BufferState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? text = null, Object? isDirty = null}) {
    return _then(
      _value.copyWith(
            text: null == text
                ? _value.text
                : text // ignore: cast_nullable_to_non_nullable
                      as String,
            isDirty: null == isDirty
                ? _value.isDirty
                : isDirty // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$BufferStateImplCopyWith<$Res>
    implements $BufferStateCopyWith<$Res> {
  factory _$$BufferStateImplCopyWith(
    _$BufferStateImpl value,
    $Res Function(_$BufferStateImpl) then,
  ) = __$$BufferStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String text, bool isDirty});
}

/// @nodoc
class __$$BufferStateImplCopyWithImpl<$Res>
    extends _$BufferStateCopyWithImpl<$Res, _$BufferStateImpl>
    implements _$$BufferStateImplCopyWith<$Res> {
  __$$BufferStateImplCopyWithImpl(
    _$BufferStateImpl _value,
    $Res Function(_$BufferStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of BufferState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? text = null, Object? isDirty = null}) {
    return _then(
      _$BufferStateImpl(
        text: null == text
            ? _value.text
            : text // ignore: cast_nullable_to_non_nullable
                  as String,
        isDirty: null == isDirty
            ? _value.isDirty
            : isDirty // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$BufferStateImpl implements _BufferState {
  const _$BufferStateImpl({this.text = '', this.isDirty = false});

  @override
  @JsonKey()
  final String text;
  @override
  @JsonKey()
  final bool isDirty;

  @override
  String toString() {
    return 'BufferState(text: $text, isDirty: $isDirty)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BufferStateImpl &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.isDirty, isDirty) || other.isDirty == isDirty));
  }

  @override
  int get hashCode => Object.hash(runtimeType, text, isDirty);

  /// Create a copy of BufferState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BufferStateImplCopyWith<_$BufferStateImpl> get copyWith =>
      __$$BufferStateImplCopyWithImpl<_$BufferStateImpl>(this, _$identity);
}

abstract class _BufferState implements BufferState {
  const factory _BufferState({final String text, final bool isDirty}) =
      _$BufferStateImpl;

  @override
  String get text;
  @override
  bool get isDirty;

  /// Create a copy of BufferState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BufferStateImplCopyWith<_$BufferStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
