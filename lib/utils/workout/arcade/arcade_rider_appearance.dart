import 'package:flutter/material.dart';

enum ArcadeHairStyle { short, curls, ponytail }

class ArcadeRiderAppearance {
  const ArcadeRiderAppearance({
    this.skin = const Color(0xffffc69b),
    this.hair = const Color(0xff583b30),
    this.jersey = const Color(0xffa78aff),
    this.shorts = const Color(0xff52476e),
    this.helmet = const Color(0xffffd477),
    this.bike = const Color(0xff74ffd3),
    this.shoes = const Color(0xfff1f5ff),
    this.hairStyle = ArcadeHairStyle.short,
  });
  final Color skin, hair, jersey, shorts, helmet, bike, shoes;
  final ArcadeHairStyle hairStyle;

  ArcadeRiderAppearance copyWith({
    Color? skin,
    Color? hair,
    Color? jersey,
    Color? shorts,
    Color? helmet,
    Color? bike,
    Color? shoes,
    ArcadeHairStyle? hairStyle,
  }) => ArcadeRiderAppearance(
    skin: skin ?? this.skin,
    hair: hair ?? this.hair,
    jersey: jersey ?? this.jersey,
    shorts: shorts ?? this.shorts,
    helmet: helmet ?? this.helmet,
    bike: bike ?? this.bike,
    shoes: shoes ?? this.shoes,
    hairStyle: hairStyle ?? this.hairStyle,
  );

  Map<String, Object> toJson() => {
    'skin': skin.toARGB32(),
    'hair': hair.toARGB32(),
    'jersey': jersey.toARGB32(),
    'shorts': shorts.toARGB32(),
    'helmet': helmet.toARGB32(),
    'bike': bike.toARGB32(),
    'shoes': shoes.toARGB32(),
    'hairStyle': hairStyle.name,
  };

  factory ArcadeRiderAppearance.fromJson(Object? data) {
    const defaults = ArcadeRiderAppearance();
    if (data is! Map) return defaults;
    Color color(String key, Color fallback) {
      final value = data[key];
      return value is int && value >= 0 && value <= 0xffffffff
          ? Color(0xff000000 | (value & 0xffffff))
          : fallback;
    }

    return ArcadeRiderAppearance(
      skin: color('skin', defaults.skin),
      hair: color('hair', defaults.hair),
      jersey: color('jersey', defaults.jersey),
      shorts: color('shorts', defaults.shorts),
      helmet: color('helmet', defaults.helmet),
      bike: color('bike', defaults.bike),
      shoes: color('shoes', defaults.shoes),
      hairStyle: ArcadeHairStyle.values.firstWhere(
        (style) => style.name == data['hairStyle'],
        orElse: () => defaults.hairStyle,
      ),
    );
  }
}
