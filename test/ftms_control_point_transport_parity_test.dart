// Plan §7.2: BLE and DIRCON must receive identical encoded target commands.
//
// This file installs a fake FlutterBluePlusPlatform so a real
// BluetoothCharacteristic.write() runs through DeviceData's actual transport
// selector. FlutterBluePlus subscribes to the platform event streams exactly
// once per isolate and never unsubscribes, so these tests must stay in their
// own file — restoring the previous instance in tearDown does not undo those
// subscriptions.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_connection_retry.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/calibration_monitor.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';

import 'support/fake_ble_platform.dart';
import 'support/fake_dircon_session.dart';

const _targetWatts = 250;
final _indoorBikeUuid = ftmsIndoorBikeDataUUID;
const _machineStatusUuid = FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Installed before anything can touch FlutterBluePlus, so its one-time
  // initialization binds to this fake rather than to a real platform.
  final blePlatform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = blePlatform;

  test('BLE and DIRCON deliver byte-identical target power commands', () async {
    final expected = FTMSControlPoint.targetPowerCommand(_targetWatts);

    final dirConBytes = await _sendOverDirCon(_targetWatts);
    final bleBytes = await _sendOverBle(blePlatform, _targetWatts);

    expect(bleBytes, orderedEquals(dirConBytes));
    expect(dirConBytes, orderedEquals(expected));
    expect(bleBytes, orderedEquals(expected));
  });

  // The DIRCON half of this lifecycle lives in dircon_machine_status_test.dart.
  // BLE needs a real BluetoothCharacteristic, which only works against the
  // platform fake installed above, so its assertions have to live here.
  group('BLE FTMS notification block', () {
    test('blocks and releases both characteristics together', () async {
      final harness = await BleHarness.connect(blePlatform);

      // The post-connection block is already held: nothing enabled yet.
      expect(harness.deviceData.isFtmsNotificationsBlocked, isTrue);
      expect(blePlatform.notifyCalls, isEmpty);

      await harness.deviceData.unblockFtmsNotifications(harness.device);

      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);
      expect(blePlatform.enabledNow(_machineStatusUuid), isTrue);

      blePlatform.notifyCalls.clear();
      await harness.deviceData.blockFtmsNotifications();

      // Both disabled on the wire, not merely unsubscribed locally.
      expect(blePlatform.enabledNow(_indoorBikeUuid), isFalse);
      expect(blePlatform.enabledNow(_machineStatusUuid), isFalse);

      harness.dispose();
    });

    // The BLE mirror of the DIRCON stale-enable race: a block taken while
    // setNotifyValue(true) is in flight would otherwise leave the
    // characteristic notifying with nothing listening.
    test('an enable superseded by a new block undoes itself', () async {
      final harness = await BleHarness.connect(blePlatform);

      blePlatform.holdNotifyGate(_machineStatusUuid);
      final unblock = harness.deviceData.unblockFtmsNotifications(
        harness.device,
      );
      await _settle();

      final block = harness.deviceData.blockFtmsNotifications();
      await _settle();
      blePlatform.releaseNotifyGate(_machineStatusUuid);
      await unblock;
      await block;

      // The enable did happen — this is an undo, not a never-ran. Without the
      // assertion the test would pass just as well if nothing had been called.
      expect(
        blePlatform.notifyCalls.where(
          (call) => call.uuid == Guid(_machineStatusUuid).str.toLowerCase(),
        ),
        containsAll([
          (uuid: Guid(_machineStatusUuid).str.toLowerCase(), enable: true),
          (uuid: Guid(_machineStatusUuid).str.toLowerCase(), enable: false),
        ]),
      );
      expect(blePlatform.enabledNow(_machineStatusUuid), isFalse);

      harness.dispose();
    });

    test('a missing Machine Status characteristic does not stop Indoor Bike Data', () async {
      final harness = await BleHarness.connect(
        blePlatform,
        withMachineStatus: false,
      );

      await harness.deviceData.unblockFtmsNotifications(harness.device);

      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);
      expect(blePlatform.enabledNow(_machineStatusUuid), isFalse);

      harness.dispose();
    });
  });

  group('FTMS notification setup is single-flight', () {
    // Four screens call ensureFtmsNotifications unawaited from initState, and
    // the health watchdog and the readiness wait drive it too, so two passes
    // can genuinely overlap. Each pass cancels the subscription it was *handed*
    // and then publishes its own: overlapping passes both create a listener and
    // only the last is published, leaving the other delivering frames with
    // nothing able to cancel it.
    test('two overlapping passes leave exactly one Indoor Bike listener', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      final decoded = <FtmsData>[];
      final subscription = harness.deviceData.ftmsDataChanges.listen(
        decoded.add,
      );

      // The gate goes on Indoor Bike Data, the *first* characteristic each pass
      // touches, not on Machine Status. _queueBleOperation is a serial queue:
      // parking it on the second characteristic would push the second pass's
      // Indoor Bike step behind the first pass's publish, so the second pass
      // would be handed the first's subscription to cancel and the leak could
      // never form. Gating the first lets both passes create their listener
      // before either reaches the queue — which is where the leak comes from.
      blePlatform.holdNotifyGate(_indoorBikeUuid);
      final first = harness.deviceData.ensureFtmsNotifications(harness.device);
      final second = harness.deviceData.ensureFtmsNotifications(harness.device);
      await waitUntil(
        () => blePlatform.notifyGateWaiters(_indoorBikeUuid) >= 1,
      );
      await _settle();
      blePlatform.releaseNotifyGate(_indoorBikeUuid);
      await first;
      await second;

      blePlatform.emitNotification(
        harness.device.remoteId,
        _indoorBikeUuid,
        _indoorBikeFrame,
      );
      await _settle();

      // One listener, so one decode. Two means the superseded pass is still
      // attached; zero means the frame never matched the characteristic's
      // filters and this test proves nothing.
      expect(decoded, hasLength(1));

      await subscription.cancel();
      harness.dispose();
    });

    // _machineStatusNotificationsLive is the single field
    // awaitFtmsNotificationsReady answers from, and calibration gates on it.
    // A pass that finds no characteristic has to clear it, or calibration is
    // told the stream is ready with no listener behind it.
    test('a Machine Status characteristic that goes missing clears readiness', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      expect(
        await harness.deviceData.awaitFtmsNotificationsReady(
          harness.device,
          timeout: const Duration(seconds: 1),
        ),
        FtmsNotificationsReadiness.ready,
      );

      // Firmware refreshed, or discovery no longer finds 0x2ADA. Indoor Bike
      // Data stays assigned so the pass still has work to do. Discovery has to
      // stop reporting it too: a null characteristic buys one forced re-probe,
      // and a fixture that still advertised 0x2ADA would simply get it back.
      blePlatform.discoveryIncludesMachineStatus = false;
      harness.deviceData.machineStatusCharacteristic = null;
      await harness.deviceData.ensureFtmsNotifications(harness.device);

      expect(
        await harness.deviceData.awaitFtmsNotificationsReady(
          harness.device,
          timeout: const Duration(seconds: 1),
        ),
        FtmsNotificationsReadiness.unavailable,
      );

      harness.dispose();
    });
  });

  // The 2026-08-25 session's actual failure: Wi-Fi died, the app fell back to
  // BLE, and calibration then sat at "Start pedaling to begin" forever. The
  // fallback ran `setupConnection` while the transport was still `connecting`,
  // so the FTMS setup inside it bailed on `!isTransportActive` — and the
  // settings-bootstrap unblock then released every readiness waiter anyway,
  // handing calibration an `unavailable` for a pass that never ran.
  //
  // Exercised end to end rather than by unit: the bug lived entirely in the
  // ordering between three collaborators, and each of them was individually
  // correct.
  group('DIRCON to BLE fallback', () {
    test('re-establishes both FTMS subscriptions and dispatches over BLE', () async {
      await FlutterBluePlus.isSupported;
      blePlatform.reset();

      final connector = FakeDirConConnector();
      final device = BluetoothDevice.fromId('00:00:00:00:00:F1');
      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = '192.168.1.50';

      // The GATT link is up in parallel with DIRCON for the whole session —
      // that is what makes the fallback a *promotion* of an existing session
      // rather than a fresh connect, and what makes the ten-second settle
      // window pure dead time.
      blePlatform.markConnected(device.remoteId);
      await deviceData.connectPreferred(device, waitForSetup: true);
      expect(
        deviceData.transportState.value.transport,
        DeviceTransportKind.dircon,
      );

      // Wi-Fi dies. The firmware sees no FIN/RST; the app sees the socket go.
      connector.first.dropConnection();

      await waitUntil(
        () =>
            deviceData.transportState.value.transport ==
                DeviceTransportKind.bluetooth &&
            deviceData.transportState.value.phase ==
                DeviceTransportPhase.connected,
      );

      // Both, not just Indoor Bike Data: 0x2ADA is calibration's only evidence
      // channel, and it was never enabled over BLE in the captured session.
      await waitUntil(() => blePlatform.enabledNow(_machineStatusUuid));
      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);

      expect(
        await deviceData.awaitFtmsNotificationsReady(
          device,
          timeout: const Duration(seconds: 2),
        ),
        FtmsNotificationsReadiness.ready,
      );

      // And the command actually reaches the BLE control point.
      blePlatform.writes.clear();
      await deviceData.writeFtmsControlPointCommand(
        FTMSControlPoint.spinDownCommand(true),
      );
      expect(blePlatform.writes.single, FTMSControlPoint.spinDownCommand(true));

      deviceData.dispose();
    });

    // Reconnect callbacks refresh UI and re-read RSSI. Restoring the transport
    // is the transaction; none of that is part of it. An unisolated throw used
    // to skip every sibling callback and, on the auto-reconnect path, report a
    // successfully restored link as a failed attempt.
    test('a throwing reconnect callback does not abort its siblings', () async {
      await FlutterBluePlus.isSupported;
      blePlatform.reset();

      final connector = FakeDirConConnector();
      final device = BluetoothDevice.fromId('00:00:00:00:00:F5');
      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = '192.168.1.50';

      var secondRan = false;
      deviceData.startConnectionMonitor(
        device,
        onReconnected: () async => throw StateError('readRssi failed'),
      );
      deviceData.startConnectionMonitor(
        device,
        onReconnected: () async => secondRan = true,
      );

      blePlatform.markConnected(device.remoteId);
      await deviceData.connectPreferred(device, waitForSetup: true);
      connector.first.dropConnection();

      await waitUntil(() => secondRan);
      expect(
        deviceData.transportState.value.phase,
        DeviceTransportPhase.connected,
      );

      deviceData.stopConnectionMonitor();
      deviceData.dispose();
    });

    // The 2026-08-25 failure end to end: the fallback ran, the post-fallback
    // settings sweep found a response-silent device, and a calibration started
    // immediately afterwards — *while the sweep was still mid-read*. The sweep
    // must yield to the calibration lease and release the FTMS block on the way
    // out, so the run is not deaf to its own acknowledgement, and the verdict
    // must never be the false "did not respond".
    //
    // Determinism hinges on ordering: `answerCustomRequests` goes false *before*
    // the DIRCON drop, so the sweep is provably still in flight (block held, a
    // `[0x01]` read on the wire, no answer coming) when `monitor.start()` takes
    // the lease. Because the run starts during the sweep's *first* unanswered
    // read — one strike, breaker still closed — the sweep exits via
    // `settings sweep yielded`, not `abandoned`.
    test('a calibration right after a response-silent fallback is not blinded', () async {
      await FlutterBluePlus.isSupported;
      blePlatform.reset();

      final connector = FakeDirConConnector();
      final device = BluetoothDevice.fromId('00:00:00:00:00:F7');
      late final DeviceData deviceData;

      // The whole body runs under print capture: the fallback fires from a
      // DIRCON disconnect listener registered during `connectPreferred`, so the
      // `[transport] settings sweep …` lines are only in this zone if the
      // `.listen()` happened here too.
      final transportLog = <String>[];
      await withPrintCapture(transportLog, () async {
        deviceData = DeviceData(dirConConnector: connector.call)
          ..advertisedIpAddress = '192.168.1.50';

        blePlatform.markConnected(device.remoteId);
        await deviceData.connectPreferred(device, waitForSetup: true);

        // Response-silent from here on. The fallback's own `setupConnection`
        // runs with `sweepSettings: false`, so it needs no custom responses;
        // only the background sweep it launches at the end does.
        blePlatform.answerCustomRequests = false;
        blePlatform.writes.clear();

        connector.first.dropConnection();
        await waitUntil(
          () =>
              deviceData.transportState.value.transport ==
                  DeviceTransportKind.bluetooth &&
              deviceData.transportState.value.phase ==
                  DeviceTransportPhase.connected,
        );

        // The post-fallback sweep is genuinely in flight: it took the FTMS
        // block — so Machine Status is *down* — and a `[0x01]` read is on the
        // wire with no answer coming. This is the state the captured session
        // hit, and the run must start from here. (Waiting for Machine Status to
        // come up first, as the pre-rewrite test did, would wait out the whole
        // sweep and defeat the point.)
        await waitUntil(
          () =>
              deviceData.isFtmsNotificationsBlocked &&
              blePlatform.writes.any((w) => w.length >= 2 && w[0] == 0x01),
        );

        final monitor = CalibrationMonitor(
          deviceData: deviceData,
          device: device,
          notificationsReadyTimeout: const Duration(seconds: 10),
        );
        await monitor.start();

        // The sweep did not hold the FTMS block hostage through the run...
        await waitUntil(() => !deviceData.isFtmsNotificationsBlocked);
        expect(monitor.phase, isNot(CalibrationPhase.failedToStart));
        expect(
          monitor.notificationsReadiness,
          FtmsNotificationsReadiness.ready,
          reason: 'Machine Status was re-enabled over BLE by the fallback',
        );
        // ...and the spin-down reached the BLE control point.
        final spinDown = FTMSControlPoint.spinDownCommand(true);
        expect(
          blePlatform.writes.any(
            (w) =>
                w.length == spinDown.length &&
                w[0] == spinDown[0] &&
                w[1] == spinDown[1],
          ),
          isTrue,
        );

        // A Machine Status frame then acknowledges the run — the evidence
        // channel the captured session never had.
        blePlatform.emitNotification(
          device.remoteId,
          _machineStatusUuid,
          const [0x14, 0x01],
        );
        await waitUntil(() => monitor.acknowledged);

        monitor.dispose();
      });

      // The run started during the first unanswered read, so the sweep yielded
      // to the lease rather than grinding to the breaker. Diagnostic
      // confirmation of the path, per the plan — its absence is how the
      // pre-rewrite test slipped through.
      expect(
        transportLog.where((l) => l.contains('settings sweep yielded')),
        isNotEmpty,
        reason: 'expected the loop-level yield, not "abandoned"',
      );

      deviceData.dispose();
    });

    // The other fallback shape: DIRCON was never paralleled by a live GATT
    // link, so the fallback opens a *fresh* connection and `_markTransport
    // Connected` is reached with `settle: true` — a 10 s post-connection quiet
    // window during which the FTMS streams are held down. A calibration started
    // in that window must not wait the window out: taking the interactive lease
    // ends the settle block early (beginInteractiveFtmsSession ->
    // _endFtmsPostConnectionBlock). This is the only test that exercises the
    // `settle: true` branch.
    test('a calibration during a fresh-GATT fallbacks settle window is not stalled', () async {
      await FlutterBluePlus.isSupported;
      blePlatform.reset();

      final connector = FakeDirConConnector();
      final device = BluetoothDevice.fromId('00:00:00:00:00:F9');
      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = '192.168.1.50';

      // No markConnected: connectPreferred reaches DIRCON without a BLE GATT
      // session, so device.isConnected is false at fallback time and
      // _connectBleAfterDirConLoss connects fresh with settle: true.
      await deviceData.connectPreferred(device, waitForSetup: true);
      expect(
        deviceData.transportState.value.transport,
        DeviceTransportKind.dircon,
      );

      connector.first.dropConnection();
      await waitUntil(
        () =>
            deviceData.transportState.value.transport ==
                DeviceTransportKind.bluetooth &&
            deviceData.transportState.value.phase ==
                DeviceTransportPhase.connected,
      );

      // A real GATT connect happened — exactly one, not a promotion of an
      // existing session.
      expect(
        blePlatform.connectCalls.where((c) => c.remoteId == device.remoteId),
        hasLength(1),
      );
      // The settle block is up: nothing FTMS is on the wire yet.
      expect(deviceData.isFtmsNotificationsBlocked, isTrue);

      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: device,
        // Well under the 10 s settle window: if the lease did not end it early,
        // readiness would stall past this and the run would not be `ready`.
        notificationsReadyTimeout: const Duration(seconds: 3),
      );
      await monitor.start();

      expect(monitor.phase, isNot(CalibrationPhase.failedToStart));
      expect(
        monitor.notificationsReadiness,
        FtmsNotificationsReadiness.ready,
        reason: 'the lease should have ended the settle block early',
      );
      expect(deviceData.isFtmsNotificationsBlocked, isFalse);
      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);
      expect(blePlatform.enabledNow(_machineStatusUuid), isTrue);

      final spinDown = FTMSControlPoint.spinDownCommand(true);
      expect(
        blePlatform.writes.any(
          (w) =>
              w.length == spinDown.length &&
              w[0] == spinDown[0] &&
              w[1] == spinDown[1],
        ),
        isTrue,
      );

      monitor.dispose();
      deviceData.dispose();
    });
  });

  // A6 proper. The captured session never enabled 0x2ADA over BLE at any point,
  // and the cause could not be localized from the log — because discovery
  // treats Indoor Bike Data as proof it ran, so a Machine Status that goes
  // missing once stays missing for the life of the connection.
  group('FTMS discovery capabilities', () {
    test('a discovered connection subscribes Machine Status', () async {
      final harness = await BleHarness.connectViaDiscovery(blePlatform);

      expect(harness.deviceData.machineStatusCharacteristic, isNotNull);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);
      expect(blePlatform.enabledNow(_machineStatusUuid), isTrue);

      harness.dispose();
    });

    test('a missed Machine Status is re-probed exactly once per epoch', () async {
      // Discovery reports no 0x2ADA. On real firmware that is either a device
      // without Machine Status or a pass that missed it, and the app cannot
      // tell which without asking again.
      final harness = await BleHarness.connectViaDiscovery(
        blePlatform,
        withMachineStatus: false,
      );
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      final afterFirstPass = blePlatform.discoveryCount;

      // Every later pass on this epoch must believe the recorded answer rather
      // than re-running service discovery — otherwise firmware that genuinely
      // has no Machine Status re-discovers forever.
      for (var i = 0; i < 3; i++) {
        await harness.deviceData.ensureFtmsNotifications(harness.device);
      }

      expect(harness.deviceData.machineStatusCharacteristic, isNull);
      expect(blePlatform.discoveryCount, afterFirstPass);
      expect(blePlatform.enabledNow(_machineStatusUuid), isFalse);
      // ...and the one thing that must not happen: Indoor Bike Data going down
      // with it.
      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);

      harness.dispose();
    });

    // Run D. The characteristic is present, so the missing-Machine-Status
    // branch never fires; what is stale is the *platform's* service list, and
    // the enable comes back `primary service not found '1826'`. Before this the
    // app logged that and gave up, leaving 0x2ADA down for the connection.
    test('a stale service cache on enable is repaired by one re-probe', () async {
      final harness = await BleHarness.connectViaDiscovery(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);
      expect(blePlatform.enabledNow(_machineStatusUuid), isTrue);

      // Model a reconnect that left CoreBluetooth's service list without 0x1826
      // while DeviceData still holds characteristics found in it.
      await harness.deviceData.blockFtmsNotifications();
      blePlatform.failNotifyAsStaleService(_machineStatusUuid);
      final beforeRecovery = blePlatform.discoveryCount;
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      expect(
        blePlatform.discoveryCount,
        beforeRecovery + 1,
        reason: 'the failed enable should have forced exactly one re-probe',
      );
      expect(blePlatform.enabledNow(_machineStatusUuid), isTrue);
      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);

      harness.dispose();
    });

    // The budget is shared with the missing-characteristic re-probe on purpose:
    // both ask the same question of the same connection, and a device that
    // keeps failing the enable must not be able to drive discovery in a loop.
    test('a stale-cache re-probe is budgeted once per epoch', () async {
      final harness = await BleHarness.connectViaDiscovery(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      blePlatform.failNotifyAsStaleService(
        _machineStatusUuid,
        permanent: true,
      );
      await harness.deviceData.blockFtmsNotifications();
      await harness.deviceData.unblockFtmsNotifications(harness.device);
      final afterFirstRecovery = blePlatform.discoveryCount;

      for (var i = 0; i < 3; i++) {
        await harness.deviceData.ensureFtmsNotifications(harness.device);
      }

      expect(blePlatform.discoveryCount, afterFirstRecovery);
      // Not asserted on the wire: a stale cache fails the *disable* too, so the
      // fake's last-known state is stale in the same way the platform's is. The
      // app's own answer is the one that matters, and it must not claim a
      // stream it could not enable.
      expect(
        await harness.deviceData.awaitFtmsNotificationsReady(
          harness.device,
          timeout: const Duration(milliseconds: 200),
        ),
        FtmsNotificationsReadiness.unavailable,
      );
      expect(blePlatform.discoveryCount, afterFirstRecovery);
      // The failure is scoped to one characteristic and must stay that way.
      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);

      harness.dispose();
    });

    // The acknowledgement channel Run C was missing. This firmware notifies the
    // control point unconditionally on a write, while 0x2ADA is suppressed when
    // the status value did not change.
    test('a discovered connection subscribes the FTMS Control Point', () async {
      final harness = await BleHarness.connectViaDiscovery(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      expect(
        blePlatform.enabledNow(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
        isTrue,
      );
      expect(harness.deviceData.controlPointNotificationsLive, isTrue);

      final frames = <List<int>>[];
      final subscription = harness.deviceData.controlPointResponseStream.listen(
        frames.add,
      );
      addTearDown(subscription.cancel);

      blePlatform.emitNotification(
        harness.device.remoteId,
        FTMS_CONTROL_POINT_CHARACTERISTIC_UUID,
        const [0x80, 0x13, 0x01, 0x20, 0x03, 0x60, 0x09],
      );
      await waitUntil(() => frames.isNotEmpty);
      expect(frames.single, const [0x80, 0x13, 0x01, 0x20, 0x03, 0x60, 0x09]);

      harness.dispose();
    });

    // The control point rides the same block as the other two: a stream that is
    // live while the transport is meant to be quiet is the thing the block
    // exists to prevent, whatever it carries.
    test('the FTMS block covers the control point', () async {
      final harness = await BleHarness.connectViaDiscovery(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);
      expect(
        blePlatform.enabledNow(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
        isTrue,
      );

      await harness.deviceData.blockFtmsNotifications();
      expect(
        blePlatform.enabledNow(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
        isFalse,
      );
      expect(harness.deviceData.controlPointNotificationsLive, isFalse);

      await harness.deviceData.unblockFtmsNotifications(harness.device);
      expect(
        blePlatform.enabledNow(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
        isTrue,
      );
      expect(harness.deviceData.controlPointNotificationsLive, isTrue);

      harness.dispose();
    });
  });

  // The watchdog used to write the CCCD on Indoor Bike Data directly: it
  // repaired the wire and never republished the Dart listener, so a stream
  // whose subscription had been cancelled came back enabled with nobody
  // reading it. Machine Status it never touched at all.
  group('FTMS health watchdog', () {
    test('recovery restores data delivery and Machine Status together', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      final decoded = <FtmsData>[];
      final subscription = harness.deviceData.ftmsDataChanges.listen(
        decoded.add,
      );

      // A stalled stream: notifications were enabled long ago and nothing has
      // arrived since.
      harness.deviceData.lastFtmsUpdate = DateTime.now().subtract(
        const Duration(minutes: 1),
      );
      await harness.deviceData.checkFtmsHealth(harness.device);

      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);
      expect(blePlatform.enabledNow(_machineStatusUuid), isTrue);

      // The point of the fix: a listener is actually attached afterwards.
      blePlatform.emitNotification(
        harness.device.remoteId,
        _indoorBikeUuid,
        _indoorBikeFrame,
      );
      await _settle();
      expect(decoded, hasLength(1));

      await subscription.cancel();
      harness.dispose();
    });

    test('a failed recovery does not report itself as recovered', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      final stalledAt = DateTime.now().subtract(const Duration(minutes: 1));
      harness.deviceData.lastFtmsUpdate = stalledAt;

      // The re-enable never lands. Resetting lastFtmsUpdate here would claim a
      // recovery that did not happen and push the next attempt out by a whole
      // watchdog period; the cooldown is what prevents a tight loop.
      blePlatform.holdNotifyGate(_indoorBikeUuid);
      final recovery = harness.deviceData.checkFtmsHealth(harness.device);
      await _settle();

      expect(harness.deviceData.lastFtmsUpdate, stalledAt);

      blePlatform.releaseNotifyGate(_indoorBikeUuid);
      await recovery;
      harness.dispose();
    });

    // The watchdog's other branch, and the one Run C exposed. `lastFtmsUpdate`
    // stays null forever on a connection that never delivered a frame, so the
    // stalled branch above is unreachable and this is the only recovery there
    // is — yet it called `ensureFtmsNotifications`, which is a no-op once
    // `isNotifying` is true. In Run C it ran four times, logged
    // `already notifying, no CCCD write` each time, and repaired nothing.
    test('a connection that never delivered a frame is recycled, not re-ensured', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      // Subscribed on both ends, and not one frame has arrived: exactly the
      // state the old branch could not tell from a healthy one.
      expect(blePlatform.enabledNow(_indoorBikeUuid), isTrue);
      expect(harness.deviceData.lastFtmsUpdate, isNull);

      blePlatform.notifyCalls.clear();
      await harness.deviceData.checkFtmsHealth(harness.device);

      for (final uuid in [_indoorBikeUuid, _machineStatusUuid]) {
        // The fake records what the platform channel sees, which for a
        // standard 16-bit UUID is the short form.
        final key = Guid(uuid).str.toLowerCase();
        expect(
          blePlatform.notifyCalls
              .where((call) => call.uuid.toLowerCase() == key)
              .map((call) => call.enable),
          containsAllInOrder([false, true]),
          reason: '$uuid was not cycled off and back on',
        );
        expect(blePlatform.enabledNow(uuid), isTrue, reason: uuid);
      }

      harness.dispose();
    });

    // Nothing to cycle before discovery has produced the characteristics, and
    // an ensure pass is what runs discovery in the first place. Recycling here
    // would disable nothing and then do the same work anyway.
    test('with no characteristic yet the branch still drives discovery', () async {
      final harness = await BleHarness.connectViaDiscovery(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      harness.deviceData.indoorBikeCharacteristic = null;
      harness.deviceData.machineStatusCharacteristic = null;
      blePlatform.notifyCalls.clear();

      await harness.deviceData.checkFtmsHealth(harness.device);

      expect(harness.deviceData.indoorBikeCharacteristic, isNotNull);
      expect(
        blePlatform.notifyCalls.map((call) => call.enable),
        isNot(contains(false)),
        reason: 'nothing was subscribed, so nothing should have been disabled',
      );

      harness.dispose();
    });
  });

  // The starvation case: the spin-down used to queue behind a forty-entry
  // settings sweep, each entry costing a full response timeout against a
  // device that had stopped answering.
  group('transport scheduler', () {
    test('a control command overtakes queued background work', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);
      harness.deviceData.ftmsControlPointCharacteristic =
          BluetoothCharacteristic(
            remoteId: harness.device.remoteId,
            serviceUuid: Guid(ftmsServiceUUID),
            characteristicUuid: Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
          );

      // The device accepts writes and never answers them, so every request
      // holds the queue for the full response timeout.
      blePlatform.answerCustomRequests = false;
      blePlatform.writes.clear();

      // Background requests queued first. Three is enough: the first occupies
      // the queue immediately, so strict arrival order would put the control
      // command behind all three.
      // Each unanswered write now surfaces TransportResponseUnconfirmed; this
      // test is about queue ordering, not the outcome, so absorb it.
      final sweep = [
        for (var reference = 1; reference <= 3; reference++)
          harness.deviceData.writeCustomCharacteristic(harness.device, [
            0x01,
            reference,
          ]).catchError((Object _) {}),
      ];
      await _settle();

      // ...then the command the user is waiting on.
      await harness.deviceData.writeFtmsControlPointCommand(
        FTMSControlPoint.spinDownCommand(true),
      );

      // It went out while most of the sweep was still queued behind it. Under
      // strict arrival order it would have been last.
      final spinDown = FTMSControlPoint.spinDownCommand(true);
      final index = blePlatform.writes.indexWhere(
        (w) => w.length == spinDown.length && w[0] == spinDown[0],
      );
      expect(index, isNonNegative);
      expect(
        index,
        lessThan(sweep.length),
        reason: 'control work must not wait for the whole background sweep',
      );

      await Future.wait(sweep);
      harness.dispose();
    });

    test('a failing operation does not stop the pump', () async {
      final harness = await BleHarness.connect(blePlatform);

      final failed = harness.deviceData.writeCustomCharacteristic(
        harness.device,
        [0x01, 1],
      );
      final after = harness.deviceData.writeCustomCharacteristic(
        harness.device,
        [0x01, 2],
      );

      // Whatever the first does, the second still runs to completion.
      await failed.catchError((Object _) {});
      await after;

      harness.dispose();
    });
  });

  group('custom response circuit breaker', () {
    test('trips after repeated silence and clears on the next answer', () async {
      final harness = await BleHarness.connect(blePlatform);
      final deviceData = harness.deviceData;

      expect(deviceData.customResponsesDegraded.value, isFalse);

      blePlatform.answerCustomRequests = false;
      for (var reference = 1; reference <= 3; reference++) {
        await expectLater(
          deviceData.writeCustomCharacteristic(harness.device, [
            0x01,
            reference,
          ]),
          throwsA(isA<TransportResponseUnconfirmed>()),
        );
      }

      expect(deviceData.customResponsesDegraded.value, isTrue);

      // The exempt heartbeat is what proves recovery: a single answered
      // request clears the breaker, so the degraded state cannot lock itself in.
      blePlatform.answerCustomRequests = true;
      await deviceData.writeCustomCharacteristic(harness.device, [0x01, 4]);
      await _settle();

      expect(deviceData.customResponsesDegraded.value, isFalse);

      harness.dispose();
    });

    test('a degraded link abandons the sweep and still releases its block', () async {
      final harness = await BleHarness.connect(blePlatform);
      final deviceData = harness.deviceData;
      await deviceData.unblockFtmsNotifications(harness.device);

      blePlatform.answerCustomRequests = false;
      for (var reference = 1; reference <= 3; reference++) {
        await expectLater(
          deviceData.writeCustomCharacteristic(harness.device, [
            0x01,
            reference,
          ]),
          throwsA(isA<TransportResponseUnconfirmed>()),
        );
      }
      expect(deviceData.customResponsesDegraded.value, isTrue);

      blePlatform.writes.clear();
      await deviceData.requestSettings(harness.device);

      // Abandoned rather than grinding through every entry...
      expect(blePlatform.writes, isEmpty);
      // ...and the FTMS block it took is released, which is what lets
      // calibration get its notifications back.
      expect(deviceData.isFtmsNotificationsBlocked, isFalse);

      harness.dispose();
    });

    // The loop-level yield in requestSettings: a calibration lease taken while
    // a sweep is already mid-read. The sweep must break before its next read
    // and release the FTMS block on the way out, so the run is not blinded on
    // Machine Status; the abandoned remainder runs when the last lease is
    // released. The DIRCON sibling could not host this — FakeDirConSession's
    // write is synchronous, so a whole sweep completes before a poll observes
    // its first write. The BLE write gate parks the sweep provably mid-read.
    test('a lease taken mid-sweep abandons the remaining reads and frees the block', () async {
      final harness = await BleHarness.connect(blePlatform);
      final deviceData = harness.deviceData;
      await deviceData.unblockFtmsNotifications(harness.device);

      bool isRead(List<int> w) => w.length >= 2 && w[0] == 0x01;

      blePlatform.holdWriteGate(ccUUID);
      blePlatform.writes.clear();

      final sweep = deviceData.requestSettings(harness.device);

      // The sweep took the block and is parked on its first read at the wire.
      await waitUntil(() => blePlatform.writeGateWaiters(ccUUID) == 1);
      expect(deviceData.isFtmsNotificationsBlocked, isTrue);
      expect(
        blePlatform.writes.where(isRead),
        isEmpty,
        reason: 'the read is parked before it reaches the wire',
      );

      final token = deviceData.beginInteractiveFtmsSession(harness.device);

      blePlatform.releaseWriteGate(ccUUID);
      await sweep;

      // Exactly the one read that was already in flight — the loop broke
      // before issuing a second.
      expect(blePlatform.writes.where(isRead), hasLength(1));
      await waitUntil(() => !deviceData.isFtmsNotificationsBlocked);
      await waitUntil(() => blePlatform.enabledNow(_machineStatusUuid));

      // Releasing the last lease runs the deferred remainder against the same
      // device.
      final afterYield = blePlatform.writes.where(isRead).length;
      deviceData.endInteractiveFtmsSession(token);
      await waitUntil(
        () => blePlatform.writes.where(isRead).length > afterYield,
      );

      harness.dispose();
    });
  });

  group('strict vs. tolerant custom writes', () {
    // The low-level write must surface an unconfirmed response, and the legacy
    // writeToSS2k wrapper must be the only thing that swallows it.
    test('writeToSS2kStrict throws where writeToSS2k absorbs', () async {
      final harness = await BleHarness.connect(blePlatform);
      final deviceData = harness.deviceData;
      final logChar = deviceData.customCharacteristic.firstWhere(
        (c) => c['vName'] == BLE_logStreamVname,
      );

      blePlatform.answerCustomRequests = false;

      await expectLater(
        deviceData.writeToSS2kStrict(harness.device, logChar, s: '1'),
        throwsA(isA<TransportResponseUnconfirmed>()),
      );

      // The tolerant wrapper turns the same fault into a snackbar and returns.
      await expectLater(
        deviceData.writeToSS2k(harness.device, logChar, s: '1'),
        completes,
      );

      harness.dispose();
    });

    // The powerTableData branch writes one packet per row and now `return`s
    // after the loop. An unconfirmed first row must abort the whole upload —
    // a half-written power table was never a good outcome — and no trailing
    // header-only [0x02, reference] packet may follow.
    test('a power-table upload stops on the first unconfirmed row', () async {
      final harness = await BleHarness.connect(blePlatform);
      final deviceData = harness.deviceData;
      final powerTable = deviceData.customCharacteristic.firstWhere(
        (c) => c['vName'] == powerTableDataVname,
      );

      blePlatform.answerCustomRequests = false;
      blePlatform.writes.clear();

      // `s` is ignored by the powerTableData branch but must be non-null to
      // clear the "use the saved value" guard at the top of the method.
      await expectLater(
        deviceData.writeToSS2kStrict(harness.device, powerTable, s: '1'),
        throwsA(isA<TransportResponseUnconfirmed>()),
      );

      // A row packet is [0x02, reference, rowIndex, ...38 little-endian pairs].
      final rowWrites = blePlatform.writes
          .where((w) => w.length > 3 && w[0] == 0x02)
          .toList();
      expect(rowWrites, hasLength(1), reason: 'only the first row went out');
      expect(rowWrites.single[2], 0, reason: 'row index 0');
      // The trailing generic write would be a bare two-byte header.
      expect(
        blePlatform.writes.any((w) => w.length == 2 && w[0] == 0x02),
        isFalse,
        reason: 'no stray header-only packet after the aborted loop',
      );

      harness.dispose();
    });
  });

  group('control point dispatch boundary', () {
    // onDispatch marks the calibration request sent. It must fire only after
    // transport validation and immediately before the write — never on a path
    // that then rejects the command, which would let a stale frame from a
    // previous run acknowledge this one.
    test('onDispatch does not fire when the control point is not ready', () async {
      final harness = await BleHarness.connect(blePlatform);
      // No control point characteristic assigned: the write is rejected.
      harness.deviceData.ftmsControlPointCharacteristic = null;

      var dispatched = false;
      await expectLater(
        harness.deviceData.writeFtmsControlPointCommand(
          FTMSControlPoint.spinDownCommand(true),
          onDispatch: () => dispatched = true,
        ),
        throwsA(isA<StateError>()),
      );

      expect(dispatched, isFalse);
      harness.dispose();
    });

    test('onDispatch fires once, adjacent to a successful write', () async {
      final harness = await BleHarness.connect(blePlatform);
      harness.deviceData.ftmsControlPointCharacteristic = BluetoothCharacteristic(
        remoteId: harness.device.remoteId,
        serviceUuid: Guid(ftmsServiceUUID),
        characteristicUuid: Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
      );
      blePlatform.writes.clear();

      var dispatchCount = 0;
      await harness.deviceData.writeFtmsControlPointCommand(
        FTMSControlPoint.spinDownCommand(true),
        onDispatch: () => dispatchCount++,
      );

      expect(dispatchCount, 1);
      expect(blePlatform.writes, isNotEmpty);
      harness.dispose();
    });

    // Composes the three pieces that keep a stale frame off a queued run: the
    // transport scheduler (a control command cannot preempt the op already
    // running), the `onDispatch` boundary inside `_writeFtmsControlPointCommand
    // Now` (fires adjacent to the wire write, not at enqueue), and
    // CalibrationPhaseTracker's pre-dispatch guard (`!_requestSent` rejects
    // everything).
    //
    // It does NOT cover CalibrationMonitor's own spin-down path. Per the plan:
    // `onDispatch` fires before the write with no await between, so no gate can
    // park the monitor's dispatch there, and holding the custom-write gate
    // stalls the monitor's *log-enable* so it never reaches dispatch at all. A
    // monitor-level test would need an injectable dispatch seam that exists
    // only for tests. The monitor wiring is four lines; the tracker gates it
    // depends on have unit coverage in calibration_monitor_test.dart.
    test('a Machine Status frame cannot acknowledge a spin-down still queued behind other work', () async {
      final harness = await BleHarness.connect(blePlatform);
      harness.deviceData.ftmsControlPointCharacteristic = BluetoothCharacteristic(
        remoteId: harness.device.remoteId,
        serviceUuid: Guid(ftmsServiceUUID),
        characteristicUuid: Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
      );
      blePlatform.writes.clear();

      final tracker = CalibrationPhaseTracker()..start();
      final spinDown = FTMSControlPoint.spinDownCommand(true);
      bool spinDownOnWire() => blePlatform.writes.any(
        (w) => w.length >= 2 && w[0] == spinDown[0] && w[1] == spinDown[1],
      );

      // Occupy the pump with a custom write parked in flight.
      blePlatform.holdWriteGate(ccUUID);
      final busy = harness.deviceData
          .writeCustomCharacteristic(harness.device, [0x01, 1])
          .catchError((Object _) {});
      await waitUntil(() => blePlatform.writeGateWaiters(ccUUID) == 1);

      // The spin-down is genuinely queued behind it.
      final dispatch = harness.deviceData.writeFtmsControlPointCommand(
        spinDown,
        onDispatch: tracker.markRequestSent,
      );
      await _settle();
      expect(spinDownOnWire(), isFalse, reason: 'still queued, not written');

      // A frame arriving in this window belongs to a previous run: the command
      // has not dispatched, so `markRequestSent` has not fired.
      expect(
        tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED),
        isFalse,
      );
      expect(tracker.acknowledged, isFalse);
      expect(tracker.ackSource, isNull);

      // Drain the pump; the spin-down reaches the wire and `onDispatch` fires
      // adjacent to it.
      blePlatform.releaseWriteGate(ccUUID);
      await waitUntil(spinDownOnWire);
      await dispatch;
      await busy;

      // The identical frame now acknowledges — the gate was the dispatch,
      // nothing else.
      tracker.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      expect(tracker.acknowledged, isTrue);
      expect(tracker.ackSource, CalibrationAckSource.machineStatus);

      harness.dispose();
    });
  });

  group('readiness is bounded', () {
    // The unblocked branch used to await ensureFtmsNotifications untimed, so a
    // caller's 15 s budget bought nothing once setup itself stalled.
    test('a stalled setup times out within the caller budget', () async {
      final harness = await BleHarness.connect(blePlatform);
      await harness.deviceData.unblockFtmsNotifications(harness.device);

      // Machine Status goes missing and the enable parks on the wire: readiness
      // is neither ready nor promptly unavailable, which is the state that used
      // to hang.
      blePlatform.discoveryIncludesMachineStatus = false;
      harness.deviceData.machineStatusCharacteristic = null;
      await harness.deviceData.ensureFtmsNotifications(harness.device);
      blePlatform.holdNotifyGate(_indoorBikeUuid);

      final stopwatch = Stopwatch()..start();
      final readiness = await harness.deviceData.awaitFtmsNotificationsReady(
        harness.device,
        timeout: const Duration(milliseconds: 300),
      );
      stopwatch.stop();

      expect(readiness, isNot(FtmsNotificationsReadiness.ready));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));

      blePlatform.releaseNotifyGate(_indoorBikeUuid);
      harness.dispose();
    });
  });

  // The DIRCON version of this lives in dircon_machine_status_test.dart. Over
  // BLE the log-stream enable rides `_writeCustomCharacteristic`, which now
  // surfaces an unconfirmed response instead of swallowing it — so
  // CalibrationStartStage.logStreamEnable is reachable on this transport too.
  group('calibration start over BLE', () {
    test('a log-enable failure with no other live channel fails to start', () async {
      final harness = await BleHarness.connect(
        blePlatform,
        withMachineStatus: false,
      );
      final deviceData = harness.deviceData;

      // The device answers no custom request, and the FTMS block is held for
      // the whole run so no notification channel — Machine Status or Control
      // Point — is live. Nothing could observe the run.
      blePlatform.answerCustomRequests = false;
      await deviceData.blockFtmsNotifications();
      expect(deviceData.controlPointNotificationsLive, isFalse);

      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: harness.device,
        notificationsReadyTimeout: const Duration(milliseconds: 200),
      );
      await monitor.start();

      expect(monitor.phase, CalibrationPhase.failedToStart);
      expect(
        monitor.startFailureStage,
        CalibrationStartStage.logStreamEnable,
      );
      expect(monitor.ackChannelsLive, isFalse);
      expect(deviceData.controlPointNotificationsLive, isFalse);

      monitor.dispose();
      harness.dispose();
    });
  });
}

