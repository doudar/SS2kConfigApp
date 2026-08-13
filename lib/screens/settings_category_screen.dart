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
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
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

    _connectionStateSubscription = this.widget.device.connectionState.listen((
      state,
    ) async {
      if (mounted) {
        setState(() {});
      }
    });

    _characteristicChangeSubscription = deviceData.characteristicChanges.listen((
      event,
    ) {
      if (mounted && _categorySettingNames.contains(event.vName)) {
        setState(() {});
      }
    });

    unawaited(
      deviceData.requestSettingsForType(widget.device, widget.settingType),
    );
  }

  @override
  void dispose() {
    if (_charReceivedListener != null) {
      deviceData.charReceived.removeListener(_charReceivedListener!);
    }
    _connectionStateSubscription?.cancel();
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: widget.title,
        firmwareOnlyDeviceHeader: true,
      ),
      body: Center(
        child: Builder(
          builder: (context) {
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      clipBehavior: Clip.antiAlias,
                      children: settingsTiles,
                    ),
            );
          },
        ),
      ),
    );
  }
}
