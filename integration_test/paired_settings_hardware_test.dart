// Set SS2K_BENCH_BLE_ID to the hardware address. Optionally set SS2K_BENCH_OTA
// to an app image. This test uses the native Bluetooth backend and OS keychain.
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as protocol;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const remote = String.fromEnvironment('SS2K_BENCH_BLE_ID');
  const image = String.fromEnvironment('SS2K_BENCH_OTA');
  const expected = String.fromEnvironment('SS2K_BENCH_VERSION');
  testWidgets(
    'Pair, reconnect, read settings and forget via native Bluetooth',
    (tester) async {
      final scan = FlutterBluePlus.onScanResults
          .expand((results) => results)
          .firstWhere(
            (r) => r.device.remoteId.str.toUpperCase() == remote.toUpperCase(),
          );
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
      late BluetoothDevice device;
      try {
        device = (await scan.timeout(const Duration(seconds: 25))).device;
      } finally {
        await FlutterBluePlus.stopScan();
      }
      int prompts = 0;
      DeviceData.pairingPrompt = (_, _, _) {
        prompts++;
        print('PAIR PENDING');
      };
      addTearDown(() => DeviceData.pairingPrompt = null);
      final connections = image.isEmpty ? 2 : 3;
      for (var i = 0; i < connections; i++) {
        final data = DeviceData();
        try {
          await data.connectPreferred(device, waitForSetup: true);
          expect(data.hasPairedSession, isTrue);
          expect(data.isDirConConnected, isFalse);
          expect(prompts, lessThanOrEqualTo(1));
          await data.writeCustomCharacteristic(device, [
            protocol.read,
            protocol.CommandId.firmwareVer,
          ]);
          expect(data.firmwareVersion.value, isNotEmpty);
          if (image.isNotEmpty && i == 2 && expected.isNotEmpty)
            expect(data.firmwareVersion.value, equals(expected));
          print(
            'Bluetooth session ${i + 1}: ${data.firmwareVersion.value}, MTU ${device.mtuNow}',
          );
          if (image.isNotEmpty && i == 1) {
            int nextReport = 10;
            await data.streamPairedFirmware(
              device,
              await File(image).readAsBytes(),
              (fraction) {
                if (fraction * 100 >= nextReport) {
                  print('Bluetooth firmware $nextReport%');
                  nextReport += 10;
                }
              },
            );
            await Future<void>.delayed(const Duration(seconds: 10));
          } else if (i + 1 == connections) {
            await data.forgetPairing(device);
            expect(data.hasPairedSession, isFalse);
          }
        } finally {
          await data.disconnectPreferred(device);
          data.dispose();
        }
      }
    },
    skip: remote.isEmpty,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
