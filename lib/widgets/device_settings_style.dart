import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/workout/workout_visuals.dart';

abstract final class DeviceSettingsStyle {
  static Color accent(SettingType type) => switch (type) {
    SettingType.basic => WorkoutVisuals.mint,
    SettingType.bluetooth => WorkoutVisuals.power,
    SettingType.network => WorkoutVisuals.gold,
    SettingType.advanced => WorkoutVisuals.heartRate,
  };

  static IconData icon(SettingType type) => switch (type) {
    SettingType.basic => Icons.tune_rounded,
    SettingType.bluetooth => Icons.bluetooth_rounded,
    SettingType.network => Icons.wifi_rounded,
    SettingType.advanced => Icons.build_outlined,
  };

  static String description(SettingType type) => switch (type) {
    SettingType.basic => 'Gearing and everyday ride preferences',
    SettingType.bluetooth => 'Power meters and heart-rate sensors',
    SettingType.network => 'Wi-Fi and network connections',
    SettingType.advanced => 'Motor tuning and device behavior',
  };

  static BoxDecoration panel(Color accent) => BoxDecoration(
    color: WorkoutVisuals.panel,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: accent.withValues(alpha: .25)),
  );
}

/// Scoped to device settings, including editors opened from other workflows.
class DeviceSettingsSurface extends StatelessWidget {
  const DeviceSettingsSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: WorkoutVisuals.ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: WorkoutVisuals.mint,
        brightness: Brightness.dark,
      ).copyWith(surface: WorkoutVisuals.panel),
      dialogTheme: const DialogThemeData(backgroundColor: WorkoutVisuals.panel),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WorkoutVisuals.ink,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    ),
    child: child,
  );
}
