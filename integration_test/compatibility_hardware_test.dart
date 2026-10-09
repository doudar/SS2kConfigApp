// Hardware check for the bike compatibility checker. Runs only when a device
// is named, and drives the real CompatibilityChecker against it over BLE.
//
//   flutter test integration_test/compatibility_hardware_test.dart -d windows \
//     --dart-define=COMPAT_ID=20:E7:C8:28:D8:56 \
//     --dart-define=COMPAT_SIMULATE=180 --dart-define=COMPAT_EXPECT=passed
//
// Defines:
//   COMPAT_ID            BLE id of the device under test (preferred).
//   COMPAT_NAME          Substring of the advertised name, used when no id is
//                        set.
//   COMPAT_SERVICE       Advertised service UUID, used when neither of the
//                        above is set. For Android peripherals such as
//                        Grupetto, which rotate their address every few
//                        minutes and advertise no name (Grupetto: 180a).
//   COMPAT_SIMULATE      Watts. When above 0 the target is treated as a
//                        SmartSpin2k standing in for a bike: before the check
//                        its simulated power and cadence are switched on, and
//                        they are switched off again afterwards.
//   COMPAT_SIMULATE_CAD  Simulated cadence in rpm (default 85).
//   COMPAT_EXPECT        passed | listening | a CompatibilityFailure name such
//                        as noData. Unset only logs what happened.
//   COMPAT_SECONDS       How long the check listens for data (default 45).
//
// Other examples:
//   ... --dart-define=COMPAT_ID=<id> --dart-define=COMPAT_EXPECT=noData
//   ... --dart-define=COMPAT_NAME=Wahoo --dart-define=COMPAT_SECONDS=60
//   ... --dart-define=COMPAT_SERVICE=180a --dart-define=COMPAT_EXPECT=noData
//
// A SmartSpin2k is deliberately not accepted by classifyCompatibilityCandidate,
// so the device is matched by id, name or service only; its classification is logged.

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ss2kconfigapp/utils/compatibility/compatibility_checker.dart';
import 'package:ss2kconfigapp/utils/constants.dart';

const _id = String.fromEnvironment('COMPAT_ID');
const _name = String.fromEnvironment('COMPAT_NAME');
const _service = String.fromEnvironment('COMPAT_SERVICE');
const _simulateWatts = int.fromEnvironment('COMPAT_SIMULATE');
const _simulateCadence = int.fromEnvironment(
  'COMPAT_SIMULATE_CAD',
  defaultValue: 85,
);
const _expect = String.fromEnvironment('COMPAT_EXPECT');
const _seconds = int.fromEnvironment('COMPAT_SECONDS', defaultValue: 45);

const _skip = _id == '' && _name == '' && _service == '';

void _log(String message) => print(
  '[COMPAT ${DateTime.now().toIso8601String().substring(11, 23)}] $message',
);

String _hex(List<int> v) =>
    v.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

bool _terminal(CompatibilityStage stage) =>
    stage == CompatibilityStage.passed || stage == CompatibilityStage.failed;

bool _matches(ScanResult result) {
  // The id wins, then the name, then an advertised service.
  if (_id.isNotEmpty) {
    return result.device.remoteId.str.toUpperCase() == _id.toUpperCase();
  }
  if (_name.isEmpty) {
    return result.advertisementData.serviceUuids.contains(Guid(_service));
  }
  final wanted = _name.toLowerCase();
  return result.advertisementData.advName.toLowerCase().contains(wanted) ||
      result.device.platformName.toLowerCase().contains(wanted);
}

Future<BluetoothDevice> _scanForTarget() async {
  final found = Completer<ScanResult>();
  final seen = <String>{};
  final subscription = FlutterBluePlus.onScanResults.listen((results) {
    for (final r in results) {
      if (seen.add(r.device.remoteId.str)) {
        _log(
          'saw ${r.device.remoteId} "${r.advertisementData.advName}" '
          'rssi=${r.rssi} services=${r.advertisementData.serviceUuids}',
        );
      }
      if (_matches(r) && !found.isCompleted) found.complete(r);
    }
  });
  await FlutterBluePlus.startScan(timeout: const Duration(seconds: 45));
  try {
    final result = await found.future.timeout(const Duration(seconds: 50));
    _log(
      'target ${result.device.remoteId} '
      '"${result.advertisementData.advName}" classification='
      '${classifyCompatibilityCandidate(result.advertisementData)}',
    );
    return result.device;
  } finally {
    await subscription.cancel();
    await FlutterBluePlus.stopScan();
  }
}

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];

/// Connects to the SmartSpin2k, writes each frame to its custom
/// characteristic, and disconnects.
Future<void> _writeFrames(
  BluetoothDevice device,
  List<List<int>> frames,
) async {
  await device.connect(
    license: License.nonprofit,
    timeout: const Duration(seconds: 15),
  );
  try {
    final services = await device.discoverServices();
    final characteristic = services
        .firstWhere((s) => s.uuid == Guid(csUUID))
        .characteristics
        .firstWhere((c) => c.uuid == Guid(ccUUID));
    for (final frame in frames) {
      _log('simulate write ${_hex(frame)}');
      await characteristic.write(frame);
    }
  } finally {
    await device.disconnect();
  }
}

