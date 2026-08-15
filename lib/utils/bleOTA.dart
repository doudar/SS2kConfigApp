/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

// ignore_for_file: annotate_overrides, avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const int bleOtaProtocolV1 = 1;
const int bleOtaV1StatusLength = 12;
const int bleOtaMaximumChunkSize = 512;
const int bleOtaV1WriteWithoutResponseCapability = 0x08;

enum BleOtaV1State {
  waiting(0x00),
  preparing(0x01),
  updating(0x02),
  flashing(0x03),
  verifying(0x04),
  rebooting(0x05),
  error(0xff);

  const BleOtaV1State(this.value);
  final int value;

  static BleOtaV1State? fromValue(int value) {
    for (final state in values) {
      if (state.value == value) return state;
    }
    return null;
  }
}

class BleOtaV1Status {
  const BleOtaV1Status({
    required this.state,
    required this.errorCode,
    required this.capabilityFlags,
    required this.bytesReceived,
    required this.imageSize,
  });

  final BleOtaV1State? state;
  final int errorCode;
  final int capabilityFlags;
  final int bytesReceived;
  final int imageSize;

  bool get hasError => state == BleOtaV1State.error || errorCode != 0;
}

BleOtaV1Status? parseBleOtaV1Status(List<int> packet) {
  if (packet.length != bleOtaV1StatusLength || packet[0] != bleOtaProtocolV1) {
    return null;
  }
  final bytes = Uint8List.fromList(packet);
  final data = ByteData.sublistView(bytes);
  return BleOtaV1Status(
    state: BleOtaV1State.fromValue(packet[1]),
    errorCode: packet[2],
    capabilityFlags: packet[3],
    bytesReceived: data.getUint32(4, Endian.little),
    imageSize: data.getUint32(8, Endian.little),
  );
}

Uint8List buildBleOtaV1StartPacket(int imageSize, int crc32) {
  if (imageSize <= 0 || imageSize > 0xffffffff) {
    throw ArgumentError.value(imageSize, 'imageSize', 'must fit in a u32');
  }
  final packet = Uint8List(10);
  final data = ByteData.sublistView(packet);
  packet[0] = 0x01;
  packet[1] = bleOtaProtocolV1;
  data.setUint32(2, imageSize, Endian.little);
  data.setUint32(6, crc32, Endian.little);
  return packet;
}

int calculateBleOtaCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

int bleOtaV1ChunkSizeForMtu(int mtu) {
  final payload = mtu - 3;
  if (payload <= 0) return 20;
  return payload.clamp(1, bleOtaMaximumChunkSize);
}

bool bleOtaV0CanRepresentImageLength(int imageSize) {
  return imageSize > 0 && imageSize % bleOtaMaximumChunkSize != 0;
}

bool bleOtaChunkRequiresLongWrite(int mtu, int chunkLength) {
  return chunkLength > (mtu - 3).clamp(0, 0xffffffff);
}

bool bleOtaV1ShouldWriteWithoutResponse(int capabilityFlags) {
  return capabilityFlags & bleOtaV1WriteWithoutResponseCapability != 0;
}

String bleOtaV1ErrorMessage(int errorCode) {
  const messages = <int, String>{
    0x01: 'Invalid command',
    0x02: 'Unsupported protocol version',
    0x03: 'Invalid START packet',
    0x04: 'Another update is active',
    0x05: 'Invalid image size',
    0x06: 'No OTA partition available',
    0x07: 'Command or data came from the wrong connection',
    0x08: 'Update has not been started',
    0x09: 'Empty firmware data write',
    0x0a: 'More bytes received than declared',
    0x0b: 'Invalid image header or wrong ESP chip',
    0x0c: 'OTA begin failed',
    0x0d: 'Flash write failed',
    0x0e: 'FINISH received before the declared byte count',
    0x0f: 'CRC-32 mismatch',
    0x10: 'ESP image verification failed',
    0x11: 'New boot partition could not be selected',
    0x12: 'No firmware data received for 30 seconds',
    0x13: 'Update aborted by the client',
    0x14: 'Update connection was lost',
  };
  return messages[errorCode] ??
      'Unknown BLE firmware update error (0x${errorCode.toRadixString(16).padLeft(2, '0')})';
}

