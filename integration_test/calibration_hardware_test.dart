// Hardware check for the calibration screen's pedaling prompts. Runs only when
// a device name is supplied, and talks to that SmartSpin2k over BLE:
//
//   flutter test integration_test/calibration_hardware_test.dart -d windows \
//     --dart-define=SS2K_HW=SmartSpin2k [--dart-define=SS2K_HW_ID=<BLE id>]
//
// Nobody pedals: the firmware's simulated cadence stands in for the rider and
// is dropped to zero the moment the screen says "Stop pedaling", as a rider
// would. The knob really moves to both ends, and the device's calibration and
// learned Power Table are replaced. Simulated cadence is switched off after.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/calibration_screen.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

const _deviceName = String.fromEnvironment('SS2K_HW');
const _deviceId = String.fromEnvironment('SS2K_HW_ID');
const _rpm = 80;

final _clock = Stopwatch();
String _t() => '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(2).padLeft(7)}s';
void _log(String message) => print('[HW ${_t()}] $message');

Future<BluetoothDevice> _scanFor(String name) async {
  final found = Completer<BluetoothDevice>();
  final seen = <String>{};
  final subscription = FlutterBluePlus.onScanResults.listen((results) {
    for (final result in results) {
      final advName = result.advertisementData.advName;
      if (advName != name && result.device.platformName != name) continue;
      final id = result.device.remoteId.str;
      if (seen.add(id)) _log('found $name at $id rssi=${result.rssi}');
      final idMatches = _deviceId.isEmpty || id.toUpperCase() == _deviceId.toUpperCase();
      if (idMatches && !found.isCompleted) found.complete(result.device);
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
    'calibration tells a rider when to stop pedaling on a real SmartSpin2k',
    (tester) async {
      _clock.start();
      SharedPreferences.setMockInitialValues({'calibration_setup': 'physicalStops'});
      final outDir = Directory('build/hw_calibration')..createSync(recursive: true);

      final device = await _scanFor(_deviceName);
      final data = DeviceDataManager.forDevice(device);
      await data.connectPreferred(device, waitForSetup: true);
      _log('connected ${device.remoteId} fw=${data.firmwareVersion.value}');

      Future<void> setCadence(int rpm) async {
        await data.writeCustomCharacteristic(device, [0x02, 0x05, rpm & 0xff, rpm >> 8]);
        _log('simulated cadence -> $rpm rpm');
      }

      Future<void> wait(int ms) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${outDir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        _log('captured $name.png');
      }

      // Firmware-side evidence, stamped on the same clock as the screen.
      final logSub = data.logStream.listen((line) {
        final l = line.toLowerCase();
        if (l.contains('spin down') || l.contains('homing') || l.contains('position found') || l.contains('min') && l.contains('found')) {
          _log('device log: ${line.trim()}');
        }
      });
      final statusSub = data.machineStatusStream.listen((frame) {
        if (frame.isNotEmpty && frame[0] == 0x14) {
          _log('machine status spin-down 0x${frame.length > 1 ? frame[1].toRadixString(16).padLeft(2, '0') : '??'}');
        }
      });

      var cues = 0;
      int? cueAt;
      final failures = <String>[];
      void check(bool ok, String what) {
        _log('${ok ? 'PASS' : 'FAIL'}  $what');
        if (!ok) failures.add(what);
      }

      String? headline() {
        for (final h in ['Start pedaling', 'Keep pedaling…', 'Stop pedaling']) {
          if (find.text(h).evaluate().isNotEmpty) return h;
        }
        return null;
      }

      try {
        // Start from no cadence, with the real sensor out of the way.
        await data.writeCustomCharacteristic(device, [0x02, 0x0F, 0x01]);
        await setCadence(0);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: RepaintBoundary(
              key: boundary,
              child: CalibrationScreen(
                device: device,
                showDeviceHeader: false,
                stopCue: () async {
                  cues++;
                  cueAt ??= _clock.elapsedMilliseconds;
                  _log('STOP CUE fired (#$cues)');
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await capture('1-start-page');

        await tester.tap(find.text('Start Calibration'));
        await tester.pump();
        _log('Start Calibration tapped');

        String? last;
        int? startPedalAt, keepAt, stopAt;
        var pedaling = false;
        var stoppedPedaling = false;
        String? verdict;

        for (var i = 0; i < 4 * 240 && verdict == null; i++) {
          await wait(250);
          await tester.pump();
          final h = headline();
          if (h != last) {
            _log('screen: ${h ?? '(no instruction card)'}');
            last = h;
            if (h == 'Start pedaling') {
              startPedalAt ??= _clock.elapsedMilliseconds;
              await capture('2-start-pedaling');
            } else if (h == 'Keep pedaling…') {
              keepAt ??= _clock.elapsedMilliseconds;
              await capture('3-keep-pedaling');
            } else if (h == 'Stop pedaling') {
              stopAt ??= _clock.elapsedMilliseconds;
              await capture('4-stop-pedaling');
            }
          }
          // The rider starts once asked, a beat later.
          if (h == 'Start pedaling' && !pedaling && _clock.elapsedMilliseconds - startPedalAt! > 1500) {
            pedaling = true;
            await setCadence(_rpm);
          }
          // ...and stops the moment the screen says so.
          if (h == 'Stop pedaling' && pedaling && !stoppedPedaling) {
            stoppedPedaling = true;
            await setCadence(0);
          }
          if (find.text('Finding high resistance').evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
              !File('${outDir.path}/5-finding-high.png').existsSync() &&
              find.text('Finding low resistance').evaluate().isNotEmpty &&
              find.byIcon(Icons.check_circle).evaluate().length >= 2) {
            await capture('5-finding-high');
          }
          if (find.text('Calibration saved').evaluate().isNotEmpty) verdict = 'Calibration saved';
          for (final f in [
            'Calibration did not finish',
            'The SmartSpin2k never started homing',
            'The SmartSpin2k did not respond',
            'Calibration was aborted',
            'The resistance limit was inconsistent',
            'Calibration could not be started',
          ]) {
            if (find.text(f).evaluate().isNotEmpty) verdict = f;
          }
        }
        await wait(800);
        await tester.pump();
        await capture('6-verdict');

        _log('--- timeline ---');
        _log('start pedaling shown at ${startPedalAt}ms, keep at ${keepAt}ms, stop at ${stopAt}ms, cue at ${cueAt}ms');
        _log('verdict: $verdict');
        check(startPedalAt != null, 'screen asked the rider to start pedaling');
        check(keepAt != null, 'screen said keep pedaling once cadence was seen');
        check(stopAt != null, 'screen told the rider to stop pedaling');
        check(cues == 1, 'stop cue fired exactly once (fired $cues)');
        check(verdict == 'Calibration saved', 'run finished after the rider stopped pedaling ($verdict)');
      } finally {
        await logSub.cancel();
        await statusSub.cancel();
        await tester.pumpWidget(const SizedBox());
        await setCadence(0);
        await data.writeCustomCharacteristic(device, [0x02, 0x0F, 0x00]);
        _log('simulated cadence off');
        await data.disconnectPreferred(device);
      }

      _log(failures.isEmpty ? 'ALL CHECKS PASSED' : '${failures.length} FAILED:\n  ${failures.join('\n  ')}');
      expect(failures, isEmpty);
    },
    skip: _deviceName.isEmpty,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
