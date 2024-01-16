import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

const customcolor1 = Color(0xFFEE0033);
const customcolor2 = Color(0xFF000000);


CustomColors lightCustomColors = const CustomColors(
  sourceCustomcolor1: Color(0xFFEE0033),
  customcolor1: Color(0xFFBF0027),
  onCustomcolor1: Color(0xFFFFFFFF),
  customcolor1Container: Color(0xFFFFDAD8),
  onCustomcolor1Container: Color(0xFF410007),
  sourceCustomcolor2: Color(0xFF000000),
  customcolor2: Color(0xFF984061),
  onCustomcolor2: Color(0xFFFFFFFF),
  customcolor2Container: Color(0xFFFFD9E2),
  onCustomcolor2Container: Color(0xFF3E001D),
);

CustomColors darkCustomColors = const CustomColors(
  sourceCustomcolor1: Color(0xFFEE0033),
  customcolor1: Color(0xFFFFB3B0),
  onCustomcolor1: Color(0xFF680010),
  customcolor1Container: Color(0xFF92001B),
  onCustomcolor1Container: Color(0xFFFFDAD8),
  sourceCustomcolor2: Color(0xFF000000),
  customcolor2: Color(0xFFFFB1C8),
  onCustomcolor2: Color(0xFF5E1133),
  customcolor2Container: Color(0xFF7B2949),
  onCustomcolor2Container: Color(0xFFFFD9E2),
);



/// Defines a set of custom colors, each comprised of 4 complementary tones.
///
/// See also:
///   * <https://m3.material.io/styles/color/the-color-system/custom-colors>
@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  const CustomColors({
    required this.sourceCustomcolor1,
    required this.customcolor1,
    required this.onCustomcolor1,
    required this.customcolor1Container,
    required this.onCustomcolor1Container,
    required this.sourceCustomcolor2,
    required this.customcolor2,
    required this.onCustomcolor2,
    required this.customcolor2Container,
    required this.onCustomcolor2Container,
  });

  final Color? sourceCustomcolor1;
  final Color? customcolor1;
  final Color? onCustomcolor1;
  final Color? customcolor1Container;
  final Color? onCustomcolor1Container;
  final Color? sourceCustomcolor2;
  final Color? customcolor2;
  final Color? onCustomcolor2;
  final Color? customcolor2Container;
  final Color? onCustomcolor2Container;

  @override
  CustomColors copyWith({
    Color? sourceCustomcolor1,
    Color? customcolor1,
    Color? onCustomcolor1,
    Color? customcolor1Container,
    Color? onCustomcolor1Container,
    Color? sourceCustomcolor2,
    Color? customcolor2,
    Color? onCustomcolor2,
    Color? customcolor2Container,
    Color? onCustomcolor2Container,
  }) {
    return CustomColors(
      sourceCustomcolor1: sourceCustomcolor1 ?? this.sourceCustomcolor1,
      customcolor1: customcolor1 ?? this.customcolor1,
      onCustomcolor1: onCustomcolor1 ?? this.onCustomcolor1,
      customcolor1Container: customcolor1Container ?? this.customcolor1Container,
      onCustomcolor1Container: onCustomcolor1Container ?? this.onCustomcolor1Container,
      sourceCustomcolor2: sourceCustomcolor2 ?? this.sourceCustomcolor2,
      customcolor2: customcolor2 ?? this.customcolor2,
      onCustomcolor2: onCustomcolor2 ?? this.onCustomcolor2,
      customcolor2Container: customcolor2Container ?? this.customcolor2Container,
      onCustomcolor2Container: onCustomcolor2Container ?? this.onCustomcolor2Container,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) {
      return this;
    }
    return CustomColors(
      sourceCustomcolor1: Color.lerp(sourceCustomcolor1, other.sourceCustomcolor1, t),
      customcolor1: Color.lerp(customcolor1, other.customcolor1, t),
      onCustomcolor1: Color.lerp(onCustomcolor1, other.onCustomcolor1, t),
      customcolor1Container: Color.lerp(customcolor1Container, other.customcolor1Container, t),
      onCustomcolor1Container: Color.lerp(onCustomcolor1Container, other.onCustomcolor1Container, t),
      sourceCustomcolor2: Color.lerp(sourceCustomcolor2, other.sourceCustomcolor2, t),
      customcolor2: Color.lerp(customcolor2, other.customcolor2, t),
      onCustomcolor2: Color.lerp(onCustomcolor2, other.onCustomcolor2, t),
      customcolor2Container: Color.lerp(customcolor2Container, other.customcolor2Container, t),
      onCustomcolor2Container: Color.lerp(onCustomcolor2Container, other.onCustomcolor2Container, t),
    );
  }

  /// Returns an instance of [CustomColors] in which the following custom
  /// colors are harmonized with [dynamic]'s [ColorScheme.primary].
  ///   * [CustomColors.sourceCustomcolor1]
  ///   * [CustomColors.customcolor1]
  ///   * [CustomColors.onCustomcolor1]
  ///   * [CustomColors.customcolor1Container]
  ///   * [CustomColors.onCustomcolor1Container]
  ///   * [CustomColors.sourceCustomcolor2]
  ///   * [CustomColors.customcolor2]
  ///   * [CustomColors.onCustomcolor2]
  ///   * [CustomColors.customcolor2Container]
  ///   * [CustomColors.onCustomcolor2Container]
  ///
  /// See also:
  ///   * <https://m3.material.io/styles/color/the-color-system/custom-colors#harmonization>
  CustomColors harmonized(ColorScheme dynamic) {
    return copyWith(
      sourceCustomcolor1: sourceCustomcolor1!.harmonizeWith(dynamic.primary),
      customcolor1: customcolor1!.harmonizeWith(dynamic.primary),
      onCustomcolor1: onCustomcolor1!.harmonizeWith(dynamic.primary),
      customcolor1Container: customcolor1Container!.harmonizeWith(dynamic.primary),
      onCustomcolor1Container: onCustomcolor1Container!.harmonizeWith(dynamic.primary),
      sourceCustomcolor2: sourceCustomcolor2!.harmonizeWith(dynamic.primary),
      customcolor2: customcolor2!.harmonizeWith(dynamic.primary),
      onCustomcolor2: onCustomcolor2!.harmonizeWith(dynamic.primary),
      customcolor2Container: customcolor2Container!.harmonizeWith(dynamic.primary),
      onCustomcolor2Container: onCustomcolor2Container!.harmonizeWith(dynamic.primary),
    );
  }
}