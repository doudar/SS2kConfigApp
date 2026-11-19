// Connects to a SmartSpin2k, turns simulated cadence off, reports its homing
// range and streams its log for a while. Diagnostic only.
//
//   flutter test integration_test/ss2k_probe_hardware_test.dart -d windows \
//     --dart-define=SS2K_HW=SmartSpin2k [--dart-define=SS2K_HW_ID=<BLE id>]

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

const _deviceName = String.fromEnvironment('SS2K_HW');
const _deviceId = String.fromEnvironment('SS2K_HW_ID');
const _listenSeconds = int.fromEnvironment('SS2K_LISTEN', defaultValue: 15);

void _log(String m) => print('[PROBE] $m');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe', (tester) async {
    final found = Completer<BluetoothDevice>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        if ((r.advertisementData.advName == _deviceName || r.device.platformName == _deviceName) &&
            (_deviceId.isEmpty || id.toUpperCase() == _deviceId.toUpperCase()) &&
            !found.isCompleted) {
          _log('found $id rssi=${r.rssi}');
          found.complete(r.device);
        }
      }
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
    final device = await found.future.timeout(const Duration(seconds: 25));
    await sub.cancel();
    await FlutterBluePlus.stopScan();

    final data = DeviceDataManager.forDevice(device);
    await data.connectPreferred(device, waitForSetup: true);
    _log('connected fw=${data.firmwareVersion.value}');
    await data.writeCustomCharacteristic(device, [0x02, 0x0F, 0x00]);
    _log('simulated cadence off');
    for (final v in [BLE_hMinVname, BLE_hMaxVname, homingSensitivityVname, simulateCadVname]) {
      await data.requestSetting(device, v);
      _log('$v = ${data.getVnameValue(v)}');
    }

    final logSub = data.logStream.listen((l) => _log('log: ${l.trim()}'));
    final logChar = data.customCharacteristic.firstWhere((c) => c['vName'] == BLE_logStreamVname);
    await data.writeToSS2kStrict(device, logChar, s: '1');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: _listenSeconds)));
    await data.writeToSS2kStrict(device, logChar, s: '0');
    await logSub.cancel();
    await data.disconnectPreferred(device);
  }, skip: _deviceName.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}
