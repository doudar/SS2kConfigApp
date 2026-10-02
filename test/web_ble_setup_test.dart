import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/web_bluetooth_services.dart';

import 'support/fake_ble_platform.dart';

// Run on Chrome as well as the VM: a VM-only test cannot catch Platform.isAndroid
// throwing in the browser during connection setup or queued GATT writes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;

  test('browser grants configuration, fitness and firmware service access', () {
    expect(
      webBluetoothServices,
      containsAll([
        Guid(csUUID),
        Guid(ftmsServiceUUID),
        Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b'),
      ]),
    );
  });

  test(
    'BLE bootstrap discovers services, subscribes and reads settings',
    () async {
      final harness = await BleHarness.connectViaDiscovery(platform);
      addTearDown(harness.dispose);

      expect(harness.deviceData.isTransportActive, isTrue);
      expect(harness.deviceData.indoorBikeCharacteristic, isNotNull);
      expect(harness.deviceData.ftmsControlPointCharacteristic, isNotNull);
      expect(platform.enabledNow(ccUUID), isTrue);
      expect(
        platform.writeCalls.where(
          (call) => call.characteristicUuid == Guid(ccUUID),
        ),
        isNotEmpty,
      );
    },
  );
}
