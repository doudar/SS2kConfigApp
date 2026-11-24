import 'dart:io';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/dircon_client.dart';
import 'package:ss2kconfigapp/utils/constants.dart';

Future<void> _checkDeveloperControls(
  DeviceData data,
  BluetoothDevice device,
) async {
  Map entry(String name) =>
      data.customCharacteristic.firstWhere((c) => c['vName'] == name);
  Future<String> read(String name) async {
    final field = entry(name);
    await data.writeCustomCharacteristic(device, [
      1,
      int.parse(field['reference']),
    ]);
    final text = data.getVnameValue(name, returnNoFirmSupport: true);
    expect(text, isNot(anyOf('null', noFirmSupport)), reason: name);
    return text;
  }

  Future<void> write(String name, String value) async {
    await data.writeToSS2kStrict(device, entry(name), s: value);
    expect(await read(name), value, reason: name);
  }

  final before = <String, String>{};
  for (final name in [
    FTMSModeVname,
    simulateCadVname,
    simulatedCadVname,
    simulateHrVname,
    simulatedHrVname,
    simulateWattsVname,
    simulatedWattsVname,
    simulateTargetWattsVname,
    simulatedTargetWattsVname,
  ]) {
    before[name] = await read(name);
  }
  expect(
    before[simulatedCadVname],
    '0',
    reason: 'Developer controls require a stationary bench.',
  );
  try {
    await write(FTMSModeVname, '0');
    await write(simulateCadVname, 'true');
    await write(simulatedCadVname, '25');
    await write(simulatedCadVname, '0');
    await write(simulateHrVname, 'true');
    await write(simulatedHrVname, '70');
    await write(simulateWattsVname, 'true');
    await write(simulatedWattsVname, '25');
    await write(simulateTargetWattsVname, 'true');
    await write(simulatedTargetWattsVname, '0');
    await write(FTMSModeVname, '5');
  } finally {
    await write(FTMSModeVname, '0');
    for (final name in [
      simulatedCadVname,
      simulatedHrVname,
      simulatedWattsVname,
      simulatedTargetWattsVname,
      simulateCadVname,
      simulateHrVname,
      simulateWattsVname,
      simulateTargetWattsVname,
      FTMSModeVname,
    ]) {
      await write(name, before[name]!);
    }
  }
  print('Developer controls verified and restored.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const host = String.fromEnvironment('SS2K_BENCH_HOST');
  test(
    'SmartBench settings survive two real DirCon connections',
    () async {
      SharedPreferences.setMockInitialValues({});
      final device = BluetoothDevice.fromId('mdns:smartbench-test');
      const previousPair = bool.fromEnvironment('SS2K_BENCH_PREVIOUS_PAIR');
      FlutterSecureStorage.setMockInitialValues({
        if (previousPair)
          'ss2k_pair_alias_${base64UrlEncode(utf8.encode(device.remoteId.str))}':
              'previous-identity',
      });
      const secure = bool.fromEnvironment('SS2K_BENCH_PAIRED');
      const image = String.fromEnvironment('SS2K_BENCH_OTA');
      const expected = String.fromEnvironment('SS2K_BENCH_EXPECT_VERSION');
      const controls = bool.fromEnvironment('SS2K_BENCH_DEVELOPER');
      if (image.isNotEmpty && !secure)
        fail('Hardware OTA requires SS2K_BENCH_PAIRED=true.');
      int approvals = 0;
      int legacyApprovals = 0;
      DeviceData.legacyConnectionPrompt = (_, _, allow, _) {
        legacyApprovals++;
        allow();
      };
      addTearDown(() => DeviceData.legacyConnectionPrompt = null);
      DeviceData.pairingPrompt = (_, _, _) {
        approvals++;
        print("PAIR PENDING");
      };
      addTearDown(() => DeviceData.pairingPrompt = null);
      for (int i = 0; i < (image.isEmpty ? 2 : 3); i++) {
        final data = DeviceData(
          dirConConnector: (_) => DirConClient.connect(host),
        )..advertisedIpAddress = host;
        try {
          await data.connectPreferred(device, waitForSetup: true);
          expect(data.isDirConConnected, isTrue);
          expect(data.hasPairedSession, secure);
          expect(await data.usesPairedSettings(device), secure);
          expect(legacyApprovals, previousPair && !secure ? 1 : 0);
          expect(approvals, secure ? 1 : 0);
          await data.writeCustomCharacteristic(device, [1, 0x25]);
          expect(data.firmwareVersion.value, isNotEmpty);
          if (i == 2 && image.isNotEmpty && expected.isNotEmpty) {
            expect(data.firmwareVersion.value, expected);
          }
          if (secure && controls && i == 0)
            await _checkDeveloperControls(data, device);
          expect(data.getVnameValue(fwVname), isNot(noFirmSupport));
          print(
            'SmartBench connection ${i + 1}: ${data.firmwareVersion.value}',
          );
          if (secure && i == 1 && image.isNotEmpty) {
            final bytes = await File(image).readAsBytes();
            int nextReport = 10;
            await data.streamPairedFirmware(device, bytes, (progress) {
              if (progress * 100 >= nextReport) {
                print('SmartBench OTA $nextReport%');
                nextReport += 10;
              }
            });
            print('SmartBench accepted $image');
            await Future<void>.delayed(const Duration(seconds: 10));
          } else if (secure && i == (image.isEmpty ? 1 : 2)) {
            await data.forgetPairing(device);
            expect(data.hasPairedSession, isFalse);
            print('SmartBench confirmed forget.');
          }
        } finally {
          await data.disconnectPreferred(device);
          data.dispose();
        }
      }
    },
    skip: host.isEmpty,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
