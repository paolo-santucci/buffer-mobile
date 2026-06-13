import 'package:freezed_annotation/freezed_annotation.dart';

part 'typography_settings.freezed.dart';

@freezed
class TypographySettings with _$TypographySettings {
  const TypographySettings._();

  const factory TypographySettings({
    @Default(8) int fontSizeIndex,
    @Default(true) bool useMonospaceFont,
  }) = _TypographySettings;

  static const List<int> slotList = [
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    20,
    22,
    24,
    26,
    28,
    30,
    34,
    38,
  ];
}
