/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/ss2k_app_bar.dart';
import '../widgets/device_settings_style.dart';
import '../utils/workout/workout_visuals.dart';
import '../utils/snackbar.dart';

import '../utils/device_data.dart';
import '../utils/presets.dart';
import '../utils/constants.dart';
import 'settings_category_screen.dart';

class SettingsScreen extends StatefulWidget {
  final BluetoothDevice device;
  const SettingsScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DeviceData deviceData;
  bool _openingBackups = false;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
  }

  Widget _buildCategoryTile(
    BuildContext context,
    String title,
    SettingType type,
    IconData icon,
  ) {
    final color = DeviceSettingsStyle.accent(type);
    return Material(
      color: WorkoutVisuals.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: .3)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsCategoryScreen(
              device: widget.device,
              title: title,
              settingType: type,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                DeviceSettingsStyle.description(type),
                style: const TextStyle(
                  color: WorkoutVisuals.muted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      DeviceSettingsSurface(child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: SS2KAppBar(
          device: widget.device,
          title: "Settings",
          firmwareOnlyDeviceHeader: true,
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final width = math.min(bounds.maxWidth - 24, 1000.0);
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns = bounds.maxWidth < 500 && scale > 1.4
                  ? 1
                  : bounds.maxWidth >= 760
                  ? 4
                  : 2;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 8, 4, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MAKE IT YOUR RIDE',
                                style: TextStyle(
                                  color: WorkoutVisuals.mint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Your SmartSpin2k setup',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: WorkoutVisuals.gold.withValues(alpha: .25),
                            ),
                          ),
                          color: WorkoutVisuals.panel,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: WorkoutVisuals.gold.withValues(
                                alpha: .12,
                              ),
                              radius: 22,
                              child: Icon(
                                Icons.settings_backup_restore,
                                size: 24,
                                color: WorkoutVisuals.gold,
                              ),
                            ),
                            title: Text(
                              'Save & restore settings',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              _openingBackups
                                  ? 'Reading settings from SmartSpin2k…'
                                  : 'Save a copy, restore a setup, or share a settings file',
                              style: TextStyle(
                                color: WorkoutVisuals.muted,
                                height: 1.4,
                              ),
                            ),
                            onTap: _openingBackups
                                ? null
                                : () async {
                                    // Preset operations are the one settings workflow that
                                    // needs an authoritative snapshot of every setting.
                                    setState(() => _openingBackups = true);
                                    try {
                                      await deviceData
                                          .requestAllEditableSettings(
                                            widget.device,
                                          );
                                      if (!context.mounted) return;
                                      setState(() => _openingBackups = false);
                                      await PresetManager.showPresetsMenu(
                                        context,
                                        deviceData,
                                        widget.device,
                                      );
                                    } catch (e) {
                                      if (context.mounted) {
                                        Snackbar.show(
                                          ABC.c,
                                          'Could not read settings. Check your SmartSpin2k connection and try again.',
                                          success: false,
                                        );
                                      }
                                    } finally {
                                      if (mounted)
                                        setState(() => _openingBackups = false);
                                    }
                                  },
                            trailing: _openingBackups
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                        SizedBox(height: 20),
                        GridView.count(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio:
                              ((width - (columns - 1) * 12) / columns) /
                              (170 * scale.clamp(1.0, 2.5)),
                          children: [
                            _buildCategoryTile(
                              context,
                              "Basic",
                              SettingType.basic,
                              DeviceSettingsStyle.icon(SettingType.basic),
                            ),
                            _buildCategoryTile(
                              context,
                              "Bluetooth",
                              SettingType.bluetooth,
                              DeviceSettingsStyle.icon(SettingType.bluetooth),
                            ),
                            _buildCategoryTile(
                              context,
                              "Network",
                              SettingType.network,
                              DeviceSettingsStyle.icon(SettingType.network),
                            ),
                            _buildCategoryTile(
                              context,
                              "Advanced",
                              SettingType.advanced,
                              DeviceSettingsStyle.icon(SettingType.advanced),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
