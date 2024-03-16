
/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter/material.dart';

class MyAppThemes {
  static final lightTheme = ThemeData(
    colorScheme: lightColorScheme,
  );

  static final darkTheme = ThemeData(
   colorScheme: darkColorScheme,
  );
}

const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF3942F3),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE0E0FF),
  onPrimaryContainer: Color(0xFF00006E),
  secondary: Color(0xFF7A27E5),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFECDCFF),
  onSecondaryContainer: Color(0xFF280057),
  tertiary: Color(0xFFA900A9),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFD7F5),
  onTertiaryContainer: Color(0xFF380038),
  error: Color(0xFFBA1A1A),
  errorContainer: Color(0xFFFFDAD6),
  onError: Color(0xFFFFFFFF),
  onErrorContainer: Color(0xFF410002),
  background: Color(0xFFFFFBFF),
  onBackground: Color(0xFF410005),
  surface: Color(0xFFFFFBFF),
  onSurface: Color(0xFF410005),
  surfaceVariant: Color(0xFFE4E1EC),
  onSurfaceVariant: Color(0xFF46464F),
  outline: Color(0xFF777680),
  onInverseSurface: Color(0xFFFFEDEB),
  inverseSurface: Color(0xFF5F1416),
  inversePrimary: Color(0xFFBFC2FF),
  shadow: Color(0xFF000000),
  surfaceTint: Color(0xFF3942F3),
  outlineVariant: Color(0xFFC7C5D0),
  scrim: Color(0xFF000000),
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFBFC2FF),
  onPrimary: Color(0xFF0000AC),
  primaryContainer: Color(0xFF171DDD),
  onPrimaryContainer: Color(0xFFE0E0FF),
  secondary: Color(0xFFD6BAFF),
  onSecondary: Color(0xFF420089),
  secondaryContainer: Color(0xFF5F00C0),
  onSecondaryContainer: Color(0xFFECDCFF),
  tertiary: Color(0xFFFFAAF3),
  onTertiary: Color(0xFF5B005B),
  tertiaryContainer: Color(0xFF810081),
  onTertiaryContainer: Color(0xFFFFD7F5),
  error: Color(0xFFFFB4AB),
  errorContainer: Color(0xFF93000A),
  onError: Color(0xFF690005),
  onErrorContainer: Color(0xFFFFDAD6),
  background: Color(0xFF410005),
  onBackground: Color(0xFFFFDAD7),
  surface: Color(0xFF410005),
  onSurface: Color(0xFFFFDAD7),
  surfaceVariant: Color(0xFF46464F),
  onSurfaceVariant: Color(0xFFC7C5D0),
  outline: Color(0xFF91909A),
  onInverseSurface: Color(0xFF410005),
  inverseSurface: Color(0xFFFFDAD7),
  inversePrimary: Color(0xFF3942F3),
  shadow: Color(0xFF000000),
  surfaceTint: Color(0xFFBFC2FF),
  outlineVariant: Color(0xFF46464F),
  scrim: Color(0xFF000000),
);