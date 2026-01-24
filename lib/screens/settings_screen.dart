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
import '../utils/snackbar.dart';

import '../utils/bledata.dart';
import '../utils/presets.dart';

class SettingsScreen extends StatefulWidget {
  final BluetoothDevice device;
  const SettingsScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>{
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  late BLEData bleData;
   bool _refreshBlocker = true;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);

    // If the data is simulated, wait for a second before calling setState
    if (bleData.isSimulated) {
      this.bleData.isReadingOrWriting.value = true;
      Timer(Duration(seconds: 2), () {
        this.bleData.isReadingOrWriting.value = false;
        if (mounted) {
          print("demo delay");
          setState(() {
            // This empty setState call triggers a rebuild of the widget
            // after the demo data has been "loaded"
          });
        }
      });
    } else {
  
    }

    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });
    
    // Subscribe to characteristic changes instead of isReadingOrWriting
    _characteristicChangeSubscription = bleData.characteristicChanges.listen((event) {
      if (!_refreshBlocker && mounted) {
        _refreshBlocker = true;
        Future.delayed(Duration(microseconds: 500), () {
          if (mounted) {
            setState(() {});
          }
          _refreshBlocker = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _characteristicChangeSubscription?.cancel();
    super.dispose();
  }

//Build the settings dropdowns
  List<Widget> buildSettings(BuildContext context) {
    List<Widget> settings = [];
    if (this.bleData.isReadingOrWriting.value) {
      Snackbar.show(ABC.c, "Data Loading, please wait ", success: true);
      setState(() {});
    } else {
      if (this.bleData.charReceived.value) {
        _newEntry(Map c) {
          if ((!this.bleData.services.isEmpty) || this.bleData.isSimulated) {
            if (c["isSetting"]) {
              settings.add(SettingTile(device: this.widget.device, c: c));
            }
          }
        }

        this.bleData.customCharacteristic.forEach((c) => _newEntry(c));
      }
    }
    _refreshBlocker = false;
    return settings;
  }

  @override
  Widget build(BuildContext context) {
    Size _size = MediaQuery.of(context).size;
    _refreshBlocker = true;
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: SS2KAppBar(
          device: widget.device,
          title: "Settings",
        ),
        body: Stack(
          children: <Widget>[
            Align(alignment:Alignment.topCenter ,child:SizedBox(
              height: _size.height * .90,
              width: _size.width * .80,
              child: ListView(clipBehavior: Clip.antiAlias, itemExtent: 100, children: <Widget>[
                Card(
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Center(
                    child: ListTile(
                      leading: Icon(Icons.settings_system_daydream, size: 30),
                      title: Text('Settings Manager'),
                      subtitle: Text('Load, Save, Import & Export Configuration'),
                      onTap: () => PresetManager.showPresetsMenu(context, bleData, widget.device),
                      trailing: Icon(Icons.chevron_right),
                    ),
                  ),
                ),
                ...buildSettings(context),
              ]),
            ),),
          ],
        ),
      ),
    );
  }
}
