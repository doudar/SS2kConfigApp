/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/device_data.dart';
import '../utils/constants.dart';
import '../utils/demo.dart';

class DropdownCard extends StatefulWidget {
  const DropdownCard({Key? key, required this.device, required this.c})
    : super(key: key);

  final BluetoothDevice device;
  final Map c;

  @override
  State<DropdownCard> createState() => _DropdownCardState();
}

class _DropdownCardState extends State<DropdownCard> {
  List<String> ddItems = [];
  String? selectedValue;
  late DeviceData deviceData;
  StreamSubscription? _charSubscription;
  final ScrollController _scrollController = ScrollController();
  VoidCallback? _scanStateListener;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _scanStateListener = () {
      if (mounted) setState(() {});
    };
    deviceData.bleDeviceScanInProgress.addListener(_scanStateListener!);
    buildDevicesMap();
    selectedValue = ddItems.isNotEmpty ? ddItems[0] : null;
    try {
      // Subscribe to characteristic changes stream instead of direct onValueReceived
      // Listen for changes to the foundDevices characteristic
      _charSubscription = deviceData.characteristicChanges
          .where((event) => event.vName == foundDevicesVname)
          .listen((event) {
            if (mounted) {
              buildDevicesMap();
              setState(() {
                // Trigger rebuild
              });
            }
          });
    } catch (e) {
      print("Subscription Failed, $e");
    }
  }

  @override
  void dispose() {
    if (_scanStateListener != null) {
      deviceData.bleDeviceScanInProgress.removeListener(_scanStateListener!);
    }
    _charSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void buildDevicesMap() {
    // These choices are valid even before a scan has begun (and if a legacy
    // firmware response is empty or malformed).
    final dropdownItems = <String>{'any', 'none'};
    final currentValue = widget.c['value']?.toString().trim();
    if (currentValue != null &&
        currentValue.isNotEmpty &&
        currentValue != 'null' &&
        currentValue != 'Loading...' &&
        currentValue != noFirmSupport) {
      dropdownItems.add(currentValue);
    }

    List<dynamic> items = const [];
    for (final characteristic in deviceData.customCharacteristic) {
      if (characteristic['vName'] != foundDevicesVname) continue;
      final encodedDevices = characteristic['value'];
      if (encodedDevices is! String || encodedDevices.trim().isEmpty) break;
      try {
        final decoded = jsonDecode(encodedDevices);
        if (decoded is List) items = decoded;
      } on FormatException {
        // Keep the unconditional any/none choices while data is incomplete.
      }
      break;
    }

    for (final deviceGroup in items) {
      if (deviceGroup is! Map) continue;
      for (final device in deviceGroup.values) {
        if (device is! Map) continue;
        if (widget.c['vName'] == connectedPWRVname) {
          if (device['UUID'] == '0x1818' ||
              device['UUID'] == '0x1826' ||
              device['UUID'] == '0x1816' ||
              device['UUID'] == '6e400001-b5a3-f393-e0a9-e50e24dcca9e' ||
              device['UUID'] == '0bf669f0-45f2-11e7-9598-0800200c9a66') {
            _addDeviceLabel(dropdownItems, device);
          }
        }
        if (widget.c['vName'] == connectedHRMVname) {
          if (device['UUID'] == '0x180d') {
            _addDeviceLabel(dropdownItems, device);
          }
        }
      }
    }
    ddItems = dropdownItems.toList();
  }

  void _addDeviceLabel(Set<String> items, Map device) {
    final label = (device['name'] ?? device['address'])?.toString().trim();
    if (label != null &&
        label.isNotEmpty &&
        label != 'null' &&
        label != noFirmSupport) {
      items.add(label);
    }
  }

  Future _changeBLEDevice(BuildContext context) async {
    setState(() {
      this.widget.c["value"] = selectedValue!;
      // Assuming writeToSS2k is your method to handle selection
    });
    //reconnect devices
    this.deviceData.writeToSS2k(this.widget.device, this.widget.c);
    this.deviceData.customCharacteristic.forEach(
      (d) => d["vName"] == restartBLEVname
          ? this.deviceData.writeToSS2k(this.widget.device, d, s: "1")
          : (),
    );
  }

  Color _getTileColor() {
    if (widget.c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return (widget.c["settingType"] as SettingType).color;
  }

  @override
  Widget build(BuildContext context) {
    Color baseColor = _getTileColor();
    final isScanning = deviceData.bleDeviceScanInProgress.value;
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  baseColor.withValues(
                    alpha: 0.95,
                  ), // Higher opacity for legibility
                  baseColor.withValues(alpha: 0.7),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    this.widget.c["humanReadableName"],
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    "Current: ${this.widget.c["value"]}",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 2,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 24, color: Colors.white24),
                Flexible(
                  child: ddItems.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              "No devices found",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                      : ScrollbarTheme(
                          data: ScrollbarThemeData(
                            thumbColor: WidgetStatePropertyAll(Colors.white54),
                            trackVisibility: WidgetStatePropertyAll(true),
                            thickness: WidgetStatePropertyAll(8.0),
                            radius: Radius.circular(10),
                          ),
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                              controller: _scrollController,
                              shrinkWrap: true,
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              itemCount: ddItems.length,
                              separatorBuilder: (ctx, i) => SizedBox(height: 4),
                              itemBuilder: (BuildContext context, int index) {
                                final item = ddItems[index];
                                final isSelected =
                                    item == this.widget.c["value"];

                                return Material(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () {
                                      selectedValue = item;
                                      _changeBLEDevice(context);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12.0,
                                        horizontal: 16.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                fontSize: 16,
                                                color: Colors.white,
                                                shadows: [
                                                  Shadow(
                                                    offset: Offset(1, 1),
                                                    blurRadius: 1,
                                                    color: Colors.black26,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
                Divider(height: 24, color: Colors.white24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (!demoModeBypass.value)
                        TextButton.icon(
                          icon: isScanning
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh,
                                  color: Colors.white70,
                                ),
                          label: Text(
                            isScanning ? 'SCANNING…' : 'SCAN',
                            style: const TextStyle(color: Colors.white),
                          ),
                          onPressed: isScanning
                              ? null
                              : () async {
                                  try {
                                    await deviceData.scanForBleDevices(
                                      widget.device,
                                    );
                                  } catch (error) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not start BLE scan: $error',
                                        ),
                                      ),
                                    );
                                  }
                                },
                        ),
                      Spacer(),
                      TextButton(
                        child: const Text(
                          'BACK',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: baseColor,
                        ),
                        child: const Text(
                          'SAVE',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          //Find the save command and execute it
                          await this.deviceData.writeCommand(
                            this.widget.device,
                            saveVname,
                          );
                          if (!mounted) return;
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
