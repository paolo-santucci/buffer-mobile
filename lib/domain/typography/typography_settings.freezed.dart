// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'typography_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$TypographySettings {
  int get fontSizeIndex => throw _privateConstructorUsedError;
  bool get useMonospaceFont => throw _privateConstructorUsedError;

  /// Create a copy of TypographySettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TypographySettingsCopyWith<TypographySettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TypographySettingsCopyWith<$Res> {
  factory $TypographySettingsCopyWith(
    TypographySettings value,
    $Res Function(TypographySettings) then,
  ) = _$TypographySettingsCopyWithImpl<$Res, TypographySettings>;
  @useResult
  $Res call({int fontSizeIndex, bool useMonospaceFont});
}

/// @nodoc
class _$TypographySettingsCopyWithImpl<$Res, $Val extends TypographySettings>
    implements $TypographySettingsCopyWith<$Res> {
  _$TypographySettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TypographySettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? fontSizeIndex = null, Object? useMonospaceFont = null}) {
    return _then(
      _value.copyWith(
            fontSizeIndex: null == fontSizeIndex
                ? _value.fontSizeIndex
                : fontSizeIndex // ignore: cast_nullable_to_non_nullable
                      as int,
            useMonospaceFont: null == useMonospaceFont
                ? _value.useMonospaceFont
                : useMonospaceFont // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$TypographySettingsImplCopyWith<$Res>
    implements $TypographySettingsCopyWith<$Res> {
  factory _$$TypographySettingsImplCopyWith(
    _$TypographySettingsImpl value,
    $Res Function(_$TypographySettingsImpl) then,
  ) = __$$TypographySettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int fontSizeIndex, bool useMonospaceFont});
}

/// @nodoc
class __$$TypographySettingsImplCopyWithImpl<$Res>
    extends _$TypographySettingsCopyWithImpl<$Res, _$TypographySettingsImpl>
    implements _$$TypographySettingsImplCopyWith<$Res> {
  __$$TypographySettingsImplCopyWithImpl(
    _$TypographySettingsImpl _value,
    $Res Function(_$TypographySettingsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TypographySettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? fontSizeIndex = null, Object? useMonospaceFont = null}) {
    return _then(
      _$TypographySettingsImpl(
        fontSizeIndex: null == fontSizeIndex
            ? _value.fontSizeIndex
            : fontSizeIndex // ignore: cast_nullable_to_non_nullable
                  as int,
        useMonospaceFont: null == useMonospaceFont
            ? _value.useMonospaceFont
            : useMonospaceFont // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$TypographySettingsImpl extends _TypographySettings {
  const _$TypographySettingsImpl({
    this.fontSizeIndex = 8,
    this.useMonospaceFont = true,
  }) : super._();

  @override
  @JsonKey()
  final int fontSizeIndex;
  @override
  @JsonKey()
  final bool useMonospaceFont;

  @override
  String toString() {
    return 'TypographySettings(fontSizeIndex: $fontSizeIndex, useMonospaceFont: $useMonospaceFont)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TypographySettingsImpl &&
            (identical(other.fontSizeIndex, fontSizeIndex) ||
                other.fontSizeIndex == fontSizeIndex) &&
            (identical(other.useMonospaceFont, useMonospaceFont) ||
                other.useMonospaceFont == useMonospaceFont));
  }

  @override
  int get hashCode => Object.hash(runtimeType, fontSizeIndex, useMonospaceFont);

  /// Create a copy of TypographySettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TypographySettingsImplCopyWith<_$TypographySettingsImpl> get copyWith =>
      __$$TypographySettingsImplCopyWithImpl<_$TypographySettingsImpl>(
        this,
        _$identity,
      );
}

abstract class _TypographySettings extends TypographySettings {
  const factory _TypographySettings({
    final int fontSizeIndex,
    final bool useMonospaceFont,
  }) = _$TypographySettingsImpl;
  const _TypographySettings._() : super._();

  @override
  int get fontSizeIndex;
  @override
  bool get useMonospaceFont;

  /// Create a copy of TypographySettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TypographySettingsImplCopyWith<_$TypographySettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
