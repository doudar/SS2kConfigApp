/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

// ignore_for_file: annotate_overrides, avoid_print, prefer_const_constructors

// Import necessary libraries
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Abstract class defining the structure of an OTA package
abstract class OtaPackage {
  // Method to update firmware
  Future<void> updateFirmware(
    BluetoothDevice device,
    int firmwareType,
    BluetoothService service,
    BluetoothCharacteristic dataUUID,
    BluetoothCharacteristic controlUUID, {
    String? binFilePath,
    String? url,
  });

  // Property to track firmware update status
  bool firmwareupdate = false;

  // Stream to provide progress percentage
  Stream<int> get percentageStream;
}

// Class responsible for handling BLE repository operations
class BleRepository {
  // Write data to a Bluetooth characteristic
  Future<void> writeDataCharacteristic(
    BluetoothCharacteristic characteristic,
    Uint8List data,
  ) async {
    await characteristic.write(data);
  }

  // Read data from a Bluetooth characteristic
  Future<List<int>> readCharacteristic(
    BluetoothCharacteristic characteristic,
  ) async {
    return await characteristic.read();
  }

  // Request a specific MTU size from a Bluetooth device
  Future<void> requestMtu(BluetoothDevice device, int mtuSize) async {
    await device.requestMtu(mtuSize);
  }
}

// Implementation of OTA package for ESP32
class Esp32OtaPackage implements OtaPackage {
  final BluetoothCharacteristic dataCharacteristic;
  final BluetoothCharacteristic controlCharacteristic;
  bool firmwareupdate = false;
  final StreamController<int> _percentageController =
      StreamController<int>.broadcast();
  @override
  Stream<int> get percentageStream => _percentageController.stream;

  Esp32OtaPackage(this.dataCharacteristic, this.controlCharacteristic);

  @override
  Future<void> updateFirmware(
    BluetoothDevice device,
    int firmwareType,
    BluetoothService service,
    BluetoothCharacteristic dataUUID,
    BluetoothCharacteristic controlUUID, {
    String? binFilePath,
    String? url,
  }) async {
    final bleRepo = BleRepository();

    // Get MTU size from the device
    int mtuSize = await device.mtu.first;
    const int chunkSize = 512;

    if (mtuSize < chunkSize + 3) {
      throw Exception(
        'BLE MTU $mtuSize is too small for the required 512-byte OTA chunks.',
      );
    }

    print("MTU size for current device $mtuSize");

    // Prepare a byte list to write MTU size to controlCharacteristic
    Uint8List byteList = Uint8List(2);
    byteList[0] = chunkSize & 0xFF;
    byteList[1] = (chunkSize >> 8) & 0xFF;

    List<Uint8List> binaryChunks;

    // Architecture validation and file selection happen before this transport
    // is invoked, so BLE OTA only accepts the prepared local firmware file.
    if (binFilePath != null && binFilePath.isNotEmpty) {
      binaryChunks = await _readLocalFile(binFilePath, chunkSize);
    } else {
      throw Exception('No firmware file path provided');
    }

    if (binaryChunks.isEmpty) {
      throw Exception('No firmware data available');
    }
    if (binaryChunks.last.length >= chunkSize) {
      throw Exception(
        'Firmware length must produce a final OTA chunk shorter than 512 bytes.',
      );
    }

    // Write x01 to the controlCharacteristic and check if it returns value of 0x02
    await bleRepo.writeDataCharacteristic(
      controlCharacteristic,
      Uint8List.fromList([1]),
    );

    // Read value from controlCharacteristic
    List<int> value = await bleRepo
        .readCharacteristic(controlCharacteristic)
        .timeout(Duration(seconds: 10));
    if (value.isEmpty || value[0] != 0x02) {
      throw Exception('Device did not acknowledge the start of the BLE OTA.');
    }
    print('value returned is this ------- ${value[0]}');

    int packageNumber = 0;
    for (Uint8List chunk in binaryChunks) {
      // A write-with-response is the TX acknowledgement. Never queue the next
      // chunk until it completes.
      await dataCharacteristic
          .write(chunk, withoutResponse: false)
          .timeout(
            Duration(seconds: 10),
            onTimeout: () {
              // If a timeout occurs, throw a custom exception to be caught by the catch block
              firmwareupdate = false;
              _percentageController.close();
              throw TimeoutException(
                'Failed to write data chunk #$packageNumber',
              );
            },
          );
      packageNumber++;

      double progress = (packageNumber / binaryChunks.length) * 100;
      int roundedProgress = progress.round(); // Rounded off progress value
      print(
        'Writing package number $packageNumber of ${binaryChunks.length} to ESP32',
      );
      print('Progress: $roundedProgress%');
      _percentageController.add(roundedProgress);
    }

    // Check if controlCharacteristic reads 0x05, indicating OTA update finished
    value = await bleRepo
        .readCharacteristic(controlCharacteristic)
        .timeout(Duration(seconds: 600));
    print('value returned is this ------- ${value[0]}');

    if (value[0] == 5) {
      print('BLE OTA update finished');
      firmwareupdate = true; // Firmware update was successful
    } else {
      print('BLE OTA update failed');
      firmwareupdate = false; // Firmware update failed
    }
    _percentageController.close();
  }

  // Convert Uint8List to List<int>
  List<int> uint8ListToIntList(Uint8List uint8List) {
    return uint8List.toList();
  }

  // Read binary file from local filesystem and split it into chunks
  Future<List<Uint8List>> _readLocalFile(String filePath, int chunkSize) async {
    final bytes = await File(filePath).readAsBytes();
    return _splitIntoChunks(bytes, chunkSize);
  }

  // Helper method to split bytes into chunks
  List<Uint8List> _splitIntoChunks(List<int> bytes, int chunkSize) {
    List<Uint8List> chunks = [];
    for (int i = 0; i < bytes.length; i += chunkSize) {
      int end = i + chunkSize;
      if (end > bytes.length) {
        end = bytes.length;
      }
      chunks.add(Uint8List.fromList(bytes.sublist(i, end)));
    }
    return chunks;
  }

  // Get firmware from an already selected and validated local file.
  Future<List<Uint8List>> getFirmware(
    int firmwareType,
    int chunkSize, {
    String? binFilePath,
  }) {
    if (binFilePath != null && binFilePath.isNotEmpty) {
      return _readLocalFile(binFilePath, chunkSize);
    } else {
      return Future.value([]);
    }
  }
}
