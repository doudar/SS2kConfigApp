// Hardware check for the Simulated Groupset setting. Runs only when a device
// name is supplied, and talks to that SmartSpin2k over BLE:
//
//   flutter test integration_test/virtual_gearing_hardware_test.dart -d windows \
//     --dart-define=SS2K_HW=SmartSpin2k --dart-define=SS2K_HW_ID=<BLE id>
//
// It changes the device's groupset and reboots it, and leaves it on Unlimited.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/virtual_gearing.dart';
import 'package:ss2kconfigapp/widgets/groupset_card.dart';

const _deviceName = String.fromEnvironment('SS2K_HW');

// Every unit advertises as "SmartSpin2k" by default, so pin the one under
// test by its BLE ID when more than one is in range.
const _deviceId = String.fromEnvironment('SS2K_HW_ID');

void _log(String message) => print('[HW] $message');

GroupsetPreset _preset(String name) =>
    groupsetPresets.firstWhere((preset) => preset.name == name);

Future<BluetoothDevice> _scanFor(String name) async {
  final found = Completer<BluetoothDevice>();
  final subscription = FlutterBluePlus.onScanResults.listen((results) {
    for (final result in results) {
      final advName = result.advertisementData.advName;
      final nameMatches =
          advName == name || result.device.platformName == name;
      final idMatches =
          _deviceId.isEmpty ||
          result.device.remoteId.str.toUpperCase() == _deviceId.toUpperCase();
      if (nameMatches && idMatches && !found.isCompleted) {
        found.complete(result.device);
      }
    }
  });
  await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
  try {
    return await found.future.timeout(const Duration(seconds: 25));
  } finally {
    await subscription.cancel();
    await FlutterBluePlus.stopScan();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Simulated Groupset round-trips on a real SmartSpin2k',
    (tester) async {
      final failures = <String>[];
      void check(bool ok, String what) {
        _log('${ok ? 'PASS' : 'FAIL'}  $what');
        if (!ok) failures.add(what);
      }

      _log('scanning for "$_deviceName"');
      var device = await _scanFor(_deviceName);
      var data = DeviceDataManager.forDevice(device);
      await data.connectPreferred(device, waitForSetup: true);
      _log(
        'connected: ${device.remoteId} fw=${data.firmwareVersion.value} '
        'mtu=${device.mtuNow}',
      );

      Map setting(String name) =>
          data.customCharacteristic.firstWhere((c) => c['vName'] == name);
      String? teeth() => setting(gearTeethVname)['value']?.toString();
      String? preset() => setting(gearPresetVname)['value']?.toString();
      String label() => groupsetLabel(teeth(), preset());

      // Forget the local copy so only what the firmware reports is checked.
      void forget() {
        setting(gearTeethVname)['value'] = null;
        setting(gearPresetVname)['value'] = null;
      }

      Future<String> readIndexed() async {
        forget();
        await data.requestSetting(device, gearTeethVname);
        return label();
      }

      Future<String> readSnapshot() async {
        forget();
        await data.requestSettings(device);
        return label();
      }

      _log('initial groupset: ${label()} (preset=${preset()}, teeth=${teeth()})');
      check(
        teeth() != null && teeth() != noFirmSupport,
        'firmware reports gearing support',
      );

      try {
        for (final groupset in groupsetPresets) {
          await data.selectGroupset(device, groupset);
          final indexed = await readIndexed();
          check(
            indexed == groupset.name,
            'select "${groupset.name}" -> indexed read "$indexed"',
          );
          final snapshot = await readSnapshot();
          check(
            snapshot == groupset.name,
            'select "${groupset.name}" -> 0x31 snapshot "$snapshot"',
          );
        }

        // A profile none of the presets match, as the web URL could set.
        await data.writeCustomCharacteristic(device, [
          0x02, 0x34, 0x03, //
          0x93, 0x13, 0x94, 0x13, 0x95, 0x13, // 5011, 5012, 5013
        ]);
        final custom = await readIndexed();
        check(
          custom == 'Custom groupset · 3 gears',
          'custom tooth profile -> "$custom"',
        );

        // The firmware rejects a one-gear profile with 0xff 0x34. That must
        // not make the setting look unsupported.
        await data.writeCustomCharacteristic(device, [
          0x02, 0x34, 0x01, 0x93, 0x13, //
        ]);
        check(
          teeth() != noFirmSupport,
          'rejected write keeps the setting available (value ${teeth()})',
        );
        final afterReject = await readIndexed();
        check(
          afterReject == 'Custom groupset · 3 gears',
          'rejected write leaves the profile unchanged -> "$afterReject"',
        );

        // The real editor: tap a preset, then SAVE.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GroupsetCard(device: device, c: setting(gearTeethVname)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        check(
          find.text('Current custom groupset').evaluate().isNotEmpty,
          'editor shows the custom profile',
        );
        const gravel = 'Gravel 1x13 – Optimized XPLR';
        await tester.ensureVisible(find.text(gravel));
        await tester.tap(find.text(gravel));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await tester.pumpAndSettle();
        final tapped = await readIndexed();
        check(tapped == gravel, 'editor tap -> firmware reports "$tapped"');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GroupsetCard(device: device, c: setting(gearTeethVname)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('SAVE'));
        await tester.tap(find.text('SAVE'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());

        // Persistence across a reboot.
        _log('rebooting');
        await data.writeCommand(device, rebootVname);
        await data.disconnectPreferred(device);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 15)),
        );
        DeviceDataManager.clearDataForDevice(device);
        device = await _scanFor(_deviceName);
        data = DeviceDataManager.forDevice(device);
        await data.connectPreferred(device, waitForSetup: true);
        _log('reconnected after reboot, mtu=${device.mtuNow}');
        check(label() == gravel, 'after reboot (bootstrap) -> "${label()}"');
        final persisted = await readIndexed();
        check(persisted == gravel, 'after reboot (indexed) -> "$persisted"');

        // Mixed Terrain also has to survive a reboot, via the 0x35 path.
        await data.selectGroupset(device, _preset('Mixed Terrain 1x24'));
        await data.writeCommand(device, saveVname);
        await data.writeCommand(device, rebootVname);
        await data.disconnectPreferred(device);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 15)),
        );
        DeviceDataManager.clearDataForDevice(device);
        device = await _scanFor(_deviceName);
        data = DeviceDataManager.forDevice(device);
        await data.connectPreferred(device, waitForSetup: true);
        check(
          label() == 'Mixed Terrain 1x24',
          'Mixed Terrain after reboot -> "${label()}"',
        );
      } finally {
        await data.selectGroupset(device, _preset('Unlimited'));
        await data.writeCommand(device, saveVname);
        _log('restored: ${await readIndexed()}');
        await data.disconnectPreferred(device);
      }

      _log(
        failures.isEmpty
            ? 'ALL CHECKS PASSED'
            : '${failures.length} FAILED:\n  ${failures.join('\n  ')}',
      );
      expect(failures, isEmpty);
    },
    skip: _deviceName.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
