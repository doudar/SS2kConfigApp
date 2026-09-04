import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/widgets/dropdown_card.dart';

void main() {
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
