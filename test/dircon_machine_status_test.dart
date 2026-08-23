// FTMS Machine Status (0x2ADA) parity over DIRCON — plan §5.2 / §7.3.
//
// Every test drives DeviceData through the injected DirConSession seam, so the
// real transport-selection code runs without a socket.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/calibration_monitor.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';

import 'support/fake_dircon_session.dart';

const _machineStatusUuid = FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID;
const _ipAddress = '192.168.1.50';

void main() {
  // DeviceData reports write failures through Snackbar, which reads a
  // GlobalKey and therefore needs a binding even in a pure-logic test.
  TestWidgetsFlutterBinding.ensureInitialized();

  late BluetoothDevice device;

  setUp(() {
    device = BluetoothDevice.fromId('00:00:00:00:00:2A');
  });

  group('DIRCON FTMS subscription setup', () {
    // Machine Status is deliberately outside the FTMS subscription block: that
    // block throttles the high-rate Indoor Bike Data telemetry, and gating
    // homing status with it would blind calibration for the whole
    // post-connection window.
    test('subscribes Machine Status immediately while Indoor Bike Data waits '
        'for the post-connection block', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      expect(deviceData.isFtmsSubscriptionBlocked, isTrue);

      expect(session.enabledNotificationsFor(_machineStatusUuid), isTrue);
      expect(session.isListening(_machineStatusUuid), isTrue);

      // Discovered, but held back until the block lifts.
      expect(session.discovered(ftmsIndoorBikeDataUUID), isTrue);
      expect(session.enabledNotificationsFor(ftmsIndoorBikeDataUUID), isFalse);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);

      await deviceData.unblockFtmsSubscription(device);

      expect(session.enabledNotificationsFor(ftmsIndoorBikeDataUUID), isTrue);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isTrue);
      expect(session.isListening(_machineStatusUuid), isTrue);

      deviceData.dispose();
    });

    test('forwards a Machine Status payload to machineStatusStream', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final received = <List<int>>[];
      final subscription = deviceData.machineStatusStream.listen(received.add);

      connector.first.emitNotification(_machineStatusUuid, [
        FTMSStatusOpCodes.SPIN_DOWN_STATUS,
        FTMSSpinDownStatus.MAX_SEARCH_STARTED,
      ]);
      await _settle();

      expect(received, [
        [FTMSStatusOpCodes.SPIN_DOWN_STATUS, FTMSSpinDownStatus.MAX_SEARCH_STARTED],
      ]);

      await subscription.cancel();
      deviceData.dispose();
    });

    // The notification stream is a broadcast with no replay. If setup enabled
    // notifications before listening, a frame the device sent in that window
    // would be dropped on the floor.
    test('delivers a frame emitted while notifications are being enabled', () async {
      final session = FakeDirConSession()
        ..emitDuringEnable(_machineStatusUuid, [
          FTMSStatusOpCodes.SPIN_DOWN_STATUS,
          FTMSSpinDownStatus.SPIN_DOWN_REQUESTED,
        ]);
      final connector = FakeDirConConnector([session]);

      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = _ipAddress;
      final received = <List<int>>[];
      final subscription = deviceData.machineStatusStream.listen(received.add);

      await deviceData.connectPreferred(device, waitForSetup: true);
      await _settle();

      expect(received, [
        [FTMSStatusOpCodes.SPIN_DOWN_STATUS, FTMSSpinDownStatus.SPIN_DOWN_REQUESTED],
      ]);

      await subscription.cancel();
      deviceData.dispose();
    });
  });

  group('FTMS setup failures are isolated', () {
    test('missing Indoor Bike Data still leaves Machine Status subscribed', () async {
      final session = FakeDirConSession()
        ..failCharacteristic(ftmsIndoorBikeDataUUID);
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);

      expect(deviceData.isDirConConnected, isTrue);
      expect(session.isListening(_machineStatusUuid), isTrue);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);

      // Lifting the block must not resurrect a characteristic the firmware
      // does not have, and must not throw out of the timer that calls it.
      await deviceData.unblockFtmsSubscription(device);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);
      expect(session.isListening(_machineStatusUuid), isTrue);

      deviceData.dispose();
    });

    test('missing Machine Status still leaves Indoor Bike Data subscribed', () async {
      final session = FakeDirConSession()..failCharacteristic(_machineStatusUuid);
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);

      expect(deviceData.isDirConConnected, isTrue);
      // Cancelled rather than leaked: the helper listens first, then unwinds
      // its own subscription when discovery fails.
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.cancellationsFor(_machineStatusUuid), 1);

      // Indoor Bike Data is unaffected and still subscribes when unblocked.
      expect(session.discovered(ftmsIndoorBikeDataUUID), isTrue);
      await deviceData.unblockFtmsSubscription(device);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isTrue);

      deviceData.dispose();
    });

    test('firmware without either characteristic still connects for configuration', () async {
      final session = FakeDirConSession()
        ..failCharacteristic(ftmsIndoorBikeDataUUID)
        ..failCharacteristic(_machineStatusUuid);
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);
      final received = <List<int>>[];
      final subscription = deviceData.machineStatusStream.listen(received.add);

      expect(deviceData.isDirConConnected, isTrue);
      expect(deviceData.charReceived.value, isTrue);
      // Configuration traffic still flows; calibration falls back to the log.
      expect(session.writesFor(ccUUID), isNotEmpty);

      session.emitNotification(_machineStatusUuid, [
        FTMSStatusOpCodes.SPIN_DOWN_STATUS,
        FTMSSpinDownStatus.SUCCESS,
      ]);
      await _settle();
      expect(received, isEmpty);

      await subscription.cancel();
      deviceData.dispose();
    });
  });

  group('teardown cancels the Machine Status subscription', () {
    test('explicit disconnect', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      await deviceData.disconnectPreferred(device);

      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isClosed, isTrue);
      expect(deviceData.isTransportActive, isFalse);

      deviceData.dispose();
    });

    test('dispose', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      deviceData.dispose();
      await _settle();

      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isClosed, isTrue);
      // A frame that races disposal must not land on the closed controller.
      expect(
        () => session.emitNotification(_machineStatusUuid, [
          FTMSStatusOpCodes.SPIN_DOWN_STATUS,
          FTMSSpinDownStatus.SUCCESS,
        ]),
        returnsNormally,
      );
      await _settle();
    });

    // An unexpected drop runs _handleDirConDisconnect, which tears the session
    // down through _closeDirCon and then attempts the BLE half of the failover.
    // Only the teardown is asserted here: _connectBleAfterDirConLoss needs a
    // connected BLE device, and is covered by the Plan 1 fallback tests and by
    // hardware acceptance item 6.
    test('unexpected transport drop', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      session.dropConnection();
      await _settle();

      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);
      expect(deviceData.isDirConConnected, isFalse);

      deviceData.dispose();
    });

    test('reconnect tears down the old session and subscribes the new one', () async {
      final first = FakeDirConSession(host: _ipAddress);
      final second = FakeDirConSession(host: _ipAddress);
      final connector = FakeDirConConnector([first, second]);
      final deviceData = await _connect(connector, device);

      await deviceData.connectPreferred(device, waitForSetup: true);

      expect(connector.issued, hasLength(2));
      expect(first.isListening(_machineStatusUuid), isFalse);
      expect(first.isClosed, isTrue);
      expect(second.isListening(_machineStatusUuid), isTrue);
      expect(deviceData.isDirConConnected, isTrue);

      final received = <List<int>>[];
      final subscription = deviceData.machineStatusStream.listen(received.add);
      second.emitNotification(_machineStatusUuid, [
        FTMSStatusOpCodes.SPIN_DOWN_STATUS,
        FTMSSpinDownStatus.SUCCESS,
      ]);
      await _settle();
      expect(received, hasLength(1));

      await subscription.cancel();
      deviceData.dispose();
    });
  });

  test('calibration follows homing from DIRCON Machine Status', () async {
    final connector = FakeDirConConnector();
    final deviceData = await _connect(connector, device);
    final session = connector.first;
    final monitor = CalibrationMonitor(deviceData: deviceData, device: device);

    await monitor.start();

    // Log streaming is enabled over the custom characteristic first, so the
    // spin-down command is never the first write on the session.
    expect(
      session.writesFor(ftmsControlPointUUID),
      contains(orderedEquals(FTMSControlPoint.spinDownCommand(true))),
    );

    session.emitNotification(_machineStatusUuid, [
      FTMSStatusOpCodes.SPIN_DOWN_STATUS,
      FTMSSpinDownStatus.MAX_SEARCH_STARTED,
    ]);
    await _settle();

    expect(monitor.phase, CalibrationPhase.searchingMax);
    expect(monitor.minFound, isTrue);

    monitor.dispose();
    deviceData.dispose();
  });
}

Future<DeviceData> _connect(
  FakeDirConConnector connector,
  BluetoothDevice device,
) async {
  final deviceData = DeviceData(dirConConnector: connector.call)
    ..advertisedIpAddress = _ipAddress;
  await deviceData.connectPreferred(device, waitForSetup: true);
  expect(
    deviceData.transportState.value.transport,
    DeviceTransportKind.dircon,
    reason: 'fixture should have taken the DIRCON path',
  );
  return deviceData;
}

/// Lets broadcast-stream deliveries and pending teardown microtasks run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);
