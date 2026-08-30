// Transport-selection coverage for the DIRCON dispatch path — the Plan 1 test
// debt that was blocked on an injectable DirConSession (plan §7.2).
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';

import 'support/fake_dircon_session.dart';

const _ipAddress = '192.168.1.50';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BluetoothDevice device;

  setUp(() {
    device = BluetoothDevice.fromId('00:00:00:00:00:2B');
  });

  // The seam that makes the DIRCON->BLE fallback's own timeout satisfiable.
  //
  // The sweep is one round-trip per custom characteristic — ~80 s on a cold
  // session — so the fallback's 10 s bound around a `setupConnection` that
  // awaits it could never be met. It fired on every transition, freeing the
  // caller while the work carried on, and skipping the transport bookkeeping
  // that followed it. Bringing the transport up has to be separable from
  // polling settings.
  test('setupConnection can bring the transport up without the settings sweep', () async {
    final connector = FakeDirConConnector();
    final deviceData = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = _ipAddress;
    await deviceData.connectPreferred(device, waitForSetup: true);
    final session = connector.first;

    final afterBootstrap = session.writesFor(ccUUID).length;
    expect(afterBootstrap, greaterThan(0), reason: 'bootstrap did sweep');

    // A full re-bootstrap, minus the poll: not one settings read goes out.
    await deviceData.setupConnection(
      device,
      forceRefresh: true,
      sweepSettings: false,
    );
    expect(session.writesFor(ccUUID).length, afterBootstrap);
    expect(deviceData.transportState.value.phase, DeviceTransportPhase.connected);

    // ...and the default still sweeps, so the flag is what suppressed it and
    // not something else about the second pass.
    await deviceData.setupConnection(device, forceRefresh: true);
    expect(session.writesFor(ccUUID).length, greaterThan(afterBootstrap));

    deviceData.dispose();
  });

  // The settings bootstrap must not gate FTMS control: a workout that starts
  // the instant a DIRCON session comes up has to reach the trainer even though
  // _dirConSetupComplete is still false.
  test('delivers target power while the settings bootstrap is still running', () async {
    final connector = FakeDirConConnector();
    final deviceData = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = _ipAddress;
    await deviceData.connectPreferred(device, waitForSetup: false);
    final session = connector.first;

    deviceData.setWorkoutTargetPower(250);

    final ftmsIndex = await _waitForWriteTo(session, ftmsControlPointUUID);
    final settingsBefore = _countWritesTo(session.writes.take(ftmsIndex), ccUUID);

    expect(
      session.writesFor(ftmsControlPointUUID).single,
      orderedEquals(FTMSControlPoint.targetPowerCommand(250)),
    );

    // Let the bootstrap finish, then prove the target really did land partway
    // through it rather than after it completed.
    await _waitUntil(() => session.writesFor(ccUUID).length > settingsBefore + 5);
    expect(
      settingsBefore,
      lessThan(session.writesFor(ccUUID).length),
      reason: 'settings writes were still streaming when the target was sent',
    );
    expect(deviceData.transportState.value.phase, DeviceTransportPhase.connected);

    deviceData.dispose();
  });

  // Regression for the connectPreferred fix: a bootstrap that fails over a link
  // that is physically up must not report the transport down.
  //
  // Note what this can and cannot pin. requestSettings catches every write
  // failure individually, so no exception currently escapes setupConnection —
  // the guard in connectPreferred is defensive. What is asserted here is the
  // outcome that guard exists to protect: a wholly failed bootstrap leaves the
  // live DIRCON session connected and usable for FTMS control.
  test('a failed settings bootstrap leaves the live transport connected', () async {
    final session = FakeDirConSession()..failWritesFor(ccUUID);
    final connector = FakeDirConConnector([session]);
    final deviceData = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = _ipAddress;

    await deviceData.connectPreferred(device, waitForSetup: true);

    expect(session.writesFor(ccUUID), isNotEmpty, reason: 'bootstrap was attempted');
    expect(deviceData.transportState.value.phase, DeviceTransportPhase.connected);
    expect(deviceData.transportState.value.transport, DeviceTransportKind.dircon);
    expect(deviceData.isDirConConnected, isTrue);

    // Still able to control the trainer despite the broken bootstrap.
    deviceData.setWorkoutTargetPower(180);
    await _waitForWriteTo(session, ftmsControlPointUUID);
    expect(
      session.writesFor(ftmsControlPointUUID).single,
      orderedEquals(FTMSControlPoint.targetPowerCommand(180)),
    );

    deviceData.dispose();
  });

  // Regression for the _closeDirCon fix: tearing down a live DIRCON session is
  // itself a transport transition, and must be reported as one.
  test('closing a live DIRCON session reports the transport down', () async {
    final connector = FakeDirConConnector();
    final deviceData = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = _ipAddress;
    await deviceData.connectPreferred(device, waitForSetup: true);
    final session = connector.first;

    expect(deviceData.isTransportActive, isTrue);
    expect(session.isListening(ccUUID), isTrue);
    final revisionBefore = deviceData.transportRevision.value;

    await deviceData.disconnectPreferred(device);

    expect(deviceData.isTransportActive, isFalse);
    expect(deviceData.isDirConConnected, isFalse);
    expect(deviceData.transportState.value.phase, DeviceTransportPhase.disconnected);
    expect(deviceData.transportState.value.transport, DeviceTransportKind.none);
    expect(deviceData.transportRevision.value, greaterThan(revisionBefore));
    expect(session.isClosed, isTrue);
    expect(session.isListening(ccUUID), isFalse);

    // A workout target must not be written into a torn-down session.
    deviceData.setWorkoutTargetPower(200);
    await _settle();
    expect(session.writesFor(ftmsControlPointUUID), isEmpty);

    deviceData.dispose();
  });

  test('a zero target sends target power then a zero-grade simulation reset', () async {
    final connector = FakeDirConConnector();
    final deviceData = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = _ipAddress;
    await deviceData.connectPreferred(device, waitForSetup: true);
    final session = connector.first;

    deviceData.setWorkoutTargetPower(0);
    await _waitUntil(() => session.writesFor(ftmsControlPointUUID).length >= 2);

    expect(session.writesFor(ftmsControlPointUUID), [
      orderedEquals(FTMSControlPoint.targetPowerCommand(0)),
      orderedEquals(
        FTMSControlPoint.indoorBikeSimulationCommand(
          windSpeed: 0,
          grade: 0,
          crr: 0,
          cw: 0,
        ),
      ),
    ]);

    deviceData.dispose();
  });
}

int _countWritesTo(Iterable<({String uuid, List<int> value})> writes, String uuid) {
  final key = uuid.toLowerCase();
  return writes.where((write) => write.uuid.toLowerCase() == key).length;
}

/// Returns the index of the first write to [uuid], waiting for it to arrive.
///
/// Workout commands share the serialized transport queue with the background
/// settings bootstrap, so the write cannot be asserted immediately or by a
/// fixed index.
Future<int> _waitForWriteTo(FakeDirConSession session, String uuid) async {
  final key = uuid.toLowerCase();
  await _waitUntil(
    () => session.writes.any((write) => write.uuid.toLowerCase() == key),
  );
  return session.writes.indexWhere((write) => write.uuid.toLowerCase() == key);
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));
