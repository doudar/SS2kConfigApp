// Plan §7.2: BLE and DIRCON must receive identical encoded target commands.
//
// This file installs a fake FlutterBluePlusPlatform so a real
// BluetoothCharacteristic.write() runs through DeviceData's actual transport
// selector. FlutterBluePlus subscribes to the platform event streams exactly
// once per isolate and never unsubscribes, so these tests must stay in their
// own file — restoring the previous instance in tearDown does not undo those
// subscriptions.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_connection_retry.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';

import 'support/fake_dircon_session.dart';

const _targetWatts = 250;
final _indoorBikeUuid = ftmsIndoorBikeDataUUID;
const _machineStatusUuid = FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Installed before anything can touch FlutterBluePlus, so its one-time
  // initialization binds to this fake rather than to a real platform.
  final blePlatform = _FakeBlePlatform();
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
      final harness = await _BleHarness.connect(blePlatform);

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
      final harness = await _BleHarness.connect(blePlatform);

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
      final harness = await _BleHarness.connect(
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
      final harness = await _BleHarness.connect(blePlatform);
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
      await _waitUntil(
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
      final harness = await _BleHarness.connect(blePlatform);
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

      await _waitUntil(
        () =>
            deviceData.transportState.value.transport ==
                DeviceTransportKind.bluetooth &&
            deviceData.transportState.value.phase ==
                DeviceTransportPhase.connected,
      );

      // Both, not just Indoor Bike Data: 0x2ADA is calibration's only evidence
      // channel, and it was never enabled over BLE in the captured session.
      await _waitUntil(() => blePlatform.enabledNow(_machineStatusUuid));
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

      await _waitUntil(() => secondRan);
      expect(
        deviceData.transportState.value.phase,
        DeviceTransportPhase.connected,
      );

      deviceData.stopConnectionMonitor();
      deviceData.dispose();
    });
  });

  // A6 proper. The captured session never enabled 0x2ADA over BLE at any point,
  // and the cause could not be localized from the log — because discovery
  // treats Indoor Bike Data as proof it ran, so a Machine Status that goes
  // missing once stays missing for the life of the connection.
  group('FTMS discovery capabilities', () {
    test('a discovered connection subscribes Machine Status', () async {
      final harness = await _BleHarness.connectViaDiscovery(blePlatform);

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
      final harness = await _BleHarness.connectViaDiscovery(
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
      final harness = await _BleHarness.connectViaDiscovery(blePlatform);
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
      final harness = await _BleHarness.connectViaDiscovery(blePlatform);
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
      final harness = await _BleHarness.connectViaDiscovery(blePlatform);
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
      await _waitUntil(() => frames.isNotEmpty);
      expect(frames.single, const [0x80, 0x13, 0x01, 0x20, 0x03, 0x60, 0x09]);

      harness.dispose();
    });

    // The control point rides the same block as the other two: a stream that is
    // live while the transport is meant to be quiet is the thing the block
    // exists to prevent, whatever it carries.
    test('the FTMS block covers the control point', () async {
      final harness = await _BleHarness.connectViaDiscovery(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);
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
      final harness = await _BleHarness.connectViaDiscovery(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);

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
      final harness = await _BleHarness.connect(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);
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
  });

  group('strict vs. tolerant custom writes', () {
    // The low-level write must surface an unconfirmed response, and the legacy
    // writeToSS2k wrapper must be the only thing that swallows it.
    test('writeToSS2kStrict throws where writeToSS2k absorbs', () async {
      final harness = await _BleHarness.connect(blePlatform);
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
  });

  group('control point dispatch boundary', () {
    // onDispatch marks the calibration request sent. It must fire only after
    // transport validation and immediately before the write — never on a path
    // that then rejects the command, which would let a stale frame from a
    // previous run acknowledge this one.
    test('onDispatch does not fire when the control point is not ready', () async {
      final harness = await _BleHarness.connect(blePlatform);
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
      final harness = await _BleHarness.connect(blePlatform);
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
  });

  group('readiness is bounded', () {
    // The unblocked branch used to await ensureFtmsNotifications untimed, so a
    // caller's 15 s budget bought nothing once setup itself stalled.
    test('a stalled setup times out within the caller budget', () async {
      final harness = await _BleHarness.connect(blePlatform);
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
}

/// Flags 0x0000 plus the mandatory instantaneous speed — the shortest frame
/// `_decodeIndoorBikeData` accepts and publishes.
const _indoorBikeFrame = [0x00, 0x00, 0x64, 0x00];

/// A BLE-connected [DeviceData] with the FTMS characteristics assigned
/// directly.
///
/// Service discovery is not modelled: `indoorBikeCharacteristic` and
/// `machineStatusCharacteristic` are public fields, so assigning them is enough
/// for the notification lifecycle to run — the same shortcut `_sendOverBle`
/// already takes for the control point.
class _BleHarness {
  _BleHarness(this.device, this.deviceData);

  final BluetoothDevice device;
  final DeviceData deviceData;

  static int _nextId = 0;

  static Future<_BleHarness> connect(
    _FakeBlePlatform platform, {
    bool withMachineStatus = true,
  }) async {
    await FlutterBluePlus.isSupported;
    platform.reset();

    final device = BluetoothDevice.fromId(
      '00:00:00:00:00:${(_nextId++).toRadixString(16).padLeft(2, '0').toUpperCase()}',
    );
    // Discovery has to agree with the direct assignment below, or the
    // epoch-scoped re-probe — which fires precisely when Machine Status is
    // missing — would hand the characteristic back and contradict the fixture.
    platform.discoveryIncludesMachineStatus = withMachineStatus;

    final deviceData = DeviceData();
    deviceData.startConnectionMonitor(device);
    platform.markConnected(device.remoteId);
    await _waitUntil(() => deviceData.isTransportActive);

    deviceData.indoorBikeCharacteristic = BluetoothCharacteristic(
      remoteId: device.remoteId,
      serviceUuid: Guid(ftmsServiceUUID),
      characteristicUuid: Guid(_indoorBikeUuid),
    );
    if (withMachineStatus) {
      deviceData.machineStatusCharacteristic = BluetoothCharacteristic(
        remoteId: device.remoteId,
        serviceUuid: Guid(ftmsServiceUUID),
        characteristicUuid: Guid(_machineStatusUuid),
      );
    }
    return _BleHarness(device, deviceData);
  }

  /// Like [connect], but lets `setupConnection` run real service discovery and
  /// assign the characteristics itself — the path A6 lives on.
  static Future<_BleHarness> connectViaDiscovery(
    _FakeBlePlatform platform, {
    bool withMachineStatus = true,
  }) async {
    await FlutterBluePlus.isSupported;
    platform.reset();
    platform.discoveryIncludesMachineStatus = withMachineStatus;

    final device = BluetoothDevice.fromId(
      '00:00:00:00:00:${(_nextId++).toRadixString(16).padLeft(2, '0').toUpperCase()}',
    );
    final deviceData = DeviceData();
    deviceData.startConnectionMonitor(device);
    platform.markConnected(device.remoteId);
    await _waitUntil(() => deviceData.isTransportActive);

    await deviceData.setupConnection(device);
    return _BleHarness(device, deviceData);
  }

  void dispose() {
    deviceData.stopConnectionMonitor();
    deviceData.dispose();
  }
}

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
  await _waitUntil(() => session.writesFor(ftmsControlPointUUID).isNotEmpty);
  final bytes = session.writesFor(ftmsControlPointUUID).single;

  deviceData.dispose();
  return bytes;
}

Future<List<int>> _sendOverBle(_FakeBlePlatform platform, int watts) async {
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
  await _waitUntil(() => deviceData.isTransportActive);

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
  await _waitUntil(() => platform.writes.isNotEmpty);
  final bytes = platform.writes.single;

  deviceData.stopConnectionMonitor();
  deviceData.dispose();
  return bytes;
}

/// Only the members these tests exercise are overridden; every other member of
/// [FlutterBluePlusPlatform] already has a usable default.
final class _FakeBlePlatform extends FlutterBluePlusPlatform {
  final StreamController<BmConnectionStateResponse> _connectionStates =
      StreamController<BmConnectionStateResponse>.broadcast();
  final StreamController<BmBluetoothAdapterState> _adapterStates =
      StreamController<BmBluetoothAdapterState>.broadcast();
  final StreamController<BmCharacteristicData> _characteristicWrites =
      StreamController<BmCharacteristicData>.broadcast();
  final StreamController<BmCharacteristicData> _characteristicReceived =
      StreamController<BmCharacteristicData>.broadcast();
  // setNotifyValue takes `.first` on this *before* it learns whether the
  // characteristic has a CCCD. The base class default is an empty stream, whose
  // `.first` completes with a "No element" error nothing is there to catch.
  // A controller that never closes leaves that future harmlessly pending.
  final StreamController<BmDescriptorData> _descriptorWrites =
      StreamController<BmDescriptorData>.broadcast();
  // The base class default is an empty stream, and `discoverServices` takes
  // `.first` on it — so without this any code path that discovers services
  // fails with a bare "No element" instead of a modelled result.
  final StreamController<BmDiscoverServicesResult> _discoveredServices =
      StreamController<BmDiscoverServicesResult>.broadcast();

  /// Whether service discovery reports 0x2ADA. False models both firmware
  /// without Machine Status and a discovery pass that missed it — the two cases
  /// the epoch-scoped re-probe exists to tell apart.
  bool discoveryIncludesMachineStatus = true;

  /// How many times discovery actually reached the platform. The re-probe is
  /// budgeted at one per connection epoch, which is only observable here.
  int discoveryCount = 0;

  /// Whether the device answers custom-characteristic requests. See
  /// [writeCharacteristic]; setting it false models a response-silent device.
  bool answerCustomRequests = true;

  final List<List<int>> writes = [];

  /// Every `setNotifyValue` request, in order.
  final List<({String uuid, bool enable})> notifyCalls = [];
  final Map<String, bool> _notifyState = {};
  final Map<String, Completer<void>> _notifyGates = {};
  final Map<String, int> _notifyGateWaiters = {};

  /// Current wire state per characteristic. `isNotifying` on the real
  /// characteristic reads a CCCD descriptor cache this fake does not populate,
  /// so this is the only place the block's effect is observable.
  bool enabledNow(String uuid) => _notifyState[_key(uuid)] ?? false;

  final Set<String> _staleNotifyUuids = {};

  /// Makes `setNotifyValue` for [uuid] fail the way both platform plugins do
  /// when their cached service list no longer holds the service a cached
  /// characteristic came from — Run D's
  /// `PlatformException(setNotifyValue, primary service not found '1826')`.
  ///
  /// Cleared by the next [discoverServices], because rediscovery is exactly
  /// what repairs the cache. [permanent] models a device that keeps failing, so
  /// a test can prove the re-probe is budgeted rather than looping.
  void failNotifyAsStaleService(String uuid, {bool permanent = false}) {
    _staleNotifyUuids.add(_key(uuid));
    if (permanent) _permanentStaleNotifyUuids.add(_key(uuid));
  }

  final Set<String> _permanentStaleNotifyUuids = {};

  /// Parks a `setNotifyValue` for [uuid] until [releaseNotifyGate], so a test
  /// can take a block while an enable is still in flight.
  void holdNotifyGate(String uuid) {
    _notifyGates[_key(uuid)] = Completer<void>();
    _notifyGateWaiters[_key(uuid)] = 0;
  }

  void releaseNotifyGate(String uuid) {
    final gate = _notifyGates.remove(_key(uuid));
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// How many `setNotifyValue` calls are currently parked on [uuid]'s gate.
  /// Lets a test wait for a pass to actually reach the wire rather than
  /// guessing at a number of event-loop turns.
  int notifyGateWaiters(String uuid) => _notifyGateWaiters[_key(uuid)] ?? 0;

  /// Emits a notification frame the way the platform does.
  ///
  /// `onValueReceived` filters on remoteId, primaryServiceUuid, serviceUuid,
  /// characteristicUuid, instanceId *and* success. [_BleHarness] builds its
  /// characteristics without a primaryServiceUuid and with the default
  /// instanceId, so those two have to be null and 0 here — otherwise every
  /// frame is filtered out and an "exactly one event" assertion passes because
  /// nothing was ever delivered.
  void emitNotification(
    DeviceIdentifier remoteId,
    String uuid,
    List<int> value,
  ) {
    _characteristicReceived.add(
      BmCharacteristicData(
        remoteId: remoteId,
        primaryServiceUuid: null,
        serviceUuid: Guid(ftmsServiceUUID),
        characteristicUuid: Guid(uuid),
        instanceId: 0,
        value: List<int>.from(value),
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
  }

  /// `Guid.str` collapses a standard 128-bit UUID to its 16-bit short form, so
  /// both sides have to be normalized the same way or every lookup silently
  /// misses and reads as "never enabled".
  static String _key(String uuid) => Guid(uuid).str.toLowerCase();

  void reset() {
    writes.clear();
    notifyCalls.clear();
    _notifyState.clear();
    _notifyGates.clear();
    _notifyGateWaiters.clear();
    discoveryIncludesMachineStatus = true;
    discoveryCount = 0;
    answerCustomRequests = true;
    _staleNotifyUuids.clear();
    _permanentStaleNotifyUuids.clear();
  }

  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices =>
      _discoveredServices.stream;

  /// Reports two primary services — the SmartSpin2k custom service and FTMS —
  /// because `_findChar` only runs when more than one service is present.
  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    discoveryCount++;
    // Rediscovery is what repairs a stale cache, so it clears the failure —
    // except where a test asked for one that outlives it.
    _staleNotifyUuids.removeWhere(
      (uuid) => !_permanentStaleNotifyUuids.contains(uuid),
    );
    BmBluetoothCharacteristic characteristic(String service, String uuid) =>
        BmBluetoothCharacteristic(
          remoteId: request.remoteId,
          primaryServiceUuid: null,
          serviceUuid: Guid(service),
          characteristicUuid: Guid(uuid),
          instanceId: 0,
          descriptors: [],
          properties: BmCharacteristicProperties(
            broadcast: false,
            read: true,
            writeWithoutResponse: false,
            write: true,
            notify: true,
            indicate: false,
            authenticatedSignedWrites: false,
            extendedProperties: false,
            notifyEncryptionRequired: false,
            indicateEncryptionRequired: false,
          ),
        );

    BmBluetoothService service(String uuid, List<String> characteristics) =>
        BmBluetoothService(
          remoteId: request.remoteId,
          primaryServiceUuid: null,
          serviceUuid: Guid(uuid),
          characteristics: [
            for (final c in characteristics) characteristic(uuid, c),
          ],
        );

    _discoveredServices.add(
      BmDiscoverServicesResult(
        remoteId: request.remoteId,
        services: [
          service(csUUID, [ccUUID]),
          service(ftmsServiceUUID, [
            _indoorBikeUuid,
            FTMS_CONTROL_POINT_CHARACTERISTIC_UUID,
            if (discoveryIncludesMachineStatus) _machineStatusUuid,
          ]),
        ],
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    return true;
  }

  // Returning false means "this characteristic has no CCCD", which is the
  // branch where FlutterBluePlus skips waiting for an OnDescriptorWritten
  // event. That keeps the fake to the one call it needs to observe.
  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async {
    final uuid = request.characteristicUuid.str.toLowerCase();
    final gate = _notifyGates[uuid];
    if (gate != null) {
      _notifyGateWaiters[uuid] = (_notifyGateWaiters[uuid] ?? 0) + 1;
      await gate.future;
      _notifyGateWaiters[uuid] = (_notifyGateWaiters[uuid] ?? 1) - 1;
    }
    if (_staleNotifyUuids.contains(uuid)) {
      notifyCalls.add((uuid: uuid, enable: request.enable));
      throw PlatformException(
        code: 'setNotifyValue',
        message: "primary service not found '1826'",
      );
    }
    notifyCalls.add((uuid: uuid, enable: request.enable));
    _notifyState[uuid] = request.enable;
    return false;
  }

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged =>
      _connectionStates.stream;

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged =>
      _adapterStates.stream;

  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten =>
      _characteristicWrites.stream;

  @override
  Stream<BmCharacteristicData> get onCharacteristicReceived =>
      _characteristicReceived.stream;

  @override
  Stream<BmDescriptorData> get onDescriptorWritten => _descriptorWrites.stream;

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;

  // BluetoothCharacteristic.write() fails the operation if the adapter reports
  // off or turning off.
  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async => BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);

  @override
  Future<bool> writeCharacteristic(
    BmWriteCharacteristicRequest request,
  ) async {
    writes.add(List<int>.from(request.value));
    // The real firmware answers every `[0x01, reference]` read with a
    // `[0x80, reference, ...]` notification, and _writeCustomCharacteristic
    // holds the shared transport queue until it arrives. A silent fake makes
    // every settings sweep cost the full 2 s response timeout per entry, which
    // is minutes for one connection bootstrap.
    if (answerCustomRequests &&
        _key(request.characteristicUuid.str) == _key(ccUUID) &&
        request.value.length > 1) {
      final reference = request.value[1];
      scheduleMicrotask(() {
        _characteristicReceived.add(
          BmCharacteristicData(
            remoteId: request.remoteId,
            primaryServiceUuid: null,
            serviceUuid: Guid(csUUID),
            characteristicUuid: Guid(ccUUID),
            instanceId: 0,
            value: [0x80, reference],
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        );
      });
    }
    // write() awaits a matching completion event before returning.
    _characteristicWrites.add(
      BmCharacteristicData(
        remoteId: request.remoteId,
        primaryServiceUuid: request.primaryServiceUuid,
        serviceUuid: request.serviceUuid,
        characteristicUuid: request.characteristicUuid,
        instanceId: request.instanceId,
        value: request.value,
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    return true;
  }

  void markConnected(DeviceIdentifier remoteId) {
    _connectionStates.add(
      BmConnectionStateResponse(
        remoteId: remoteId,
        connectionState: BmConnectionStateEnum.connected,
        disconnectReasonCode: null,
        disconnectReasonString: null,
      ),
    );
  }
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
