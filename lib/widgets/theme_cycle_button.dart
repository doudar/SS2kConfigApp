import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/theme_provider.dart';

class ThemeCycleButton extends StatelessWidget {
  const ThemeCycleButton({super.key});

  ThemeMode _nextThemeMode(ThemeMode current) {
    switch (current) {
      case ThemeMode.light:
        return ThemeMode.dark;
      case ThemeMode.dark:
        return ThemeMode.system;
      case ThemeMode.system:
        return ThemeMode.light;
    }
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  Future<void> _cycleThemeMode(BuildContext context) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final nextMode = _nextThemeMode(themeProvider.themeMode);
    await themeProvider.setThemeMode(nextMode);

    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.removeCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Theme: ${_themeModeLabel(nextMode)}'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.opacity),
      color: Colors.white,
      tooltip: 'Cycle Theme',
      onPressed: () => _cycleThemeMode(context),
    );
  }
}
