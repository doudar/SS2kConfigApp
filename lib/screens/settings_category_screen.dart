/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/setting_tile.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/device_settings_style.dart';
import '../utils/workout/workout_visuals.dart';
import '../utils/device_data.dart';
import '../utils/constants.dart';

class SettingsCategoryScreen extends StatefulWidget {
  final BluetoothDevice device;
  final String title;
  final SettingType settingType;

  const SettingsCategoryScreen({
    Key? key,
    required this.device,
    required this.title,
    required this.settingType,
  }) : super(key: key);

  @override
  State<SettingsCategoryScreen> createState() => _SettingsCategoryScreenState();
}

class _SettingsCategoryScreenState extends State<SettingsCategoryScreen> {
  StreamSubscription<CharacteristicChangeEvent>?
  _characteristicChangeSubscription;
  VoidCallback? _charReceivedListener;
  late DeviceData deviceData;
  late Set<String> _categorySettingNames;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _categorySettingNames = deviceData.customCharacteristic
        .where(
          (c) =>
              c["isSetting"] == true && c["settingType"] == widget.settingType,
        )
        .map((c) => c["vName"].toString())
        .toSet();

    _charReceivedListener = () {
      if (mounted) {
        setState(() {});
      }
    };
    deviceData.charReceived.addListener(_charReceivedListener!);

    _characteristicChangeSubscription = deviceData.characteristicChanges.listen(
      (event) {
        if (mounted && _categorySettingNames.contains(event.vName)) {
          setState(() {});
        }
      },
    );

    unawaited(
      deviceData.requestSettingsForType(widget.device, widget.settingType),
    );
  }

  @override
  void dispose() {
    if (_charReceivedListener != null) {
      deviceData.charReceived.removeListener(_charReceivedListener!);
    }
    _characteristicChangeSubscription?.cancel();
    super.dispose();
  }

  List<Widget> buildSettingsList(BuildContext context) {
    List<Widget> settings = [];
    _newEntry(Map c) {
      if (this.deviceData.charReceived.value || this.deviceData.isSimulated) {
        final value = c["value"]?.toString();
        // Filter by isSetting AND the requested SettingType
        if (c["isSetting"] == true &&
            c["settingType"] == widget.settingType &&
            value != null &&
            value != "null") {
          settings.add(SettingTile(device: this.widget.device, c: c));
        }
      }
    }

    this.deviceData.customCharacteristic.forEach((c) => _newEntry(c));

    return settings;
  }

  @override
  Widget build(BuildContext context) => DeviceSettingsSurface(
    child: Builder(
      builder: (context) {
        final tiles = buildSettingsList(context);
        final accent = DeviceSettingsStyle.accent(widget.settingType);
        return Scaffold(
          appBar: SS2KAppBar(
            device: widget.device,
            title: widget.title,
            firmwareOnlyDeviceHeader: true,
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: tiles.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 20),
                            Text(
                              'Refreshing Data',
                              style: TextStyle(color: WorkoutVisuals.muted),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                            child: Row(
                              children: [
                                Icon(
                                  DeviceSettingsStyle.icon(widget.settingType),
                                  color: accent,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    DeviceSettingsStyle.description(
                                      widget.settingType,
                                    ),
                                    style: const TextStyle(
                                      color: WorkoutVisuals.muted,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...tiles,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
