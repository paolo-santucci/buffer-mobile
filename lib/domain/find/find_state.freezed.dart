// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'find_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$FindState {
  String get query => throw _privateConstructorUsedError;
  String get replaceTerm => throw _privateConstructorUsedError;
  List<MatchSpan> get matches => throw _privateConstructorUsedError;
  int? get currentMatchIndex =>
      throw _privateConstructorUsedError; // null ⇒ no current match (FR-05/FR-15)
  bool get active => throw _privateConstructorUsedError;

  /// Create a copy of FindState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FindStateCopyWith<FindState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FindStateCopyWith<$Res> {
  factory $FindStateCopyWith(FindState value, $Res Function(FindState) then) =
      _$FindStateCopyWithImpl<$Res, FindState>;
  @useResult
  $Res call({
    String query,
    String replaceTerm,
    List<MatchSpan> matches,
    int? currentMatchIndex,
    bool active,
  });
}

/// @nodoc
class _$FindStateCopyWithImpl<$Res, $Val extends FindState>
    implements $FindStateCopyWith<$Res> {
  _$FindStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FindState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? query = null,
    Object? replaceTerm = null,
    Object? matches = null,
    Object? currentMatchIndex = freezed,
    Object? active = null,
  }) {
    return _then(
      _value.copyWith(
            query: null == query
                ? _value.query
                : query // ignore: cast_nullable_to_non_nullable
                      as String,
            replaceTerm: null == replaceTerm
                ? _value.replaceTerm
                : replaceTerm // ignore: cast_nullable_to_non_nullable
                      as String,
            matches: null == matches
                ? _value.matches
                : matches // ignore: cast_nullable_to_non_nullable
                      as List<MatchSpan>,
            currentMatchIndex: freezed == currentMatchIndex
                ? _value.currentMatchIndex
                : currentMatchIndex // ignore: cast_nullable_to_non_nullable
                      as int?,
            active: null == active
                ? _value.active
                : active // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FindStateImplCopyWith<$Res>
    implements $FindStateCopyWith<$Res> {
  factory _$$FindStateImplCopyWith(
    _$FindStateImpl value,
    $Res Function(_$FindStateImpl) then,
  ) = __$$FindStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String query,
    String replaceTerm,
    List<MatchSpan> matches,
    int? currentMatchIndex,
    bool active,
  });
}

/// @nodoc
class __$$FindStateImplCopyWithImpl<$Res>
    extends _$FindStateCopyWithImpl<$Res, _$FindStateImpl>
    implements _$$FindStateImplCopyWith<$Res> {
  __$$FindStateImplCopyWithImpl(
    _$FindStateImpl _value,
    $Res Function(_$FindStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FindState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? query = null,
    Object? replaceTerm = null,
    Object? matches = null,
    Object? currentMatchIndex = freezed,
    Object? active = null,
  }) {
    return _then(
      _$FindStateImpl(
        query: null == query
            ? _value.query
            : query // ignore: cast_nullable_to_non_nullable
                  as String,
        replaceTerm: null == replaceTerm
            ? _value.replaceTerm
            : replaceTerm // ignore: cast_nullable_to_non_nullable
                  as String,
        matches: null == matches
            ? _value._matches
            : matches // ignore: cast_nullable_to_non_nullable
                  as List<MatchSpan>,
        currentMatchIndex: freezed == currentMatchIndex
            ? _value.currentMatchIndex
            : currentMatchIndex // ignore: cast_nullable_to_non_nullable
                  as int?,
        active: null == active
            ? _value.active
            : active // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$FindStateImpl extends _FindState {
  const _$FindStateImpl({
    this.query = '',
    this.replaceTerm = '',
    final List<MatchSpan> matches = const <MatchSpan>[],
    this.currentMatchIndex,
    this.active = false,
  }) : _matches = matches,
       super._();

  @override
  @JsonKey()
  final String query;
  @override
  @JsonKey()
  final String replaceTerm;
  final List<MatchSpan> _matches;
  @override
  @JsonKey()
  List<MatchSpan> get matches {
    if (_matches is EqualUnmodifiableListView) return _matches;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_matches);
  }

  @override
  final int? currentMatchIndex;
  // null ⇒ no current match (FR-05/FR-15)
  @override
  @JsonKey()
  final bool active;

  @override
  String toString() {
    return 'FindState(query: $query, replaceTerm: $replaceTerm, matches: $matches, currentMatchIndex: $currentMatchIndex, active: $active)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FindStateImpl &&
            (identical(other.query, query) || other.query == query) &&
            (identical(other.replaceTerm, replaceTerm) ||
                other.replaceTerm == replaceTerm) &&
            const DeepCollectionEquality().equals(other._matches, _matches) &&
            (identical(other.currentMatchIndex, currentMatchIndex) ||
                other.currentMatchIndex == currentMatchIndex) &&
            (identical(other.active, active) || other.active == active));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    query,
    replaceTerm,
    const DeepCollectionEquality().hash(_matches),
    currentMatchIndex,
    active,
  );

  /// Create a copy of FindState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FindStateImplCopyWith<_$FindStateImpl> get copyWith =>
      __$$FindStateImplCopyWithImpl<_$FindStateImpl>(this, _$identity);
}

abstract class _FindState extends FindState {
  const factory _FindState({
    final String query,
    final String replaceTerm,
    final List<MatchSpan> matches,
    final int? currentMatchIndex,
    final bool active,
  }) = _$FindStateImpl;
  const _FindState._() : super._();

  @override
  String get query;
  @override
  String get replaceTerm;
  @override
  List<MatchSpan> get matches;
  @override
  int? get currentMatchIndex; // null ⇒ no current match (FR-05/FR-15)
  @override
  bool get active;

  /// Create a copy of FindState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FindStateImplCopyWith<_$FindStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
