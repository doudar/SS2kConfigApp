import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleOTA.dart';

void main() {
  group('BLE OTA protocol version 1', () {
    test('recognizes and decodes a 12-byte version 1 status packet', () {
      final packet = Uint8List(12);
      final data = ByteData.sublistView(packet);
      packet[0] = 1;
      packet[1] = BleOtaV1State.flashing.value;
      packet[2] = 0;
      packet[3] = 0x0f;
      data.setUint32(4, 0x00123456, Endian.little);
      data.setUint32(8, 0x00765432, Endian.little);

      final status = parseBleOtaV1Status(packet);

      expect(status, isNotNull);
      expect(status!.state, BleOtaV1State.flashing);
      expect(status.capabilityFlags, 0x0f);
      expect(status.bytesReceived, 0x00123456);
      expect(status.imageSize, 0x00765432);
      expect(status.hasError, isFalse);
    });

    test('does not mistake legacy or malformed values for version 1', () {
      expect(parseBleOtaV1Status([0x02]), isNull);
      expect(parseBleOtaV1Status(List<int>.filled(11, 0)), isNull);
      expect(parseBleOtaV1Status(List<int>.filled(12, 0)), isNull);
    });

    test('builds the START command with little-endian metadata', () {
      expect(buildBleOtaV1StartPacket(0x12345678, 0x90abcdef), [
        0x01,
        0x01,
        0x78,
        0x56,
        0x34,
        0x12,
        0xef,
        0xcd,
        0xab,
        0x90,
      ]);
    });

    test('uses standard reflected CRC-32', () {
      expect(calculateBleOtaCrc32('123456789'.codeUnits), 0xcbf43926);
      expect(calculateBleOtaCrc32(const []), 0x00000000);
    });

    test('chooses an ATT-safe variable chunk size capped at 512 bytes', () {
      expect(bleOtaV1ChunkSizeForMtu(23), 20);
      expect(bleOtaV1ChunkSizeForMtu(247), 244);
      expect(bleOtaV1ChunkSizeForMtu(515), 512);
      expect(bleOtaV1ChunkSizeForMtu(1024), 512);
    });

    test('exposes firmware error details', () {
      expect(bleOtaV1ErrorMessage(0x0f), 'CRC-32 mismatch');
      expect(
        bleOtaV1ErrorMessage(0x12),
        'No firmware data received for 30 seconds',
      );
      expect(bleOtaV1ErrorMessage(0x13), 'Update aborted by the client');
      expect(bleOtaV1ErrorMessage(0x14), 'Update connection was lost');
      expect(bleOtaV1ErrorMessage(0x42), contains('0x42'));
    });

    test('uses protocol capability as the authoritative write mode', () {
      expect(bleOtaV1ShouldWriteWithoutResponse(0x0f), isTrue);
      expect(bleOtaV1ShouldWriteWithoutResponse(0x08), isTrue);
      expect(bleOtaV1ShouldWriteWithoutResponse(0x07), isFalse);
    });

    test('marks either an Error state or nonzero code as a failure', () {
      final errorState = Uint8List(12)
        ..[0] = 1
        ..[1] = BleOtaV1State.error.value
        ..[2] = 0x0f;
      final errorCode = Uint8List(12)
        ..[0] = 1
        ..[1] = BleOtaV1State.flashing.value
        ..[2] = 0x0d;

      expect(parseBleOtaV1Status(errorState)!.hasError, isTrue);
      expect(parseBleOtaV1Status(errorCode)!.hasError, isTrue);
    });
  });

  group('BLE OTA legacy protocol', () {
    test('preserves its short-final-chunk framing requirement', () {
      expect(bleOtaV0CanRepresentImageLength(513), isTrue);
      expect(bleOtaV0CanRepresentImageLength(512), isFalse);
      expect(bleOtaV0CanRepresentImageLength(1024), isFalse);
    });

    test('uses a long write when a fixed legacy chunk exceeds the MTU', () {
      expect(bleOtaChunkRequiresLongWrite(23, 512), isTrue);
      expect(bleOtaChunkRequiresLongWrite(515, 512), isFalse);
      expect(bleOtaChunkRequiresLongWrite(23, 20), isFalse);
    });
  });
}
