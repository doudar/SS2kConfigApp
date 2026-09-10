import 'package:flutter/material.dart';

/// The Save your ride visual language, scoped to workout menus and dialogs.
/// Colors follow the app's light/dark ColorScheme; geometry lives here.
abstract final class WorkoutSettingsTheme {
  static const maxWidth = 520.0;
  static const browserWidth = 760.0;
  static const dialogRadius = 26.0;
  static const panelRadius = 18.0;
  static const actionRadius = 16.0;
  static const inset = EdgeInsets.symmetric(horizontal: 20, vertical: 24);
  static const headerPadding = EdgeInsets.all(24);
  static const bodyPadding = EdgeInsets.fromLTRB(24, 0, 24, 20);

  static BoxDecoration panel(ColorScheme colors) => BoxDecoration(
    color: colors.onSurface.withValues(alpha: .035),
    borderRadius: BorderRadius.circular(panelRadius),
    border: Border.all(color: colors.outline.withValues(alpha: .15)),
  );

  static ThemeData resolve(ThemeData base) {
    final colors = base.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(actionRadius),
      side: BorderSide(color: colors.outline.withValues(alpha: .25)),
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.primary,
        textColor: colors.onSurface,
        contentPadding: const EdgeInsets.all(16),
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.onSurface.withValues(alpha: .035),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