abstract class OtaPackage {
  Future<void> updateFirmware(
    BluetoothDevice device,
    int firmwareType,
    BluetoothService service,
    BluetoothCharacteristic dataUUID,
    BluetoothCharacteristic controlUUID, {
    String? binFilePath,
    String? url,
  });

  bool firmwareupdate = false;
  Stream<int> get percentageStream;
}

class Esp32OtaPackage implements OtaPackage {
  Esp32OtaPackage(this.dataCharacteristic, this.controlCharacteristic);

  final BluetoothCharacteristic dataCharacteristic;
  final BluetoothCharacteristic controlCharacteristic;
  bool firmwareupdate = false;
  final StreamController<int> _percentageController =
      StreamController<int>.broadcast();

  BleOtaV1Status? _latestV1Status;
  StreamSubscription<List<int>>? _controlSubscription;

  @override
  Stream<int> get percentageStream => _percentageController.stream;

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
    if (binFilePath == null || binFilePath.isEmpty) {
      throw Exception('No firmware file path provided');
    }

    final firmware = await File(binFilePath).readAsBytes();
    if (firmware.isEmpty) throw Exception('No firmware data available');

    firmwareupdate = false;
    var protocolV1Started = false;
    try {
      final initialValue = await _subscribeAndReadControl();
      if (parseBleOtaV1Status(initialValue) != null ||
          _latestV1Status != null) {
        protocolV1Started = true;
        await _updateProtocolV1(device, firmware);
      } else {
        await _updateProtocolV0(device, firmware);
      }
      firmwareupdate = true;
      if (!_percentageController.isClosed) _percentageController.add(100);
    } catch (_) {
      if (protocolV1Started &&
          _latestV1Status?.state != BleOtaV1State.rebooting) {
        await _bestEffortV1Abort();
      }
      rethrow;
    } finally {
      await _controlSubscription?.cancel();
      try {
        await controlCharacteristic.setNotifyValue(false);
      } catch (_) {
        // Protocol 1 normally disconnects while rebooting.
      }
      if (!_percentageController.isClosed) {
        await _percentageController.close();
      }
    }
  }

  Future<List<int>> _subscribeAndReadControl() async {
    _controlSubscription = controlCharacteristic.onValueReceived.listen(
      _recordControlValue,
      onError: (Object error) {
        print('BLE OTA control notification error: $error');
      },
    );
    try {
      await controlCharacteristic.setNotifyValue(true);
    } catch (error) {
      // A read still permits version detection and status polling on stacks
      // where notification setup is transiently unavailable.
      print('BLE OTA control notifications unavailable: $error');
    }
    try {
      final value = await controlCharacteristic.read().timeout(
        const Duration(seconds: 10),
      );
      _recordControlValue(value);
      return value;
    } catch (error) {
      // A version 1 notification can race with (or outlive) a failed read.
      // Give that notification a brief chance before treating detection as
      // failed. Legacy protocol 0 still requires readable control status.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_latestV1Status != null) return const [];
      rethrow;
    }
  }

  void _recordControlValue(List<int> value) {
    final status = parseBleOtaV1Status(value);
    if (status != null) _latestV1Status = status;
  }

  Future<void> _updateProtocolV1(
    BluetoothDevice device,
    Uint8List firmware,
  ) async {
    final crc32 = calculateBleOtaCrc32(firmware);
    final capabilityFlags = _latestV1Status?.capabilityFlags ?? 0;
    final characteristicReportsWriteWithoutResponse =
        dataCharacteristic.properties.writeWithoutResponse;
    // The versioned status packet is authoritative. Some host BLE backends
    // (notably Windows implementations) omit the write-without-response
    // characteristic property even when the peripheral supports it.
    final useWriteWithoutResponse = bleOtaV1ShouldWriteWithoutResponse(
      capabilityFlags,
    );
    // Do not let a stale Error status from a prior attempt reject a new START.
    // The firmware explicitly permits retrying START after an error.
    _latestV1Status = null;
    await controlCharacteristic.write(
      buildBleOtaV1StartPacket(firmware.length, crc32),
      withoutResponse: false,
    );

    await _waitForV1State(
      const {BleOtaV1State.updating},
      timeout: const Duration(seconds: 30),
      description: 'the OTA partition to become ready',
    );

    final mtu = await _bestAvailableMtu(device);
    final chunkSize = bleOtaV1ChunkSizeForMtu(mtu);
    final writeMode = useWriteWithoutResponse
        ? 'write without response'
        : 'sequential write with response';
    print(
      'BLE OTA protocol 1 selected; capabilities '
      '0x${capabilityFlags.toRadixString(16).padLeft(2, '0')}, MTU $mtu, '
      'chunk size $chunkSize, characteristic WNR property '
      '$characteristicReportsWriteWithoutResponse, using $writeMode',
    );

    var bytesWritten = 0;
    var chunkNumber = 0;
    while (bytesWritten < firmware.length) {
      _throwForLatestV1Error();
      final end = (bytesWritten + chunkSize).clamp(0, firmware.length);
      final chunk = Uint8List.sublistView(firmware, bytesWritten, end);
      try {
        await dataCharacteristic
            .write(chunk, withoutResponse: useWriteWithoutResponse)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException(
                'Failed to write BLE firmware data chunk #$chunkNumber',
              ),
            );
      } catch (_) {
        // Prefer a protocol error (including the firmware's 30-second data
        // timeout) over a generic platform write/disconnect exception when a
        // final status notification arrived at the same time.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        _throwForLatestV1Error();
        rethrow;
      }
      bytesWritten = end;
      chunkNumber++;
      _emitProgress(bytesWritten, firmware.length);
    }

    _throwForLatestV1Error();
    await controlCharacteristic.write(
      Uint8List.fromList([0x02]),
      withoutResponse: false,
    );
    await _waitForV1State(
      const {BleOtaV1State.rebooting},
      timeout: const Duration(minutes: 2),
      description: 'firmware verification and reboot',
    );
    print('BLE OTA protocol 1 update accepted; rebooting');
  }

  Future<void> _updateProtocolV0(
    BluetoothDevice device,
    Uint8List firmware,
  ) async {
    const chunkSize = bleOtaMaximumChunkSize;
    if (!bleOtaV0CanRepresentImageLength(firmware.length)) {
      throw Exception(
        'This legacy firmware requires a final BLE OTA chunk shorter than '
        '$chunkSize bytes. Use WiFi OTA or protocol version 1 for this image.',
      );
    }

    final mtu = await _bestAvailableMtu(device);
    print('BLE OTA legacy protocol selected; MTU $mtu');
    await controlCharacteristic.write(
      Uint8List.fromList([0x01]),
      withoutResponse: false,
    );
    await _waitForLegacyValue(
      0x02,
      timeout: const Duration(seconds: 15),
      description: 'the legacy OTA start acknowledgement',
    );

    var bytesWritten = 0;
    var chunkNumber = 0;
    while (bytesWritten < firmware.length) {
      final end = (bytesWritten + chunkSize).clamp(0, firmware.length);
      final chunk = Uint8List.sublistView(firmware, bytesWritten, end);
      final needsLongWrite = bleOtaChunkRequiresLongWrite(mtu, chunk.length);
      await dataCharacteristic
          .write(chunk, withoutResponse: false, allowLongWrite: needsLongWrite)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Failed to write legacy BLE firmware chunk #$chunkNumber',
            ),
          );
      bytesWritten = end;
      chunkNumber++;
      _emitProgress(bytesWritten, firmware.length);
    }

    await _waitForLegacyValue(
      0x05,
      timeout: const Duration(minutes: 10),
      description: 'the legacy OTA completion acknowledgement',
    );
    print('Legacy BLE OTA update finished');
  }

  Future<int> _bestAvailableMtu(BluetoothDevice device) async {
    var mtu = device.mtuNow;
    if (mtu < 23) {
      try {
        mtu = await device.mtu.first.timeout(const Duration(seconds: 2));
      } catch (_) {
        mtu = 23;
      }
    }
    if (Platform.isAndroid && mtu < bleOtaMaximumChunkSize + 3) {
      try {
        mtu = await device.requestMtu(bleOtaMaximumChunkSize + 3);
      } catch (error) {
        print('BLE OTA MTU request failed; continuing with MTU $mtu: $error');
      }
    }
    return mtu < 23 ? 23 : mtu;
  }

  Future<BleOtaV1Status> _waitForV1State(
    Set<BleOtaV1State> expected, {
    required Duration timeout,
    required String description,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastReadError;
    while (DateTime.now().isBefore(deadline)) {
      final latest = _latestV1Status;
      if (latest != null) {
        _throwForV1Error(latest);
        if (latest.state != null && expected.contains(latest.state)) {
          return latest;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        final value = await controlCharacteristic.read().timeout(
          const Duration(seconds: 3),
        );
        _recordControlValue(value);
        lastReadError = null;
      } catch (error) {
        lastReadError = error;
        final afterRead = _latestV1Status;
        if (afterRead?.state == BleOtaV1State.rebooting &&
            expected.contains(BleOtaV1State.rebooting)) {
          return afterRead!;
        }
      }
    }
    final suffix = lastReadError == null ? '' : ' Last read: $lastReadError';
    throw TimeoutException('Timed out waiting for $description.$suffix');
  }

  Future<void> _waitForLegacyValue(
    int expected, {
    required Duration timeout,
    required String description,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastReadError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final value = await controlCharacteristic.read().timeout(
          const Duration(seconds: 3),
        );
        if (value.isNotEmpty && value[0] == expected) return;
        if (value.isNotEmpty && value[0] == 0xff) {
          throw Exception('Legacy BLE OTA reported an error.');
        }
        lastReadError = null;
      } catch (error) {
        if (error is Exception &&
            error.toString().contains('reported an error')) {
          rethrow;
        }
        lastReadError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final suffix = lastReadError == null ? '' : ' Last read: $lastReadError';
    throw TimeoutException('Timed out waiting for $description.$suffix');
  }

  void _throwForLatestV1Error() {
    final status = _latestV1Status;
    if (status != null) _throwForV1Error(status);
  }

  void _throwForV1Error(BleOtaV1Status status) {
    if (!status.hasError) return;
    throw Exception(
      'BLE firmware update failed: ${bleOtaV1ErrorMessage(status.errorCode)} '
      '(received ${status.bytesReceived} of ${status.imageSize} bytes).',
    );
  }

  Future<void> _bestEffortV1Abort() async {
    try {
      await controlCharacteristic
          .write(Uint8List.fromList([0x03]), withoutResponse: false)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      print('BLE OTA abort could not be delivered: $error');
    }
  }

  void _emitProgress(int bytesWritten, int imageSize) {
    if (_percentageController.isClosed) return;
    _percentageController.add(((bytesWritten / imageSize) * 100).round());
  }

  Future<List<Uint8List>> getFirmware(
    int firmwareType,
    int chunkSize, {
    String? binFilePath,
  }) async {
    if (binFilePath == null || binFilePath.isEmpty) return [];
    final bytes = await File(binFilePath).readAsBytes();
    final chunks = <Uint8List>[];
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      chunks.add(Uint8List.sublistView(bytes, offset, end));
    }
    return chunks;
  }
}
