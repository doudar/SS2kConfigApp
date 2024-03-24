/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
// This is a mock demo utility to simulate SmartSpin2k device connections

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/constants.dart';
class DemoDevice {
  static final DemoDevice _singleton = DemoDevice._internal();

  factory DemoDevice() {
    return _singleton;
  }

  DemoDevice._internal();

  // This function simulates finding a SmartSpin2k device during a scan
  ScanResult simulateSmartSpin2kScan() {
    // Generate mock advertising data for a SmartSpin2k device
    final Map<String, dynamic> mockAdData = {
      'localName': 'SmartSpin2k',
      'txPowerLevel': '0',
      'manufacturerData': '...',
      // Add other advertising data fields that a SmartSpin2k would normally include
    };

    // Create a mock BluetoothDevice
    final BluetoothDevice mockDevice = BluetoothDevice(
      remoteId: DeviceIdentifier('00:00:00:00:00:00'),
    );

    // Create a mock ScanResult
    final ScanResult mockScanResult = ScanResult(
      device: mockDevice,
      timeStamp: DateTime.now(),
      advertisementData: AdvertisementData(
        advName: mockAdData['localName'],
        appearance: 1,
        connectable: true,
        serviceUuids: [Guid(csUUID)],
        serviceData: {},
        txPowerLevel: int.tryParse(mockAdData['txPowerLevel']),
        manufacturerData: mockAdData['manufacturerData'],
        // ...initialize other advertisement data as necessary
      ),
      rssi: -59, // Sample signal strength
    );

    return mockScanResult;
  }
}

