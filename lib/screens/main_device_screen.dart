/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:SS2kConfigApp/widgets/device_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../screens/settings_screen.dart';
import '../screens/shifter_screen.dart';
import '../screens/firmware_update_screen.dart';

import '../utils/extra.dart';

import '../utils/bledata.dart';

class MainDeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const MainDeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<MainDeviceScreen> createState() => _MainDeviceScreenState();
}

class _MainDeviceScreenState extends State<MainDeviceScreen> {
  late BLEData bleData;
  
  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);
    this.bleData.connectionStateSubscription = widget.device.connectionState.listen((state) async {
      this.bleData.connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        this.bleData.services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected) {
        this.bleData.rssi.value = await widget.device.readRssi();
      }
      bleData.setupConnection(widget.device);
    });

    if (bleData.charReceived.value) {
      bleData.updateCustomCharacter(widget.device);
    } else {
      bleData.charReceived.addListener(_crListener);
    }
    bleData.isConnectingSubscription = widget.device.isConnecting.listen((value) {
      this.bleData.isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    this.bleData.isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      this.bleData.isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _crListener() {
    if (bleData.charReceived.value) {
      bleData.updateCustomCharacter(widget.device);
    }
  }

  @override
  void dispose() {
    this.bleData.connectionStateSubscription.cancel();
    this.bleData.isConnectingSubscription.cancel();
    this.bleData.isDisconnectingSubscription.cancel();
    this.bleData.charReceived.removeListener(_crListener);
    super.dispose();
  }

  Widget _buildCard(String assetPath, String title, VoidCallback onPressed) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ListTile(
            onTap: onPressed,
            leading: Image.asset(assetPath, width: 56, fit: BoxFit.cover),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Main Device Screen"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: EdgeInsets.all(8),
        children: <Widget>[
          DeviceHeader(device: widget.device,connectOnly: true),
          SizedBox(height: 20),
          _buildCard('assets/shiftscreen.png', "Virtual Shifter", () {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => ShifterScreen(device: widget.device)));
          }),
          _buildCard('assets/settingsScreen.png', "Settings", () {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => SettingsScreen(device: widget.device)));
          }),
          _buildCard('assets/GitHub-logo.png', "Update Firmware", () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => FirmwareUpdateScreen(device: widget.device)));
          }),
        ],
      ),
    );
  }
}
