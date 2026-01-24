/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/ss2k_app_bar.dart';
import '../utils/snackbar.dart';

import '../utils/bledata.dart';
import '../utils/presets.dart';
import '../utils/constants.dart';
import 'settings_category_screen.dart';

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
      Timer(Duration(seconds: 2), () {
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

  Widget _buildCategoryTile(BuildContext context, String title, SettingType type, IconData icon) {
    Color color = type.color;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SettingsCategoryScreen(
                device: widget.device,
                title: title,
                settingType: type,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.7),
                color.withOpacity(0.3),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: Colors.white),
              SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Size _size = MediaQuery.of(context).size; // Unused
    _refreshBlocker = true;
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: SS2KAppBar(
          device: widget.device,
          title: "Settings",
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                color: Colors.blueGrey[800],
                child: ListTile(
                  contentPadding: EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blueGrey[600],
                    radius: 30,
                    child: Icon(Icons.settings_system_daydream, size: 30, color: Colors.white),
                  ),
                  title: Text(
                    'Settings Manager',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  subtitle: Text(
                    'Load, Save, Import & Export Configuration',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () => PresetManager.showPresetsMenu(context, bleData, widget.device),
                  trailing: Icon(Icons.chevron_right, color: Colors.white),
                ),
              ),
              SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildCategoryTile(
                        context, "Basic Settings", SettingType.basic, Icons.settings),
                    _buildCategoryTile(
                        context, "Bluetooth Settings", SettingType.bluetooth, Icons.bluetooth),
                    _buildCategoryTile(
                        context, "Network Settings", SettingType.network, Icons.wifi),
                    _buildCategoryTile(
                        context, "Advanced Settings", SettingType.advanced, Icons.build),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
