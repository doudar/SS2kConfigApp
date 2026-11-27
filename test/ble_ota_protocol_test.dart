import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleOTA.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  int get mtuNow => 515;
}

class _Service extends Fake implements BluetoothService {}

class _Characteristic extends Fake implements BluetoothCharacteristic {
  final events = StreamController<List<int>>.broadcast(sync: true);
  List<int> readableStatus = [];
  void Function(List<int> bytes)? onWrite;
  void publish(List<int> bytes) {
    readableStatus = bytes;
    events.add(bytes);
  }

  @override
  Stream<List<int>> get onValueReceived => events.stream;
  @override
  Future<List<int>> read({int timeout = 15}) async => readableStatus;
  @override
  Future<bool> setNotifyValue(
    bool notify, {
    int timeout = 15,
    bool forceIndications = false,
  }) async => true;
  @override
  Future<void> write(
    List<int> bytes, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async => onWrite?.call(bytes);
}

void main() {
  for (final legacyError in [true, false]) {
    test(
      'protocol 0 starts with data and honors terminal notification (error=$legacyError)',
      () async {
        final data = _Characteristic(), ctl = _Characteristic();
        addTearDown(data.events.close);
        addTearDown(ctl.events.close);
        final lengths = <int>[];
        ctl.onWrite = (_) => fail('Early 26.x firmware has no START command');
        data.onWrite = (bytes) {
          lengths.add(bytes.length);
          ctl.publish([0x02]);
          if (bytes.length < 512) ctl.publish([legacyError ? 0x04 : 0x05]);
        };
        final writer = Esp32OtaPackage(data, ctl);
        final update = writer.updateFirmware(
          _Device(),
          2,
          _Service(),
          data,
          ctl,
          firmware: Uint8List(1031),
        );
        if (legacyError) {
          await expectLater(update, throwsStateError);
        } else {
          await update;
        }
        expect(writer.firmwareupdate, !legacyError);
        expect(lengths, [512, 512, 7]);
      },
    );
  }

  test(
    'protocol 1 waits for the last flash receipt before sending FINISH',
    () async {
      final data = _Characteristic(), ctl = _Characteristic();
      addTearDown(data.events.close);
      addTearDown(ctl.events.close);
      const size = 66001;
      var sent = 0;
      var finished = false;
      final finalWrite = Completer<void>();
      void publish(BleOtaV1State state, int received, int declared) {
        final packet = Uint8List(12)
          ..[0] = 1
          ..[1] = state.value
          ..[3] = 15;
        ByteData.sublistView(packet)
          ..setUint32(4, received, Endian.little)
          ..setUint32(8, declared, Endian.little);
        ctl.publish(packet);
      }

      publish(BleOtaV1State.waiting, 0, 0);
      ctl.onWrite = (packet) {
        if (packet.first == 1) {
          publish(BleOtaV1State.updating, 0, size);
        } else {
          expect(packet, [2]);
          finished = true;
          publish(BleOtaV1State.rebooting, size, size);
        }
      };
      data.onWrite = (bytes) {
        sent += bytes.length;
        if (sent == 65536) publish(BleOtaV1State.flashing, sent, size);
        if (sent == size) finalWrite.complete();
      };
      final writer = Esp32OtaPackage(data, ctl);
      final update = writer.updateFirmware(
        _Device(),
        2,
        _Service(),
        data,
        ctl,
        firmware: Uint8List(size),
      );
      await finalWrite.future;
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      publish(BleOtaV1State.flashing, size, size);
      await update;
      expect(finished, isTrue);
      expect(writer.firmwareupdate, isTrue);
    },
  );
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
