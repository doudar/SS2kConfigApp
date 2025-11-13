import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Removed json_theme dependency due to Flutter 3.38 theming API changes.
// Implement minimal JSON -> ThemeData decoding inline to avoid
// incompatibilities between AppBarTheme/AppBarThemeData, etc.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themePreferenceKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.system;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  ThemeMode get themeMode => _themeMode;
  ThemeData? get lightTheme => _lightTheme;
  ThemeData? get darkTheme => _darkTheme;

  ThemeProvider() {
    _loadThemePreference();
    _loadThemes();
  }

  Future<void> _loadThemes() async {
    // Load light theme
    final lightThemeStr = await rootBundle.loadString('assets/appainter_theme.json');
    final lightThemeJson = jsonDecode(lightThemeStr);
    _lightTheme = _decodeTheme(lightThemeJson);

    // Load dark theme
    final darkThemeStr = await rootBundle.loadString('assets/appainter_theme_dark.json');
    final darkThemeJson = jsonDecode(darkThemeStr);
    _darkTheme = _decodeTheme(darkThemeJson);

    notifyListeners();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themePreferenceKey);
    if (savedTheme != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.toString() == savedTheme,
        orElse: () => ThemeMode.system,
      );
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePreferenceKey, mode.toString());
    notifyListeners();
  }
}

// --- Minimal Theme JSON Decoder (supports subset used by exported Appainter JSON) ---

ThemeData _decodeTheme(Map<String, dynamic> json) {
  final brightnessStr = (json['brightness'] ?? 'light').toString().toLowerCase();
  final brightness = brightnessStr == 'dark' ? Brightness.dark : Brightness.light;
  final cs = Map<String, dynamic>.from(json['colorScheme'] ?? {});

  Color parseColor(dynamic v) {
    if (v == null) return const Color(0x00000000);
    final s = v.toString();
    if (s.startsWith('#')) {
      // Supports #AARRGGBB and #RRGGBB
      final hex = s.substring(1);
      final value = hex.length == 6 ? int.parse('ff$hex', radix: 16) : int.parse(hex, radix: 16);
      return Color(value);
    }
    return const Color(0x00000000);
  }

  ColorScheme colorScheme = ColorScheme(
    brightness: brightness,
    primary: parseColor(cs['primary']),
    onPrimary: parseColor(cs['onPrimary']),
    primaryContainer: parseColor(cs['primaryContainer']),
    onPrimaryContainer: parseColor(cs['onPrimaryContainer']),
    secondary: parseColor(cs['secondary']),
    onSecondary: parseColor(cs['onSecondary']),
    secondaryContainer: parseColor(cs['secondaryContainer']),
    onSecondaryContainer: parseColor(cs['onSecondaryContainer']),
    tertiary: parseColor(cs['tertiary'] ?? cs['secondary']),
    onTertiary: parseColor(cs['onTertiary'] ?? cs['onSecondary']),
    tertiaryContainer: parseColor(cs['tertiaryContainer'] ?? cs['secondaryContainer']),
    onTertiaryContainer: parseColor(cs['onTertiaryContainer'] ?? cs['onSecondaryContainer']),
    error: parseColor(cs['error']),
    onError: parseColor(cs['onError']),
    errorContainer: parseColor(cs['errorContainer'] ?? cs['error']),
    onErrorContainer: parseColor(cs['onErrorContainer'] ?? cs['onError']),
    surface: parseColor(cs['surface'] ?? cs['background']),
    onSurface: parseColor(cs['onSurface']),
    surfaceContainerHighest: parseColor(cs['surfaceVariant'] ?? cs['surface']),
    onSurfaceVariant: parseColor(cs['onSurfaceVariant'] ?? cs['onSurface']),
    outline: parseColor(cs['outline']),
    outlineVariant: parseColor(cs['outlineVariant'] ?? cs['outline']),
    shadow: parseColor(cs['shadow'] ?? '#00000000'),
    scrim: parseColor(cs['scrim'] ?? '#00000000'),
    inverseSurface: parseColor(cs['inverseSurface'] ?? cs['surface']),
    onInverseSurface: parseColor(cs['onInverseSurface'] ?? cs['onSurface']),
    inversePrimary: parseColor(cs['inversePrimary'] ?? cs['primary']),
    surfaceTint: parseColor(cs['surfaceTint'] ?? cs['primary']),
  );

  TextTheme parseTextTheme(Map<String, dynamic>? jsonTheme) {
    if (jsonTheme == null) return const TextTheme();
    TextStyle? styleFor(String key) {
      final m = jsonTheme[key];
      if (m is Map<String, dynamic>) {
        int? weightFrom(String? fw) {
          if (fw == null) return null;
          if (fw.startsWith('w')) {
            return int.tryParse(fw.substring(1));
          }
          return null;
        }
        return TextStyle(
          color: parseColor(m['color']),
          fontFamily: m['fontFamily'],
          fontSize: (m['fontSize'] is num) ? (m['fontSize'] as num).toDouble() : null,
          fontWeight: () {
            final w = weightFrom(m['fontWeight']?.toString());
            if (w == null) return null;
            final idx = ((w ~/ 100) - 1).clamp(0, FontWeight.values.length - 1);
            return FontWeight.values[idx];
          }(),
          letterSpacing: (m['letterSpacing'] is num) ? (m['letterSpacing'] as num).toDouble() : null,
        );
      }
      return null;
    }
    return TextTheme(
      displayLarge: styleFor('displayLarge'),
      displayMedium: styleFor('displayMedium'),
      displaySmall: styleFor('displaySmall'),
      headlineLarge: styleFor('headlineLarge'),
      headlineMedium: styleFor('headlineMedium'),
      headlineSmall: styleFor('headlineSmall'),
      titleLarge: styleFor('titleLarge'),
      titleMedium: styleFor('titleMedium'),
      titleSmall: styleFor('titleSmall'),
      bodyLarge: styleFor('bodyLarge'),
      bodyMedium: styleFor('bodyMedium'),
      bodySmall: styleFor('bodySmall'),
      labelLarge: styleFor('labelLarge'),
      labelMedium: styleFor('labelMedium'),
      labelSmall: styleFor('labelSmall'),
    );
  }

  final textTheme = parseTextTheme(json['textTheme'] as Map<String, dynamic>?);
  final useMaterial3 = json['useMaterial3'] == true;

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    useMaterial3: useMaterial3,
    textTheme: textTheme,
    scaffoldBackgroundColor: parseColor(json['scaffoldBackgroundColor']),
    primaryColor: parseColor(json['primaryColor'] ?? cs['primary']),
    splashColor: parseColor(json['splashColor'] ?? '#00000000'),
    dividerColor: parseColor(json['dividerColor'] ?? '#00000000'),
  );
}