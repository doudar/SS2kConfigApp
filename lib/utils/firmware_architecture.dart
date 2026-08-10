import 'dart:typed_data';

enum FirmwareArchitecture {
  esp32('ESP32', 'firmware.bin', 0),
  esp32S3('ESP32-S3', 'S3firmware.bin', 9);

  const FirmwareArchitecture(
    this.displayName,
    this.firmwareFilename,
    this.espChipId,
  );

  final String displayName;
  final String firmwareFilename;
  final int espChipId;
}

class HardwareDetection {
  const HardwareDetection({
    required this.hardwareName,
    required this.architecture,
    this.assumedLegacy = false,
  });

  final String hardwareName;
  final FirmwareArchitecture architecture;
  final bool assumedLegacy;
}

HardwareDetection detectHardwareArchitecture(String? response) {
  switch (response?.trim()) {
    case 'Revision One':
      return const HardwareDetection(
        hardwareName: 'Revision One',
        architecture: FirmwareArchitecture.esp32,
      );
    case 'Revision Two':
      return const HardwareDetection(
        hardwareName: 'Revision Two',
        architecture: FirmwareArchitecture.esp32,
      );
    case 'Revision Three (ESP32-S3)':
      return const HardwareDetection(
        hardwareName: 'Revision Three (ESP32-S3)',
        architecture: FirmwareArchitecture.esp32S3,
      );
    default:
      return const HardwareDetection(
        hardwareName: 'Legacy/unknown hardware',
        architecture: FirmwareArchitecture.esp32,
        assumedLegacy: true,
      );
  }
}

String expectedReleaseAssetName(String tag) =>
    'SmartSpin2kFirmware-$tag.bin.zip';

String selectFirmwareArchiveEntry(
  Iterable<String> entryNames,
  FirmwareArchitecture architecture,
) {
  final expected = architecture.firmwareFilename;
  final matches = entryNames.where(
    (name) => name.split(RegExp(r'[/\\]')).last == expected,
  );
  if (matches.length != 1) {
    throw FormatException(
      '$expected was not found exactly once in this release. '
      'This release does not support ${architecture.displayName}.',
    );
  }
  return matches.single;
}

/// Validates the ESP image header and prevents cross-flashing between chips.
/// ESP image format stores the target chip id as a little-endian uint16 at 12.
void validateFirmwareImage(
  Uint8List bytes,
  FirmwareArchitecture expectedArchitecture,
) {
  if (bytes.isEmpty) {
    throw const FormatException('The selected firmware file is empty.');
  }
  if (bytes.length < 14 || bytes[0] != 0xE9) {
    throw const FormatException(
      'The selected file is not a valid ESP firmware image.',
    );
  }

  final chipId = bytes[12] | (bytes[13] << 8);
  if (chipId != expectedArchitecture.espChipId) {
    final actual = switch (chipId) {
      0 => FirmwareArchitecture.esp32.displayName,
      9 => FirmwareArchitecture.esp32S3.displayName,
      _ => 'unknown chip id $chipId',
    };
    throw FormatException(
      'Firmware targets $actual, but the connected device requires '
      '${expectedArchitecture.displayName}.',
    );
  }
}
