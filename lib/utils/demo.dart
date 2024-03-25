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
  // Mock manufacturer ID and data
  static const int mockManufacturerId = 123; 
  final List<int> mockManufacturerData = [0x00, 0x01, 0x02];
  // This function simulates finding a SmartSpin2k device during a scan
  ScanResult simulateSmartSpin2kScan() {
    // Generate mock advertising data for a SmartSpin2k device
    final Map<String, dynamic> mockAdData = {
      'localName': 'SmartSpin2k Demo',
      'txPowerLevel': '50',
      'manufacturerData': {mockManufacturerId: mockManufacturerData},
      // Add other advertising data fields that a SmartSpin2k would normally include
    };

    // Create a mock BluetoothDevice
    final BluetoothDevice mockDevice = BluetoothDevice(
      remoteId: DeviceIdentifier('SmartSpin2k Demo'),
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
      ),
      rssi: -59, // Sample signal strength
    );

    return mockScanResult;
  }



}
