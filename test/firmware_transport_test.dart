import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

void main() {
  test('transport without BLE OTA characteristics reports no package', () {
    final deviceData = DeviceData();

    expect(deviceData.createFirmwareOtaPackage(), isNull);
  });

  test('tracks the complete firmware update session for FTMS suppression', () {
    final deviceData = DeviceData();

    expect(deviceData.isFirmwareUpdateInProgress, isFalse);

    deviceData.beginFirmwareUpdate();
    deviceData.beginFirmwareUpdate();
    expect(deviceData.isFirmwareUpdateInProgress, isTrue);

    deviceData.endFirmwareUpdate();
    expect(deviceData.isFirmwareUpdateInProgress, isTrue);

    deviceData.endFirmwareUpdate();
    expect(deviceData.isFirmwareUpdateInProgress, isFalse);

    // Defensive cleanup must not underflow and poison the next update.
    deviceData.endFirmwareUpdate();
    expect(deviceData.isFirmwareUpdateInProgress, isFalse);
  });
}
