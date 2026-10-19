/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../widgets/smartspin_introduction.dart';

import '../utils/constants.dart';
import 'main_device_screen.dart';
import '../utils/snackbar.dart';
import '../utils/device_data.dart';
import '../widgets/scan_result_tile.dart';
import '../utils/demo.dart';
import 'onboarding/onboarding_wizard.dart';
import '../utils/onboarding/wizard_session.dart';
import '../utils/dircon_discovery.dart';
import '../utils/smartspin_scan_result.dart';
import '../utils/nearby_ble_devices.dart';
import 'package:provider/provider.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _scanResults = [];
  bool _bleScanning = false;
  final _networkDiscovery = DirConDiscovery();
  bool get _isScanning => _bleScanning || _networkDiscovery.isScanning;
  List<SmartSpinScanResult> get _results => SmartSpinScanResult.merge(
    _scanResults,
    _networkDiscovery.endpoints,
    includeAllBle: kIsWeb,
  ).map(DeviceDataManager.reuseConnectedIdentity).toList();

  void _networkChanged() {
    if (mounted) setState(() {});
  }

  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  int _tapCount = 0; // Tap counter
  bool _showDemoButton = false; // Initially, the demo button is not shown

  @override
  void initState() {
    super.initState();
    _networkDiscovery.addListener(_networkChanged);

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        NearbyBleDevices.instance.observeAll(results);
        DeviceDataManager.refreshNearbyDevices();
        _scanResults = results;
        if (mounted) {
          setState(() {});
        }
      },
      onError: (e) {
        Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _bleScanning = state;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _networkDiscovery.removeListener(_networkChanged);
    _networkDiscovery.dispose();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    super.dispose();
  }

  Future onScanPressed() async {
    //don't allow scan in demo mode - it ruins the setup
    if (_showDemoButton) return;
    unawaited(_networkDiscovery.start());
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
      await _networkDiscovery.stop();
      await FlutterBluePlus.stopScan();
    } catch (e) {
      Snackbar.show(
        ABC.b,
        prettyException("Stop Scan Error:", e),
        success: false,
      );
    }
  }

  Future<void> onConnectPressed(SmartSpinScanResult result) async {
    final device = result.device;
    final deviceData = DeviceDataManager.forDevice(device);
    deviceData.applyScanResult(result);
    await _networkDiscovery.stop();
    try {
      // Reset the user disconnect flag if triggered
      if (deviceData.isUserDisconnect) {
        deviceData.isUserDisconnect = false;
      }
    } catch (e) {
      print("Device DeviceData was not initialized: $e");
    }
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    if (!deviceData.isTransportActive)
      unawaited(
        deviceData.connectPreferred(device).catchError((Object e) {
          Snackbar.show(
            ABC.c,
            prettyException("Connect Error:", e),
            success: false,
          );
        }),
      );
    if (!mounted) return;
    MaterialPageRoute route = MaterialPageRoute(
      builder: (context) => MainDeviceScreen(device: device),
      settings: RouteSettings(name: '/MainDeviceScreen'),
    );
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

  Future<void> onRefresh() async {
    if (!_isScanning) await onScanPressed();
  }

  void _openGuidedSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => WizardSession(),
          child: const OnboardingWizard(),
        ),
      ),
    );
  }

  Widget buildScanButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool scanning = _isScanning;
    final Color foregroundColor = scanning ? colorScheme.onError : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scanning
                ? colorScheme.error.withValues(alpha: 0.88)
                : const Color(0xFF1B1B1B),
            scanning
                ? colorScheme.error.withValues(alpha: 0.64)
                : const Color(0xFF2A2A2A),
          ],
        ),
        border: Border.all(
          color: scanning
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.red.withValues(alpha: 0.28),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: scanning
            ? const Icon(Icons.stop_rounded)
            : const Text(
                "SCAN",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildGuidedSetupButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: OutlinedButton.icon(
        onPressed: _openGuidedSetup,
        icon: const Icon(Icons.route_outlined),
        label: const Text('Guided Setup'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color.fromARGB(
            255,
            54,
            27,
            26,
          ).withValues(alpha: 0.24),
          side: BorderSide(color: Colors.red.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ready to ride?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Power on your SmartSpin2k, then scan to connect.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            buildScanButton(context),
            const SizedBox(height: 12),
            _buildGuidedSetupButton(context),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Having trouble connecting?'),
              children: [
                const Text(
                  '1. Keep your SmartSpin2k powered on and within range.\n'
                  '2. Turn Bluetooth off and on, then scan again.\n'
                  '3. Restart your SmartSpin2k.\n'
                  '4. Close other connected apps if needed. Each SmartSpin2k '
                  'supports up to 3 app connections.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => openSmartSpinLink(
                    context,
                    'https://docs.smartspin2k.com/',
                  ),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('Setup help & support'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _results
        .map(
          (r) => ScanResultTile(
            key: ValueKey(r.device.remoteId.str),
            result: r,
            onTap: () => onConnectPressed(r),
          ),
        )
        .toList();
  }

  void _incrementTapCount() {
    setState(() {
      _tapCount++;
      if (_tapCount >= 5) {
        _showDemoButton = true;
        demoModeBypass.value = true; // also expose to main.dart routing
      }
    });
  }

  void onDemoModePressed(context) {
    // Use the DemoDevice to simulate finding a SmartSpin2k device
    final demoDevice = DemoDevice();
    ScanResult simulatedScanResult = demoDevice.simulateSmartSpin2kScan();

    // Update the UI to display the simulated scan result
    setState(() {
      _scanResults = [
        simulatedScanResult,
      ]; // Replace existing scan results with the simulated one
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
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
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
          title: Text('SmartSpin2k'),
          titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black87,
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: onRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1000;
                  final introduction = const SmartSpinIntroduction();
                  final connection = _buildConnectionPanel(context);
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Column(
                            children: [
                              ..._buildScanResultTiles(context),
                              if (_results.isNotEmpty)
                                const SizedBox(height: 16),
                              if (_results.isEmpty && wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 7, child: introduction),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 4, child: connection),
                                  ],
                                )
                              else ...[
                                connection,
                                if (_results.isEmpty) ...[
                                  const SizedBox(height: 20),
                                  introduction,
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_results.isEmpty)
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
                        onDemoModePressed(
                          context,
                        ); // Assuming this is your method to set up demo data

                        setState(() {
                          _showDemoButton =
                              false; // Hide the button again after entering demo mode
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
