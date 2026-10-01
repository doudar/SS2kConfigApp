import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

import 'support/fake_dircon_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BluetoothDevice device;
  late FakeDirConConnector connector;
  late DeviceData data;

  setUp(() {
    device = BluetoothDevice.fromId('00:00:00:00:00:94');
    connector = FakeDirConConnector([FakeDirConSession(), FakeDirConSession()]);
    data = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = '192.168.1.50';
  });
  tearDown(() => data.dispose());

  Future<void> connect() => data.connectPreferred(device, waitForSetup: true);

  test('ending an idle workout is silent across connections', () async {
    data.endWorkoutControl();
    await connect();
    final firstSession = connector.first;
    data.endWorkoutControl();
    await _settle();
    expect(firstSession.writesFor(ftmsControlPointUUID), isEmpty);

    await data.disconnectPreferred(device);
    await connect();
    await _settle();
    expect(connector.last.writesFor(ftmsControlPointUUID), isEmpty);
  });

  for (final watts in [250, 0]) {
    test(
      'ending a $watts W workout releases once without reconnect replay',
      () async {
        await connect();
        final session = connector.first;
        data.setWorkoutTargetPower(watts);
        await _waitUntil(
          () =>
              session.writesFor(ftmsControlPointUUID).length ==
              (watts == 0 ? 2 : 1),
        );
        final beforeStop = session.writesFor(ftmsControlPointUUID).length;

        data.endWorkoutControl();
        // A second stop/load must not cancel the first release while queued.
        data.endWorkoutControl();
        await _waitUntil(
          () => session.writesFor(ftmsControlPointUUID).length > beforeStop,
        );
        expect(session.writesFor(ftmsControlPointUUID).skip(beforeStop), [
          [0x11, 0, 0, 0, 0, 0, 0],
        ]);
        expect(data.ftmsData.targetERG, 0);

        await data.setupConnection(
          device,
          forceRefresh: true,
          sweepSettings: false,
        );
        await _settle();
        expect(
          session.writesFor(ftmsControlPointUUID),
          hasLength(beforeStop + 1),
        );

        await data.disconnectPreferred(device);
        await connect();
        await _settle();
        expect(connector.last.writesFor(ftmsControlPointUUID), isEmpty);
      },
    );
  }

  for (final startedOffline in [false, true]) {
    test(
      'ending ${startedOffline ? 'an offline' : 'a disconnected'} workout cannot replay control',
      () async {
        if (!startedOffline) await connect();
        data.setWorkoutTargetPower(250);
        if (!startedOffline) {
          await _waitUntil(
            () => connector.first.writesFor(ftmsControlPointUUID).isNotEmpty,
          );
          await data.disconnectPreferred(device);
        }

        data.endWorkoutControl();
        await connect();
        await _settle();
        expect(connector.last.writesFor(ftmsControlPointUUID), isEmpty);
      },
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('workout control write did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
