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
import '../utils/bledata.dart';
import '../utils/constants.dart';
import '../utils/stream_extensions.dart';

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
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  late BLEData bleData;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);

    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      // Connection state changes don't require rebuilding the settings tiles
    });

    _characteristicChangeSubscription = bleData.characteristicChanges.listen((event) {
      // Settings tiles update via StreamBuilder, no need for setState
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _characteristicChangeSubscription?.cancel();
    super.dispose();
  }

  List<Widget> buildSettingsList(BuildContext context) {
    List<Widget> settings = [];
    if (this.bleData.charReceived.value) {
      _newEntry(Map c) {
        if ((!this.bleData.services.isEmpty) || this.bleData.isSimulated) {
          // Filter by isSetting AND the requested SettingType
          if (c["isSetting"] == true && c["settingType"] == widget.settingType && c["value"] != null) {
              settings.add(SettingTile(device: this.widget.device, c: c));
            }
          }
        }
        this.bleData.customCharacteristic.forEach((c) => _newEntry(c));
      }
    
    return settings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: widget.title,
      ),
      body: Center(
        child: StreamBuilder<CharacteristicChangeEvent>(
          stream: bleData.characteristicChanges,
          builder: (context, snapshot) {
            Size _size = MediaQuery.of(context).size;
            List<Widget> settingsTiles = buildSettingsList(context);

            return SizedBox(
              height: _size.height * .90,
              width: _size.width * .80,
              child: settingsTiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 20),
                          Text(
                            "Refreshing Data",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      clipBehavior: Clip.antiAlias,
                      // itemExtent: 100, // Removed fixed extent to allow variable height tiles if needed, or keep for consistency
                      children: settingsTiles,
                    ),
            );
          },
        ),
      ),
    );
  }
}
