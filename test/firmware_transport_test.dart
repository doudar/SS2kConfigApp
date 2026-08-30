import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

void main() {
  test('transport without BLE OTA characteristics reports no package', () {
    final deviceData = DeviceData();

    expect(deviceData.createFirmwareOtaPackage(), isNull);
  });

  test('FTMS subscription blocks are reference counted', () async {
    final deviceData = DeviceData();
    final device = BluetoothDevice.fromId(
      '00000000-0000-0000-0000-000000000001',
    );

    await deviceData.blockFtmsNotifications();
    await deviceData.blockFtmsNotifications();
    expect(deviceData.isFtmsNotificationsBlocked, isTrue);

    await deviceData.unblockFtmsNotifications(device);
    expect(deviceData.isFtmsNotificationsBlocked, isTrue);

    await deviceData.unblockFtmsNotifications(device);
    expect(deviceData.isFtmsNotificationsBlocked, isFalse);

    // Defensive cleanup must not underflow and poison the next block.
    await deviceData.unblockFtmsNotifications(device);
    expect(deviceData.isFtmsNotificationsBlocked, isFalse);
  });

  test('prefers the full custom device name over the BLE advertisement', () {
    final deviceData = DeviceData();
    final nameSetting = deviceData.customCharacteristic.firstWhere(
      (setting) => setting['vName'] == 'BLE_deviceName',
    );

    expect(deviceData.preferredDeviceName('SmartSpin'), 'SmartSpin');

    nameSetting['value'] = 'Full SmartSpin2k Name';
    expect(
      deviceData.preferredDeviceName('Full SmartS'),
      'Full SmartSpin2k Name',
    );
  });
}
