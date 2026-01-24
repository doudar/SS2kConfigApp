import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/theme_provider.dart';
import '../widgets/basic_app_bar.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BasicAppBar(
        title: "App Settings",
      ),
      body: ListView(
        children: [
          _buildThemeSection(context),
        ],
      ),
    );
  }

  Widget _buildThemeSection(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Theme',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          RadioGroup<ThemeMode>(
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                themeProvider.setThemeMode(value);
              }
            },
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}