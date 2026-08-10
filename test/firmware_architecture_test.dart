import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/firmware_architecture.dart';

void main() {
  group('hardware architecture detection', () {
    test('maps known ESP32 revisions', () {
      expect(
        detectHardwareArchitecture('Revision One').architecture,
        FirmwareArchitecture.esp32,
      );
      expect(
        detectHardwareArchitecture('Revision Two').architecture,
        FirmwareArchitecture.esp32,
      );
    });

    test('maps Revision Three to ESP32-S3', () {
      final result = detectHardwareArchitecture('Revision Three (ESP32-S3)');
      expect(result.architecture, FirmwareArchitecture.esp32S3);
      expect(result.assumedLegacy, isFalse);
      expect(result.architecture.firmwareFilename, 'S3firmware.bin');
    });

    test('uses legacy ESP32 path for missing or unknown values', () {
      for (final value in <String?>[null, '', 'Future Revision']) {
        final result = detectHardwareArchitecture(value);
        expect(result.architecture, FirmwareArchitecture.esp32);
        expect(result.assumedLegacy, isTrue);
      }
    });
  });

  test('constructs the exact workflow release asset name', () {
    expect(
      expectedReleaseAssetName('26.8.10'),
      'SmartSpin2kFirmware-26.8.10.bin.zip',
    );
  });

  test('selects only the architecture-specific archive entry', () {
    final entries = ['firmware.bin', 'littlefs.bin', 'nested/S3firmware.bin'];
    expect(
      selectFirmwareArchiveEntry(entries, FirmwareArchitecture.esp32),
      'firmware.bin',
    );
    expect(
      selectFirmwareArchiveEntry(entries, FirmwareArchitecture.esp32S3),
      'nested/S3firmware.bin',
    );
  });

  test('never falls back to ESP32 firmware when the S3 image is absent', () {
    expect(
      () => selectFirmwareArchiveEntry([
        'firmware.bin',
        'littlefs.bin',
      ], FirmwareArchitecture.esp32S3),
      throwsFormatException,
    );
  });

  group('ESP image validation', () {
    Uint8List imageForChip(int chipId) {
      final bytes = Uint8List(32);
      bytes[0] = 0xE9;
      bytes[12] = chipId & 0xff;
      bytes[13] = chipId >> 8;
      return bytes;
    }

    test('accepts matching ESP32 and ESP32-S3 images', () {
      expect(
        () =>
            validateFirmwareImage(imageForChip(0), FirmwareArchitecture.esp32),
        returnsNormally,
      );
      expect(
        () => validateFirmwareImage(
          imageForChip(9),
          FirmwareArchitecture.esp32S3,
        ),
        returnsNormally,
      );
    });

    test('rejects both cross-flash directions', () {
      expect(
        () =>
            validateFirmwareImage(imageForChip(9), FirmwareArchitecture.esp32),
        throwsFormatException,
      );
      expect(
        () => validateFirmwareImage(
          imageForChip(0),
          FirmwareArchitecture.esp32S3,
        ),
        throwsFormatException,
      );
    });

    test('rejects empty and malformed images', () {
      expect(
        () => validateFirmwareImage(Uint8List(0), FirmwareArchitecture.esp32),
        throwsFormatException,
      );
      expect(
        () => validateFirmwareImage(
          Uint8List.fromList([0x00, 0x01]),
          FirmwareArchitecture.esp32,
        ),
        throwsFormatException,
      );
    });
  });
}
