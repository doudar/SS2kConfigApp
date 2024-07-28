/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:SS2kConfigApp/utils/extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../widgets/device_header.dart';
import '../utils/bledata.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;
  const ShifterScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late BLEData bleData;
  late Map c;
  String t = "Loading";
  String statusString = '';
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  bool _refreshBlocker = false;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    this.bleData.customCharacteristic.forEach((i) => i["vName"] == shifterPositionVname ? c = i : ());
    t = c["value"] ?? "Loading";
    //special setup for demo mode
    if (bleData.isSimulated) {
      t = "0";
      return;
    }
    Timer.periodic(const Duration(seconds: 15), (refreshTimer) {
      if (!this.widget.device.isConnected) {
        try {
          this.widget.device.connectAndUpdateStream();
        } catch (e) {
          print("failed to reconnect.");
        }
      } else {
        if (mounted) {
        } else {
          refreshTimer.cancel();
        }
      }
    });
    rwSubscription();
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    this.bleData.isReadingOrWriting.removeListener(_rwListner);
    WakelockPlus.disable();
    super.dispose();
  }

  Future rwSubscription() async {
    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      bleData.isReadingOrWriting.addListener(_rwListner);
    });
  }

  void _rwListner() async {
    if (_refreshBlocker) {
      return;
    }
    _refreshBlocker = true;
    await Future.delayed(Duration(microseconds: 500));

    if (mounted) {
      setState(() {
        t = c["value"] ?? "Loading";
        statusString = bleData.ftmsData.watts.toString() +
            "w   " +
            bleData.ftmsData.cadence.toString() +
            "rpm " +
            (bleData.ftmsData.heartRate == 0 ? "" : bleData.ftmsData.heartRate.toString() + "bpm ");
      });
    }
    _refreshBlocker = false;
  }

  shift(int amount) {
    if (t != "Loading") {
      String _t = (int.parse(c["value"]) + amount).toString();
      c["value"] = _t;
      this.bleData.writeToSS2k(this.widget.device, c);
    }
    if (bleData.isSimulated) {
      setState(() {
        t = c["value"];
      });
    }
    WakelockPlus.enable();
  }

  Widget _buildShiftButton(IconData icon, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        elevation: 5,
        //foregroundColor: ThemeData().colorScheme.primaryContainer, // Button color
        // backgroundColor: ThemeData().colorScheme.onPrimaryContainer, // Icon color
        // shadowColor: ThemeData().colorScheme.background.withOpacity(0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))), // Oval shape
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 30), // Padding for oval shape
      ),
      child: Icon(icon, size: 60), // Icon size
      onPressed: onPressed,
    );
  }

  Widget _buildGearDisplay(String gearNumber) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: ThemeData().colorScheme.surface.withOpacity(0.5),
            spreadRadius: 5,
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        gearNumber,
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
        child: Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          "Virtual Shifter",
          style: TextStyle(
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.normal,
            fontSize: 20,
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            DeviceHeader(device: this.widget.device, connectOnly: true),
            Text(
              statusString,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            Spacer(flex: 1),
            _buildShiftButton(Icons.arrow_upward, () {
              shift(1);
            }),
            Spacer(flex: 1),
            _buildGearDisplay(t), // Assuming '0' is the current gear value
            Spacer(flex: 1),
            _buildShiftButton(Icons.arrow_downward, () {
              shift(-1);
            }),
            Spacer(flex: 1),
          ],
        ),
      ),
    ));
  }
}
