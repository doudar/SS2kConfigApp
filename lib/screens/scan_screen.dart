/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';
import 'main_device_screen.dart';
import '../utils/snackbar.dart';
import '../utils/bledata.dart';
import '../utils/extra.dart';
import '../widgets/scan_result_tile.dart';
import '../widgets/theme_cycle_button.dart';
import '../utils/demo.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  int _tapCount = 0; // Tap counter
  bool _showDemoButton = false; // Initially, the demo button is not shown

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
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    super.dispose();
  }

  Future onScanPressed() async {
    //don't allow scan in demo mode - it ruins the setup
    if (_showDemoButton) return;
    try {
      if (kIsWeb) {
        // Web platform uses different scanning approach
        await FlutterBluePlus.startScan(
          withServices: [Guid(csUUID)],
          timeout: const Duration(seconds: 15),
        );
      } else {
        // Native platforms use client-side filtering for better cross-platform consistency
        // and improved reliability when multiple BLE apps are active.
        int divisor = !kIsWeb && io.Platform.isAndroid ? 8 : 1;
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          continuousUpdates: true,
          continuousDivisor: divisor,
        );
      }
    } catch (e) {
      String errorMessage = kIsWeb
          ? "Web Bluetooth Error: Make sure your browser supports Web Bluetooth and you're using HTTPS"
          : prettyException("Start Scan Error:", e);
      Snackbar.show(ABC.b, errorMessage, success: false);
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
    try {
      // Reset the user disconnect flag if triggered
      if (BLEDataManager.forDevice(device).isUserDisconnect) {
        BLEDataManager.forDevice(device).isUserDisconnect = false;
      }
    } catch (e) {
      print("Device BLEData was not initialized: $e");
    }
    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan();
    }
    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });
    MaterialPageRoute route = MaterialPageRoute(
        builder: (context) => MainDeviceScreen(device: device), settings: RouteSettings(name: '/MainDeviceScreen'));
    Navigator.of(context).push(route).then((_) {
      // Clear stale scan results when returning from device screen.
      // This prevents showing a cached entry for a previous device
      // that has the same name (e.g. "SmartSpin2k") but a different MAC.
      if (mounted) {
        setState(() {
          _scanResults = [];
        });
        // Automatically start a fresh scan so new devices are discovered
        if (!_showDemoButton) {
          onScanPressed();
        }
      }
    });
  }

  Future onRefresh() {
    if (_isScanning == false) {
      if (kIsWeb) {
        FlutterBluePlus.startScan(withServices: [Guid(csUUID)], timeout: const Duration(seconds: 15));
      } else {
        int divisor = io.Platform.isAndroid ? 8 : 1;
        FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          continuousUpdates: true,
          continuousDivisor: divisor,
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Widget buildScanButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool scanning = FlutterBluePlus.isScanningNow;
    final Color foregroundColor = scanning ? colorScheme.onError : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scanning ? colorScheme.error.withValues(alpha: 0.88) : const Color(0xFF1B1B1B),
            scanning ? colorScheme.error.withValues(alpha: 0.64) : const Color(0xFF2A2A2A),
          ],
        ),
        border: Border.all(
          color: scanning ? Colors.white.withValues(alpha: 0.22) : Colors.red.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          if (!scanning)
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.14),
              blurRadius: 10,
              spreadRadius: -2,
            ),
        ],
      ),
      child: ElevatedButton(
        onPressed: scanning ? onStopPressed : onScanPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: foregroundColor,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: scanning
            ? const Icon(Icons.stop_rounded)
            : const Text(
                "SCAN",
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
      ),
    );
  }

  Widget _buildEmptyStatePanel(BuildContext context) {
    final theme = Theme.of(context);
    final headingColor = Colors.white;
    final bodyColor = Colors.white.withValues(alpha: 0.92);
    final secondaryBodyColor = Colors.white.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.red.withValues(alpha: 0.8),
                  Colors.black.withValues(alpha: 0.93),
                  const Color(0xFF1A0606).withValues(alpha: 0.90),
                ],
                stops: const [0.0, 0.62, 1.0],
              ),
              border: Border.all(color: Colors.red.withValues(alpha: 0.45), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    Uri url = Uri(
                        scheme: 'https',
                        host: 'SmartSpin2k.com',
                        path: '/',
                        fragment: ''); //http://SmartSpin2k.com";
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color.fromARGB(255, 54, 27, 26).withValues(alpha: 0.24),
                    foregroundColor: bodyColor,
                    side: BorderSide(
                      color: const Color.fromARGB(255, 66, 26, 23).withValues(alpha: 0.42),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: Text(
                    'SmartSpin2k is a device that adds automatic resistance and virtual shifting to spin bikes. Click to learn more!',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: bodyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () async {
                    final Uri docsUrl = Uri.parse('https://docs.smartspin2k.com/');
                    if (await canLaunchUrl(docsUrl)) {
                      await launchUrl(docsUrl);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color.fromARGB(255, 54, 27, 26).withValues(alpha: 0.24),
                    foregroundColor: headingColor,
                    side: BorderSide(
                      color: const Color.fromARGB(255, 66, 26, 23).withValues(alpha: 0.42),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: Text(
                    'Having Trouble?',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: headingColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'If you cannot find your SmartSpin2k, try the following steps:',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: bodyColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '1. Ensure your SmartSpin2k is powered on and within range.\n'
                  '2. Turn off and on the Bluetooth on your device, then try scanning again.\n'
                  '3. Restart your SmartSpin2k device.\n'
                  '4. Each SmartSpin2k has a max connection of 3 apps (including this one). Close some if needed.\n'
                  '5. If none of these steps work, please contact support for further assistance.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondaryBodyColor,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    final csGuid = Guid(csUUID);
    bool _isSmartSpin2kDevice(ScanResult result) {
      final adv = result.advertisementData;
      final hasService = adv.serviceUuids.any((uuid) => uuid == csGuid || uuid.str.toLowerCase() == csUUID.toLowerCase());
      return hasService;
    }

    final List<ScanResult> results = kIsWeb
      ? _scanResults
      : _scanResults.where(_isSmartSpin2kDevice).toList();

    return results
        .map(
          (r) => ScanResultTile(
            result: r,
            onTap: () => onConnectPressed(r.device),
          ),
        )
        .toList();
  }

  void _incrementTapCount() {
    setState(() {
      _tapCount++;
      if (_tapCount >= 5) {
        _showDemoButton = true; // Show the button after 5 taps
        // _tapCount = 0; // Reset the counter
      }
    });
  }

  void onDemoModePressed(context) {
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
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.92),
                  Colors.red.withValues(alpha: 0.80),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          title: Text('Find Your SmartSpin2k:'),
          titleTextStyle: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [
              Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
          actions: [
            const ThemeCycleButton(),
          ],
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                children: <Widget>[
                  ..._buildScanResultTiles(context),
                  if (_scanResults.isEmpty) // This line checks if there are no scan results
                    _buildEmptyStatePanel(context),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final buttonWidth = (constraints.maxWidth * 0.55).clamp(170.0, 320.0).toDouble();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 15),
                        child: Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: buttonWidth,
                            child: buildScanButton(context),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_scanResults.isEmpty)
              Positioned(
                left: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _incrementTapCount,
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    width: 100, // Adjust the size as needed
                    height: 100, // Adjust the size as needed
                    color: Colors.transparent,
                  ),
                ),
              ),
            Visibility(
              child: ElevatedButton(
                onPressed: _showDemoButton
                    ? () {
                        // Enter demo mode logic here
                        onDemoModePressed(context); // Assuming this is your method to set up demo data

                        setState(() {
                          _showDemoButton = false; // Hide the button again after entering demo mode
                        });
                      }
                    : null, // Button does nothing if _showDemoButton is false
                child: const Text(
                  "Tap Here to Enter\n Demo Mode",
                  style: TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.82),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
                ),
              ),
              visible: _showDemoButton,
            ),
          ],
        ),
      ),
    );
  }
}
