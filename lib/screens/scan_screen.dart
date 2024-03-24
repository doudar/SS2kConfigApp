/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/constants.dart';
import 'main_device_screen.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';
import '../widgets/scan_result_tile.dart';
import '../utils/demo.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results;
      if (mounted) {
        setState(() {});
      }
    }, onError: (e) {
      Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    super.dispose();
  }

  Future onScanPressed() async {
    try {
      // android is slow when asking for all advertisements,
      // so instead we only ask for 1/8 of them
      int divisor = Platform.isAndroid ? 8 : 1;
      await FlutterBluePlus.startScan(
          withServices: [Guid(csUUID)],
          timeout: const Duration(seconds: 15),
          continuousUpdates: true,
          continuousDivisor: divisor);
    } catch (e) {
      Snackbar.show(ABC.b, prettyException("Start Scan Error:", e), success: false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      Snackbar.show(ABC.b, prettyException("Stop Scan Error:", e), success: false);
    }
  }

  void onConnectPressed(BluetoothDevice device) {
    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan();
    }
    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });
    MaterialPageRoute route = MaterialPageRoute(
        builder: (context) => MainDeviceScreen(device: device), settings: RouteSettings(name: '/MainDeviceScreen'));
    Navigator.of(context).push(route);
  }

  Future onRefresh() {
    if (_isScanning == false) {
      FlutterBluePlus.startScan(withServices: [Guid(csUUID)], timeout: const Duration(seconds: 15));
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Widget buildScanButton(BuildContext context) {
    if (FlutterBluePlus.isScanningNow) {
      return ElevatedButton(
        child: const Icon(Icons.stop),
        onPressed: onStopPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeData().colorScheme.error, foregroundColor: ThemeData().colorScheme.onError,
          //maximumSize: Size.fromWidth(100),
        ),
      );
    } else {
      return ElevatedButton(
        child: const Text("SCAN"),
        onPressed: onScanPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeData().colorScheme.secondary, foregroundColor: ThemeData().colorScheme.onSecondary,
          //maximumSize: Size.fromWidth(50),
        ),
      );
    }
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _scanResults
        .map(
          (r) => ScanResultTile(
            result: r,
            onTap: () => onConnectPressed(r.device),
          ),
        )
        .toList();
  }

  void onDemoModePressed() {
    // Use the DemoDevice to simulate finding a SmartSpin2k device
    final demoDevice = DemoDevice();
    ScanResult simulatedScanResult = demoDevice.simulateSmartSpin2kScan();

    // Update the UI to display the simulated scan result
    setState(() {
      _scanResults = [simulatedScanResult]; // Replace existing scan results with the simulated one
      // If you want to keep existing scan results and add the simulated one, use `_scanResults.add(simulatedScanResult);` instead
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Find Your SmartSpin2k:'),
          titleTextStyle: TextStyle(
            fontSize: 30,
          ),
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                children: <Widget>[
                  ..._buildScanResultTiles(context),
                  if (_scanResults.isEmpty) // This line checks if there are no scan results
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Having Trouble?',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'If you cannot find your SmartSpin2k, try the following steps:',
                            style: TextStyle(fontSize: 18),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '1. Ensure your SmartSpin2k is powered on and within range.\n'
                            '2. Turn off and on the Bluetooth on your device, then try scanning again.\n'
                            '3. Restart your SmartSpin2k device.\n'
                            '4. Make sure the SmartSpin2k is not connected to another ConfigApp or QZ.\n'
                            '5. If none of these steps work, please contact support for further assistance.',
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(100, 8, 100, 15),
                    child: buildScanButton(context),
                  ),
                ],
              ),
            ),
            if (_scanResults.isEmpty)
              Positioned(
                left: 10, // Distance from left edge
                bottom: 10, // Distance from bottom edge
                child: ElevatedButton(
                  onPressed: onDemoModePressed,
                  child: Text('Demo Mode'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange, // Background color
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
