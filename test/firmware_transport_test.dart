import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

void main() {
  test('transport without BLE OTA characteristics reports no package', () {
    final deviceData = DeviceData();

    expect(deviceData.createFirmwareOtaPackage(), isNull);
  });
}
