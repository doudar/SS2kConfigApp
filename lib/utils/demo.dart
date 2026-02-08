/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
// This is a mock demo utility to simulate SmartSpin2k device connections

import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

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
  BleDevice simulateSmartSpin2kScan() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return BleDevice(
      deviceId: 'demo-$timestamp',
      name: 'SmartSpin2k Demo',
      rssi: -59,
      services: [csUUID],
      manufacturerDataList: [
        ManufacturerData(
          mockManufacturerId,
          Uint8List.fromList(mockManufacturerData),
        ),
      ],
      timestamp: timestamp,
    );
  }



}
