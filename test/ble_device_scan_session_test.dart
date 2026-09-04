import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/ble_scan_results_protocol.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

import 'support/fake_dircon_session.dart';

List<int> _packet({
  required BleScanResultEvent event,
  required int scanId,
  required int sequence,
  List<int> payload = const [],
}) => [
  0x80,
  bleScanResultsReference,
  bleScanResultsVersion,
  event.index,
  scanId & 0xff,
  scanId >> 8,
  sequence & 0xff,
  sequence >> 8,
  0,
  1,
  ...payload,
];

List<int> _deviceBody(String uuid, String name) {
  final uuidBytes = utf8.encode(uuid);
  return [uuidBytes.length, ...uuidBytes, ...utf8.encode(name)];
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scan pauses FTMS and preserves results until disconnect', () async {
    final device = BluetoothDevice.fromId('00:00:00:00:00:34');
    final connector = FakeDirConConnector();
    final deviceData = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = '192.168.1.50';
    addTearDown(deviceData.dispose);

    await deviceData.connectPreferred(device, waitForSetup: true);
    final session = connector.first;

    // Drain the post-connection quiet-window block so this test begins with
    // genuinely live FTMS channels.
    await deviceData.unblockFtmsNotifications(device);
    expect(session.notificationsEnabledNow(ftmsIndoorBikeDataUUID), isTrue);

    var scanCommandCount = session
        .writesFor(ccUUID)
        .where((value) => value.length >= 3 && value[1] == 0x24)
        .length;
    final firstScan = deviceData.scanForBleDevices(device);
    expect(deviceData.bleDeviceScanInProgress.value, isTrue);
    await _waitUntil(
      () =>
          session
              .writesFor(ccUUID)
              .where((value) => value.length >= 3 && value[1] == 0x24)
              .length >
          scanCommandCount,
    );

    expect(deviceData.isFtmsNotificationsBlocked, isTrue);
    expect(session.notificationsEnabledNow(ftmsIndoorBikeDataUUID), isFalse);
    expect(
      session.notificationsEnabledNow(FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID),
      isFalse,
    );

    session.emitNotification(
      ccUUID,
      _packet(event: BleScanResultEvent.begin, scanId: 1, sequence: 0),
    );
    session.emitNotification(
      ccUUID,
      _packet(
        event: BleScanResultEvent.device,
        scanId: 1,
        sequence: 0,
        payload: _deviceBody('0x180d', 'COROS Heart Rate Monitor'),
      ),
    );
    session.emitNotification(
      ccUUID,
      _packet(event: BleScanResultEvent.end, scanId: 1, sequence: 1),
    );
    await firstScan;

    expect(deviceData.bleDeviceScanInProgress.value, isFalse);
    expect(deviceData.isFtmsNotificationsBlocked, isFalse);
    expect(session.notificationsEnabledNow(ftmsIndoorBikeDataUUID), isTrue);

    scanCommandCount++;
    final secondScan = deviceData.scanForBleDevices(device);
    await _waitUntil(
      () =>
          session
              .writesFor(ccUUID)
              .where((value) => value.length >= 3 && value[1] == 0x24)
              .length >
          scanCommandCount,
    );
    session.emitNotification(
      ccUUID,
      _packet(event: BleScanResultEvent.begin, scanId: 2, sequence: 0),
    );
    session.emitNotification(
      ccUUID,
      _packet(
        event: BleScanResultEvent.device,
        scanId: 2,
        sequence: 0,
        payload: _deviceBody('0x1818', 'SmartBench'),
      ),
    );
    session.emitNotification(
      ccUUID,
      _packet(event: BleScanResultEvent.end, scanId: 2, sequence: 1),
    );
    await secondScan;

    final foundDevices = deviceData.customCharacteristic.firstWhere(
      (characteristic) => characteristic['vName'] == foundDevicesVname,
    );
    final encoded = foundDevices['value'] as String;
    expect(encoded, contains('COROS Heart Rate Monitor'));
    expect(encoded, contains('SmartBench'));
  });
}
