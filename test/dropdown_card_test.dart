import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_scan_results_protocol.dart';
import 'package:ss2kconfigapp/utils/ble_sensor_services.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/nearby_ble_devices.dart';
import 'package:ss2kconfigapp/widgets/dropdown_card.dart';

void main() {
  setUp(() => NearbyBleDevices.instance.clear());
  tearDown(() => NearbyBleDevices.instance.clear());
  for (final sensor in [
    (connectedPWRVname, bleCyclingPowerDeviceUuid),
    (connectedHRMVname, bleHeartRateDeviceUuid),
  ]) {
    testWidgets('clearing scan results preserves saved ${sensor.$1}', (
      tester,
    ) async {
      final device = BluetoothDevice.fromId('00:00:00:00:00:35');
      final deviceData = DeviceData();
      DeviceDataManager.updateDataForDevice(device, deviceData);
      addTearDown(() {
        DeviceDataManager.clearDataForDevice(device);
        deviceData.dispose();
      });
      final setting = deviceData.customCharacteristic.firstWhere(
        (c) => c['vName'] == sensor.$1,
      );
      setting['value'] = 'Saved sensor';
      NearbyBleDevices.instance.reconcileFirmwareDevice(
        BleScanDevice(uuid: sensor.$2, name: 'Old sensor'),
      );
      deviceData.mergeAppDiscoveredBleDevices([
        BleScanDevice(uuid: sensor.$2, name: 'Old sensor'),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DropdownCard(device: device, c: setting),
          ),
        ),
      );
      expect(
        deviceData.getVnameValue(foundDevicesVname),
        contains('Old sensor'),
      );
      await tester.scrollUntilVisible(find.text('Old sensor'), 50);
      expect(find.text('Old sensor'), findsOneWidget);
      final clearButton = find.widgetWithText(TextButton, 'Clear Scan Results');
      deviceData.bleDeviceScanInProgress.value = true;
      await tester.pump();
      expect(tester.widget<TextButton>(clearButton).onPressed, isNull);
      deviceData.bleDeviceScanInProgress.value = false;
      await tester.pump();
      await tester.tap(clearButton);
      await tester.pump();

      expect(find.text('Old sensor'), findsNothing);
      expect(find.text('Saved sensor'), findsOneWidget);
      expect(find.text('any'), findsOneWidget);
      expect(find.text('none'), findsOneWidget);
      expect(setting['value'], 'Saved sensor');
      // Opening either picker seeds from the app-wide discoveries again.
      DeviceDataManager.forDevice(device);
      expect(
        deviceData.getVnameValue(foundDevicesVname),
        isNot(contains('Old sensor')),
      );

      // Later discoveries must not resurrect the cleared connection cache.
      deviceData.mergeAppDiscoveredBleDevices([
        BleScanDevice(uuid: sensor.$2, name: 'New sensor'),
      ]);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('New sensor'), 50);
      expect(find.text('New sensor'), findsOneWidget);
      expect(find.text('Old sensor'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saved BLE device picker always offers any and none', (
    tester,
  ) async {
    final device = BluetoothDevice.fromId('00:00:00:00:00:32');
    final deviceData = DeviceData();
    DeviceDataManager.updateDataForDevice(device, deviceData);
    addTearDown(() {
      DeviceDataManager.clearDataForDevice(device);
      deviceData.dispose();
    });

    final powerMeter = deviceData.customCharacteristic.firstWhere(
      (characteristic) => characteristic['vName'] == connectedPWRVname,
    );
    final foundDevices = deviceData.customCharacteristic.firstWhere(
      (characteristic) => characteristic['vName'] == foundDevicesVname,
    );
    powerMeter.remove('value');
    foundDevices['value'] = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DropdownCard(device: device, c: powerMeter),
        ),
      ),
    );

    expect(find.text('any'), findsOneWidget);
    expect(find.text('none'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved BLE device picker shows immediate scan feedback', (
    tester,
  ) async {
    final device = BluetoothDevice.fromId('00:00:00:00:00:33');
    final deviceData = DeviceData();
    DeviceDataManager.updateDataForDevice(device, deviceData);
    addTearDown(() {
      DeviceDataManager.clearDataForDevice(device);
      deviceData.dispose();
    });

    final powerMeter = deviceData.customCharacteristic.firstWhere(
      (characteristic) => characteristic['vName'] == connectedPWRVname,
    );
    powerMeter['value'] = 'any';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DropdownCard(device: device, c: powerMeter),
        ),
      ),
    );

    expect(find.text('SCAN'), findsOneWidget);
    deviceData.bleDeviceScanInProgress.value = true;
    await tester.pump();

    expect(find.text('SCANNING…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton).first).onPressed,
      isNull,
    );
  });
}