/// Flags 0x0000 plus the mandatory instantaneous speed — the shortest frame
/// `_decodeIndoorBikeData` accepts and publishes.
const _indoorBikeFrame = [0x00, 0x00, 0x64, 0x00];

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<List<int>> _sendOverDirCon(int watts) async {
  final connector = FakeDirConConnector();
  final device = BluetoothDevice.fromId('00:00:00:00:00:D1');
  final deviceData = DeviceData(dirConConnector: connector.call)
    ..advertisedIpAddress = '192.168.1.50';
  await deviceData.connectPreferred(device, waitForSetup: true);

  expect(deviceData.transportState.value.transport, DeviceTransportKind.dircon);

  deviceData.setWorkoutTargetPower(watts);
  final session = connector.first;
  await waitUntil(() => session.writesFor(ftmsControlPointUUID).isNotEmpty);
  final bytes = session.writesFor(ftmsControlPointUUID).single;

  deviceData.dispose();
  return bytes;
}

Future<List<int>> _sendOverBle(FakeBlePlatform platform, int watts) async {
  // Triggers FlutterBluePlus's lazy initialization so it subscribes to the
  // fake's event streams before any connection state is emitted.
  await FlutterBluePlus.isSupported;

  final device = BluetoothDevice.fromId('00:00:00:00:00:B1');
  final deviceData = DeviceData();

  // The transport state moves to Bluetooth/connected through the connection
  // monitor's listener. Populating FlutterBluePlus's internal connection map
  // alone would leave DeviceData reporting no transport.
  deviceData.startConnectionMonitor(device);
  platform.markConnected(device.remoteId);
  await waitUntil(() => deviceData.isTransportActive);

  expect(
    deviceData.transportState.value.transport,
    DeviceTransportKind.bluetooth,
  );
  expect(device.isConnected, isTrue);

  deviceData.ftmsControlPointCharacteristic = BluetoothCharacteristic(
    remoteId: device.remoteId,
    serviceUuid: Guid(ftmsServiceUUID),
    characteristicUuid: Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID),
  );

  platform.writes.clear();
  deviceData.setWorkoutTargetPower(watts);
  await waitUntil(() => platform.writes.isNotEmpty);
  final bytes = platform.writes.single;

  deviceData.stopConnectionMonitor();
  deviceData.dispose();
  return bytes;
}
