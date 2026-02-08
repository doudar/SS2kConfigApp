/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

import 'package:ss2kconfigapp/screens/power_table_screen.dart';
import 'package:ss2kconfigapp/widgets/ss2k_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import '../screens/settings_screen.dart';
import '../screens/shifter_screen.dart';
import '../screens/firmware_update_screen.dart';
import '../screens/workout_screen.dart';
import '../screens/ble_log_screen.dart';

import '../utils/extra.dart';

import '../utils/bledata.dart';

class MainDeviceScreen extends StatefulWidget {
  final BleDevice device;
  const MainDeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<MainDeviceScreen> createState() => _MainDeviceScreenState();
}

class _MainDeviceScreenState extends State<MainDeviceScreen> {
  late BLEData bleData;
  bool _maintenanceExpanded = false;
  StreamSubscription<bool>? _connectionStateSubscription;
  StreamSubscription<bool>? _connectingSubscription;
  StreamSubscription<bool>? _disconnectingSubscription;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forBleDevice(widget.device);
    //Are we running a demo?
    if (widget.device.name == "SmartSpin2k Demo") {
      _demoDeviceSetup(context);
      return;
    }
    _initializeConnectionMonitoring();

    if (bleData.charReceived.value) {
      bleData.updateCustomCharacter();
    } else {
      bleData.charReceived.addListener(_crListener);
    }
    _connectingSubscription = widget.device.isConnecting.listen((value) {
      bleData.isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _disconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      bleData.isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _initializeConnectionMonitoring() {
    _loadInitialConnectionState();
    _connectionStateSubscription = UniversalBle.connectionStream(widget.device.deviceId).listen((connected) {
      _handleConnectionChange(connected);
    });
  }

  Future<void> _loadInitialConnectionState() async {
    try {
      final state = await UniversalBle.getConnectionState(widget.device.deviceId);
      await _handleConnectionChange(state == BleConnectionState.connected);
    } catch (_) {}
  }

  Future<void> _handleConnectionChange(bool connected) async {
    if (connected) {
      try {
        bleData.rssi.value = await widget.device.readRssi();
      } catch (_) {}
      bleData.services = [];
      await bleData.setupConnection(forceRediscover: true);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _crListener() {
    if (bleData.charReceived.value) {
      bleData.updateCustomCharacter();
    }
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _connectingSubscription?.cancel();
    _disconnectingSubscription?.cancel();
    bleData.charReceived.removeListener(_crListener);
    super.dispose();
  }

  //Setup a dummy demo device if we are running in demo mode
  void _demoDeviceSetup(context) {
    // Assuming bleData.services expects a similar structure
    this.bleData.isSimulated = true;

    bleData.customCharacteristic.forEach((key) {
      key["value"] = key["defaultData"] ?? "Default Value";
    });
    bleData.charReceived.value = true;
    bleData.firmwareVersion.value = "24.1.3";
    bleData.configAppCompatibleFirmware = true;
  }

  Widget _buildCard(String assetPath, String title, VoidCallback onPressed) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ListTile(
            onTap: onPressed,
            leading: SizedBox(
              width: 56,
              height: 56,
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                isAntiAlias: true,
              ),
            ),
            title: Text(title),
            trailing: IconButton(
              icon: Icon(Icons.arrow_forward),
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableMaintenanceCard() {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              setState(() {
                _maintenanceExpanded = !_maintenanceExpanded;
              });
            },
            leading: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                Icons.build_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text("Maintenance"),
            trailing: Icon(
              _maintenanceExpanded ? Icons.expand_less : Icons.expand_more,
            ),
          ),
          if (_maintenanceExpanded) ...[
            Divider(height: 1),
            ListTile(
              leading: SizedBox(
                width: 56,
                height: 56,
                child: Image.asset(
                  'assets/GitHub-logo.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  isAntiAlias: true,
                ),
              ),
              title: Text("Update Firmware"),
              trailing: Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => FirmwareUpdateScreen(device: this.widget.device),
                  ),
                );
              },
            ),
            Divider(height: 1),
            ListTile(
              leading: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  Icons.article_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text("View Logs"),
              trailing: Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => BleLogScreen(device: this.widget.device),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: "Main Device Screen",
      ),
      body: ListView(
        padding: EdgeInsets.all(8),
        children: <Widget>[
          SizedBox(height: 20),
          _buildCard('assets/shiftscreen.png', "Virtual Shifter", () {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => ShifterScreen(device: this.widget.device)));
          }),
          _buildCard('assets/settingsScreen.png', "Settings", () {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => SettingsScreen(device: this.widget.device)));
          }),
          _buildCard('assets/resistanceChart.png', "Power Table", () {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => PowerTableScreen(device: this.widget.device)));
          }),
          _buildCard('assets/Workout_Screen.png', "Workout", () {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => WorkoutScreen(device: this.widget.device)));
          }),
          _buildExpandableMaintenanceCard(),
        ],
      ),
    );
  }
}
