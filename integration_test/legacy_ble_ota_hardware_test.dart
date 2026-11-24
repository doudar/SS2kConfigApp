// Native BLE transfer and independent post-reboot readback. Without an image,
// this test only identifies the trainer and reports the OTA protocol.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss2kconfigapp/utils/bleOTA.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/firmware_architecture.dart';
import 'package:ss2kconfigapp/utils/firmware_authenticity.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const remote = String.fromEnvironment('SS2K_BENCH_BLE_ID');
  const archive = String.fromEnvironment('SS2K_BENCH_OTA');
  const target = String.fromEnvironment('SS2K_BENCH_VERSION');
  const board = String.fromEnvironment('SS2K_BENCH_CHIP');
  testWidgets(
    'Legacy BLE firmware transfer and reboot',
    (tester) async {
      final found = FlutterBluePlus.onScanResults
          .expand((batch) => batch)
          .firstWhere(
            (r) => r.device.remoteId.str.toUpperCase() == remote.toUpperCase(),
          );
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 25));
      late ScanResult result;
      try {
        result = await found.timeout(const Duration(seconds: 30));
      } finally {
        await FlutterBluePlus.stopScan();
      }
      final device = result.device;
      print(
        'OTA bench: ${result.advertisementData.advName} ${device.remoteId}',
      );
      await device.connect(license: License.nonprofit);
      addTearDown(device.disconnect);
      final services = await device.discoverServices();
      print('OTA bench: services ${services.map((s) => s.uuid).join(', ')}');
      Future<String> version(List<BluetoothService> services) async {
        final chars = services.expand((s) => s.characteristics);
        final revision = chars.where((c) => c.uuid == Guid('2a26')).firstOrNull;
        if (revision != null) {
          return utf8
              .decode(await revision.read())
              .replaceAll('\u0000', '')
              .trim();
        }
        final custom = chars.singleWhere((c) => c.uuid == Guid(ccUUID));
        await custom.setNotifyValue(true);
        final response = custom.onValueReceived
            .firstWhere((v) => v.length > 2 && v[0] == 0x80 && v[1] == 0x25)
            .timeout(const Duration(seconds: 10));
        await custom.write([1, 0x25]);
        return utf8.decode((await response).sublist(2)).trim();
      }

      final original = await version(services);
      print('OTA bench: starting firmware $original');
      final service = services.singleWhere(
        (s) => s.uuid == Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b'),
      );
      final data = service.characteristics.singleWhere(
        (c) => c.uuid == Guid('62ec0272-3ec5-11eb-b378-0242ac130005'),
      );
      final control = service.characteristics.singleWhere(
        (c) => c.uuid == Guid('62ec0272-3ec5-11eb-b378-0242ac130003'),
      );
      final status = await control.read();
      print(
        'OTA bench: running=$original protocol=${parseBleOtaV1Status(status) == null ? 0 : 1} mtu=${device.mtuNow}',
      );
      if (archive.isEmpty) return;
      expect(target, isNotEmpty);
      expect(original, isNotEmpty);
      expect(
        original,
        isNot(target),
        reason: 'Choose a different version for verifiable readback.',
      );
      final arch = FirmwareArchitecture.values.byName(board);
      final verifier = FirmwareAuthenticity.fromPem(
        await rootBundle.loadString('assets/ss2k-release-public.pem'),
      );
      final file = File(archive);
      final image = verifier.local(
        file.uri.pathSegments.last,
        await file.readAsBytes(),
        arch,
      );
      final writer = Esp32OtaPackage(data, control);
      final progress = writer.percentageStream.distinct().listen(
        (p) => print('OTA bench: $p%'),
      );
      addTearDown(progress.cancel);
      final reboot = device.connectionState.firstWhere(
        (s) => s == BluetoothConnectionState.disconnected,
      );
      print(
        'OTA bench: uploading ${image.filename}, ${image.bytes.length} bytes, target=$target',
      );
      try {
        await writer.updateFirmware(
          device,
          2,
          service,
          data,
          control,
          firmware: image.bytes,
        );
        expect(writer.firmwareupdate, isTrue);
      } on BleOtaCompletionUnconfirmed {
        print('OTA bench: checking for reboot after missing terminal receipt');
      }
      await reboot.timeout(const Duration(seconds: 60));
      for (int attempt = 0; attempt < 10 && !device.isConnected; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await device.connect(
            license: License.nonprofit,
            timeout: const Duration(seconds: 10),
          );
        } catch (_) {
          if (attempt == 9) rethrow;
        }
      }
      final reported = await version(await device.discoverServices());
      print('OTA bench: post-reboot running=$reported');
      expect(reported, target);
    },
    skip: remote.isEmpty,
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