/// Turns simulated power and cadence on, and registers their removal.
Future<void> _startSimulation(BluetoothDevice device) async {
  addTearDown(() async {
    try {
      await _writeFrames(device, [
        [0x02, 0x0E, 0x00],
        [0x02, 0x0F, 0x00],
      ]);
      _log('simulation switched off');
    } catch (e) {
      _log('FAILED to switch simulation off: $e');
    }
  });
  await _writeFrames(device, [
    [0x02, 0x0E, 0x01],
    [0x02, 0x03, ..._le16(_simulateWatts)],
    [0x02, 0x0F, 0x01],
    [0x02, 0x05, ..._le16(_simulateCadence)],
  ]);
}

/// Logs every packet and connection event for [device].
List<StreamSubscription<dynamic>> _watch(BluetoothDevice device) => [
  device.connectionState.listen(
    (s) => _log('connectionState=$s reason=${device.disconnectReason}'),
  ),
  FlutterBluePlus.events.onCharacteristicReceived.listen(
    (e) => _log(
      'rx ${e.characteristic.uuid} [${e.value.length}] ${_hex(e.value)}',
    ),
  ),
];

void _logState(CompatibilityChecker checker, String label) {
  checker.state.addListener(() {
    final s = checker.state.value;
    _log(
      '$label state ${s.stage} power=${s.power}/${s.powerSeen} '
      'cadence=${s.cadence}/${s.cadenceSeen} failure=${s.failure}',
    );
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'compatibility check against real hardware',
    (tester) async {
      final failureNames = CompatibilityFailure.values.map((f) => f.name);
      if (_expect.isNotEmpty &&
          _expect != 'passed' &&
          _expect != 'listening' &&
          !failureNames.contains(_expect)) {
        fail(
          'COMPAT_EXPECT "$_expect" is not passed, listening or one of '
          '${failureNames.join(', ')}',
        );
      }

      final device = await _scanForTarget();
      if (_simulateWatts > 0) await _startSimulation(device);

      final watchers = _watch(device);
      final checker = CompatibilityChecker(
        device,
        listenTimeout: const Duration(seconds: _seconds),
      );
      _logState(checker, 'check');
      unawaited(checker.run());

      final end = DateTime.now().add(const Duration(seconds: _seconds + 15));
      while (DateTime.now().isBefore(end)) {
        final stage = checker.state.value.stage;
        if (_terminal(stage)) break;
        if (_expect == 'listening' && stage == CompatibilityStage.listening) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final result = checker.state.value;
      _log('FINAL ${result.stage} failure=${result.failure}');
      await Future<void>.delayed(const Duration(seconds: 2));
      for (final w in watchers) {
        await w.cancel();
      }
      await checker.dispose();

      switch (_expect) {
        case '':
          break;
        case 'passed':
          expect(result.stage, CompatibilityStage.passed);
        case 'listening':
          expect(result.stage, CompatibilityStage.listening);
        default:
          expect(result.stage, CompatibilityStage.failed);
          expect(result.failure?.name, _expect);
      }
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'restarting a check does not tear down the new link',
    (tester) async {
      final device = await _scanForTarget();
      if (_simulateWatts > 0) await _startSimulation(device);

      final watchers = _watch(device);
      final a = CompatibilityChecker(
        device,
        listenTimeout: const Duration(seconds: _seconds),
      );
      final b = CompatibilityChecker(
        device,
        listenTimeout: const Duration(seconds: _seconds),
      );
      _logState(a, 'A');
      _logState(b, 'B');

      try {
        // Mirror the screen: retire A while it is mid-connect, then start B
        // only once A's disposal has finished.
        unawaited(a.run());
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await a.dispose();
        _log('A disposed, starting B');

        // Armed by B's first connection: a stale disconnect from A lands
        // while B is still discovering and subscribing, and B would quietly
        // retry past it, so waiting for `listening` to arm would miss it.
        var connected = false;
        var dropped = false;
        final dropWatch = device.connectionState.listen((s) {
          if (s == BluetoothConnectionState.connected) connected = true;
          if (connected &&
              s == BluetoothConnectionState.disconnected &&
              b.state.value.stage != CompatibilityStage.passed) {
            dropped = true;
            _log('DROP after B connected');
          }
        });
        unawaited(b.run());

        final end = DateTime.now().add(const Duration(seconds: _seconds + 15));
        while (DateTime.now().isBefore(end) &&
            b.state.value.stage == CompatibilityStage.connecting) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(
          b.state.value.stage,
          anyOf(CompatibilityStage.listening, CompatibilityStage.passed),
          reason:
              'B ended in ${b.state.value.stage} '
              '${b.state.value.failure}',
        );

        // Hold for a few seconds (or until a simulated bike passes) and make
        // sure the link survives.
        final hold = DateTime.now().add(
          Duration(seconds: _simulateWatts > 0 ? _seconds : 4),
        );
        while (DateTime.now().isBefore(hold) &&
            !_terminal(b.state.value.stage)) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        _log('B ended in ${b.state.value.stage} ${b.state.value.failure}');
        await dropWatch.cancel();

        expect(dropped, isFalse, reason: 'link dropped after B connected');
        expect(
          b.state.value.failure,
          isNot(CompatibilityFailure.connectionFailed),
        );
        if (_simulateWatts > 0) {
          expect(b.state.value.stage, CompatibilityStage.passed);
        }
      } finally {
        for (final w in watchers) {
          await w.cancel();
        }
        await a.dispose();
        await b.dispose();
      }
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
