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
    // Both FTMS streams share one lifecycle. An earlier revision exempted
    // Machine Status from the block so calibration could never be blinded;
    // review reversed that, and calibration now waits for readiness instead.
    test('neither FTMS stream starts while the post-connection block is held', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      expect(deviceData.isFtmsNotificationsBlocked, isTrue);

      // Both discovered, neither listening, neither enabled on the wire.
      for (final uuid in [ftmsIndoorBikeDataUUID, _machineStatusUuid]) {
        expect(session.discovered(uuid), isTrue, reason: uuid);
        expect(session.notificationsEnabledNow(uuid), isFalse, reason: uuid);
        expect(session.isListening(uuid), isFalse, reason: uuid);
      }

      await deviceData.unblockFtmsNotifications(device);

      for (final uuid in [ftmsIndoorBikeDataUUID, _machineStatusUuid]) {
        expect(session.notificationsEnabledNow(uuid), isTrue, reason: uuid);
        expect(session.isListening(uuid), isTrue, reason: uuid);
      }

      deviceData.dispose();
    });

    test('a nested block only releases both streams on the final unblock', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      // Post-connection block plus one more.
      await deviceData.blockFtmsNotifications();
      await deviceData.unblockFtmsNotifications(device);

      expect(deviceData.isFtmsNotificationsBlocked, isTrue);
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);

      await deviceData.unblockFtmsNotifications(device);

      expect(session.isListening(_machineStatusUuid), isTrue);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isTrue);

      deviceData.dispose();
    });

    test('re-blocking cancels and disables both streams', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;
      await deviceData.unblockFtmsNotifications(device);

      await deviceData.blockFtmsNotifications();

      for (final uuid in [ftmsIndoorBikeDataUUID, _machineStatusUuid]) {
        expect(session.isListening(uuid), isFalse, reason: uuid);
        // Current wire state, not "was ever enabled" — an enable that leaked
        // past a block is invisible to the historical check.
        expect(session.notificationsEnabledNow(uuid), isFalse, reason: uuid);
      }

      deviceData.dispose();
    });

    // A block taken while an enable is still in flight would otherwise leave
    // the device notifying with nothing listening: the block saw nothing
    // enabled, so it scheduled no disable, and the enable landed afterwards.
    test('an enable superseded by a new block undoes itself', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;

      session.holdNotificationGate(_machineStatusUuid);
      final unblock = deviceData.unblockFtmsNotifications(device);
      await _settle();

      // The enable is parked mid-flight; take the block that supersedes it.
      // Not awaited before the release: the block's own disable queues behind
      // the same gate, so awaiting it here would deadlock the test.
      final block = deviceData.blockFtmsNotifications();
      await _settle();
      session.releaseNotificationGate(_machineStatusUuid);
      await unblock;
      await block;
      await _settle();

      expect(session.notificationsEnabledNow(_machineStatusUuid), isFalse);
      expect(session.isListening(_machineStatusUuid), isFalse);

      deviceData.dispose();
    });

    test('forwards a Machine Status payload to machineStatusStream', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      await deviceData.unblockFtmsNotifications(device);
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
      // The enable that matters is the one the unblock performs; the block held
      // during connect never turns notifications on at all.
      await deviceData.unblockFtmsNotifications(device);
      await _settle();

      expect(received, [
        [FTMSStatusOpCodes.SPIN_DOWN_STATUS, FTMSSpinDownStatus.SPIN_DOWN_REQUESTED],
      ]);

      await subscription.cancel();
      deviceData.dispose();
    });
  });

  group('FTMS setup failures are isolated', () {
    test('missing Indoor Bike Data does not stop Machine Status', () async {
      final session = FakeDirConSession()
        ..failCharacteristic(ftmsIndoorBikeDataUUID);
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);

      expect(deviceData.isDirConConnected, isTrue);

      // Lifting the block must not resurrect a characteristic the firmware
      // does not have, must not throw out of the timer that calls it, and must
      // not let the first characteristic's absence skip the second.
      await deviceData.unblockFtmsNotifications(device);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);
      expect(session.isListening(_machineStatusUuid), isTrue);
      expect(session.notificationsEnabledNow(_machineStatusUuid), isTrue);

      deviceData.dispose();
    });

    test('missing Machine Status does not stop Indoor Bike Data', () async {
      final session = FakeDirConSession()..failCharacteristic(_machineStatusUuid);
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);

      expect(deviceData.isDirConConnected, isTrue);
      expect(session.isListening(_machineStatusUuid), isFalse);

      await deviceData.unblockFtmsNotifications(device);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isTrue);
      expect(session.notificationsEnabledNow(ftmsIndoorBikeDataUUID), isTrue);
      // Cancelled rather than leaked: the helper listens first, then unwinds
      // its own subscription when enablement fails.
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.cancellationsFor(_machineStatusUuid), 1);

      deviceData.dispose();
    });

    // "The firmware lacks this characteristic" and "the socket just died" reach
    // the same catch. Only the first may continue to the other characteristic:
    // subscribing to a dead session achieves nothing and would leave a listener
    // attached to it.
    //
    // Abandoning the pass is only half the job. The session here is invalidated
    // *silently* — DirConSession.close() never publishes on `disconnected` and
    // _closeWithError is one-shot — so nothing else is coming to notice. If the
    // catch only breaks, DeviceData keeps reporting DIRCON/connected over a
    // dead socket, which also wedges BLE recovery: startConnectionMonitor
    // short-circuits on isDirConConnected.
    test('a transport failure mid-resubscribe abandons the pass and the transport', () async {
      final session = FakeDirConSession();
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);

      session.failCharacteristicWithTransportLoss(
        ftmsIndoorBikeDataUUID,
        emitDisconnect: false,
      );
      await deviceData.unblockFtmsNotifications(device);

      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);
      // Not attempted at all — the pass gave up on the dead session.
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.notificationsEnabledNow(_machineStatusUuid), isFalse);

      await _until(
        () => !deviceData.isDirConConnected,
        'DIRCON stayed connected over a silently closed session',
      );
      // Stops the BLE half of the failover, which has no platform in this
      // isolate. The assertions below are about releasing DIRCON, not about
      // what replaces it.
      deviceData.isUserDisconnect = true;
      await _settle();

      expect(deviceData.isTransportActive, isFalse);
      expect(session.isClosed, isTrue);
      expect(session.isListening(ccUUID), isFalse);
      // Deliberately not asserting a specific phase: automatic recovery passes
      // through DIRCON/reconnecting and then Bluetooth/connecting, and
      // none/disconnected is reserved for an explicit user disconnect.

      deviceData.dispose();
    });

    // Regression: "the firmware lacks this characteristic" and "the socket just
    // died" arrive at the same catch block. Downgrading the second to the first
    // leaves DeviceData reporting DIRCON/connected over a closed session — and
    // because startConnectionMonitor short-circuits on isDirConConnected, that
    // also wedges the BLE reconnect path.
    test('a transport failure during Machine Status setup abandons DIRCON', () async {
      final session = FakeDirConSession()
        ..failCharacteristicWithTransportLoss(_machineStatusUuid);
      final connector = FakeDirConConnector([session]);
      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = _ipAddress;

      final connect = deviceData.connectPreferred(device, waitForSetup: true);
      // connectPreferred falls back to BLE, which has no platform in this
      // isolate. Cancel its retry loop as soon as the DIRCON half has given up
      // so the test asserts on the handoff rather than on ten real attempts.
      await _until(
        () => !deviceData.isDirConConnected,
        'DIRCON stayed connected over a dead session',
      );
      deviceData.isUserDisconnect = true;
      await connect.catchError((Object _) {});

      expect(deviceData.isDirConConnected, isFalse);
      expect(deviceData.isTransportActive, isFalse);
      expect(session.isClosed, isTrue);
      // Nothing is left subscribed to the abandoned session.
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);
      expect(session.isListening(ccUUID), isFalse);

      deviceData.dispose();
    });

    // The same abandonment must hold when the session dies *silently*. Not
    // every DirConClient invalidation publishes on `disconnected`:
    // `close()` never does, and `_closeWithError` is one-shot via
    // `_disconnectEmitted`. Listening earlier does not help here — isConnected
    // is the only evidence, so the catch block has to consult it.
    test('a silent session close during Machine Status setup abandons DIRCON', () async {
      final session = FakeDirConSession()
        ..failCharacteristicWithTransportLoss(
          _machineStatusUuid,
          emitDisconnect: false,
        );
      final connector = FakeDirConConnector([session]);
      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = _ipAddress;

      final connect = deviceData.connectPreferred(device, waitForSetup: true);
      await _until(
        () => !deviceData.isDirConConnected,
        'DIRCON stayed connected over a silently closed session',
      );
      deviceData.isUserDisconnect = true;
      await connect.catchError((Object _) {});

      expect(deviceData.isDirConConnected, isFalse);
      expect(deviceData.isTransportActive, isFalse);
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isListening(ccUUID), isFalse);

      deviceData.dispose();
    });

    // Discovery succeeds and *then* the socket dies, so there is no exception
    // for the catch block to inspect — only the `disconnected` event. It is a
    // broadcast stream with no replay, so this is caught only if the listener
    // was already attached when the event fired.
    test('a session lost after Machine Status discovery abandons DIRCON', () async {
      final session = FakeDirConSession()
        ..dropConnectionAfterEnsure(_machineStatusUuid);
      final connector = FakeDirConConnector([session]);
      final deviceData = DeviceData(dirConConnector: connector.call)
        ..advertisedIpAddress = _ipAddress;

      final connect = deviceData.connectPreferred(device, waitForSetup: true);
      await _until(
        () => !deviceData.isDirConConnected,
        'DIRCON stayed connected after the session was lost mid-setup',
      );
      deviceData.isUserDisconnect = true;
      await connect.catchError((Object _) {});

      expect(deviceData.isDirConConnected, isFalse);
      expect(deviceData.isTransportActive, isFalse);
      expect(session.isClosed, isTrue);
      // The staleness guard must unwind the subscriptions it opened after
      // _closeDirCon had already cleared the fields.
      expect(session.isListening(_machineStatusUuid), isFalse);
      expect(session.isListening(ftmsIndoorBikeDataUUID), isFalse);
      expect(session.isListening(ccUUID), isFalse);

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
      expect(deviceData.isDirConConnected, isTrue);

      // The new session gets its own post-connection block, so it comes up only
      // once that is released — same lifecycle as the first connection.
      expect(second.isListening(_machineStatusUuid), isFalse);
      await deviceData.unblockFtmsNotifications(device);
      expect(second.isListening(_machineStatusUuid), isTrue);

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

  test('calibration waits for the block, then follows homing from DIRCON '
      'Machine Status', () async {
    final connector = FakeDirConConnector();
    final deviceData = await _connect(connector, device);
    final session = connector.first;
    final monitor = CalibrationMonitor(deviceData: deviceData, device: device);

    // The automatic post-connection block is still held. Machine Status is
    // suspended with it, so the homing command must not go out yet — the run's
    // own acknowledgement frames would land before anything was listening.
    final started = monitor.start();
    await _settle();
    expect(session.writesFor(ftmsControlPointUUID), isEmpty);
    expect(monitor.awaitingNotifications, isTrue);

    await deviceData.unblockFtmsNotifications(device);
    await started;

    expect(monitor.awaitingNotifications, isFalse);
    expect(monitor.notificationsReadiness, FtmsNotificationsReadiness.ready);
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

    // The run's own evidence that DIRCON carried it, which is what the
    // copied calibration report exists to show on hardware.
    expect(monitor.machineStatusLog.single.message, '14 04  max search started');

    monitor.dispose();
    deviceData.dispose();
  });

  group('calibration readiness is bounded', () {
    // A leaked block count must not make calibration unstartable. The run goes
    // ahead on the log and hMax paths, and the report says the stream was not
    // there rather than leaving the reader to infer it.
    test('a block that never lifts still starts the run, and says so', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;
      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: device,
        notificationsReadyTimeout: const Duration(milliseconds: 50),
      );

      await monitor.start();

      expect(monitor.notificationsReadiness, FtmsNotificationsReadiness.timedOut);
      expect(monitor.awaitingNotifications, isFalse);
      expect(
        session.writesFor(ftmsControlPointUUID),
        contains(orderedEquals(FTMSControlPoint.spinDownCommand(true))),
      );

      monitor.dispose();
      deviceData.dispose();
    });

    // Firmware without the characteristic is not a stuck block: the count did
    // drain, there is simply nothing to subscribe to. The two must not report
    // the same thing.
    test('firmware without Machine Status reports unavailable, not timedOut', () async {
      final session = FakeDirConSession()..failCharacteristic(_machineStatusUuid);
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);
      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: device,
        notificationsReadyTimeout: const Duration(seconds: 5),
      );

      final started = monitor.start();
      await _settle();
      await deviceData.unblockFtmsNotifications(device);
      await started;

      expect(
        monitor.notificationsReadiness,
        FtmsNotificationsReadiness.unavailable,
      );
      expect(
        session.writesFor(ftmsControlPointUUID),
        contains(orderedEquals(FTMSControlPoint.spinDownCommand(true))),
      );

      monitor.dispose();
      deviceData.dispose();
    });

    // The flag is cleared in a finally, so nothing can strand the screen on
    // "getting ready" with no way out.
    test('disposal during the wait clears the waiting flag', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: device,
        notificationsReadyTimeout: const Duration(milliseconds: 50),
      );

      final started = monitor.start();
      await _settle();
      expect(monitor.awaitingNotifications, isTrue);

      monitor.dispose();
      await started;

      expect(monitor.awaitingNotifications, isFalse);

      deviceData.dispose();
    });
  });

  // A run that cannot be started, and a run the device never acted on, used to
  // look identical from the screen: nothing happened, and eight minutes later
  // the overall timeout blamed homing force. Both now end promptly, in their
  // own phase, with copy that matches what actually went wrong.
  group('calibration reports a verdict instead of hanging', () {
    test('a control-point write that throws ends the run as failedToStart', () async {
      final session = FakeDirConSession()
        ..failWritesFor(ftmsControlPointUUID, StateError('transport gone'));
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);
      final monitor = CalibrationMonitor(deviceData: deviceData, device: device);

      final started = monitor.start();
      await _settle();
      await deviceData.unblockFtmsNotifications(device);
      await started;

      expect(monitor.phase, CalibrationPhase.failedToStart);
      expect(monitor.startFailureStage, CalibrationStartStage.dispatch);
      expect(monitor.startFailure, isNotNull);
      // The raw exception belongs in the report, never in the sanitized string
      // the screen renders.
      expect(monitor.startFailure, isNot(contains('StateError')));
      expect(
        monitor.transcript.map((e) => e.message).join('\n'),
        contains('transport gone'),
      );

      monitor.dispose();
      deviceData.dispose();
    });

    // A retry after a finished run has to be able to fail. The tracker refuses
    // to move off a terminal phase, so start() resets run state before its
    // first fallible step — otherwise the previous run's verdict would still be
    // standing when the new run failed, and the failure would go unrecorded
    // behind a stale "complete".
    test('a retry after a completed run can still report failedToStart', () async {
      final session = FakeDirConSession();
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);
      final monitor = CalibrationMonitor(deviceData: deviceData, device: device);

      final first = monitor.start();
      await _settle();
      await deviceData.unblockFtmsNotifications(device);
      await first;

      // Drive the first run all the way to a terminal verdict.
      for (final param in [
        FTMSSpinDownStatus.MAX_SEARCH_STARTED,
        FTMSSpinDownStatus.SUCCESS,
      ]) {
        session.emitNotification(_machineStatusUuid, [
          FTMSStatusOpCodes.SPIN_DOWN_STATUS,
          param,
        ]);
        await _settle();
      }
      expect(monitor.phase, CalibrationPhase.complete);

      // The retry cannot reach the device at all.
      session.failWritesFor(ftmsControlPointUUID, StateError('transport gone'));
      await monitor.start();

      expect(monitor.phase, CalibrationPhase.failedToStart);
      expect(monitor.startFailureStage, CalibrationStartStage.dispatch);

      monitor.dispose();
      deviceData.dispose();
    });

    // The forced transition itself: [markStartFailed] deliberately overrides a
    // terminal phase, unlike every other transition, so a start failure that
    // lands before the run reset is still recorded.
    test('markStartFailed overrides a terminal verdict', () {
      final tracker = CalibrationPhaseTracker()..start();
      expect(tracker.markTimedOut(), isTrue);
      expect(tracker.phase, CalibrationPhase.failedNeverStarted);

      // An ordinary failure is refused...
      expect(tracker.markNoAcknowledgement(), isFalse);
      expect(tracker.phase, CalibrationPhase.failedNeverStarted);

      // ...the forced one is not.
      expect(tracker.markStartFailed(), isTrue);
      expect(tracker.phase, CalibrationPhase.failedToStart);
    });

    // The two diagnoses the overall timeout has to keep apart. Homing force is
    // only implicated once the search actually ran; before that the device took
    // the command and never acted on it, which is a cadence-source problem.
    test('the overall timeout splits on whether homing ever started', () {
      final neverStarted = CalibrationPhaseTracker()..start();
      neverStarted.markRequestSent();
      neverStarted.onControlPointResponse(const [0x80, 0x13, 0x01]);
      expect(neverStarted.acknowledged, isTrue);
      expect(neverStarted.homingStarted, isFalse);
      expect(neverStarted.markTimedOut(), isTrue);
      expect(neverStarted.phase, CalibrationPhase.failedNeverStarted);

      final searched = CalibrationPhaseTracker()..start();
      searched.markRequestSent();
      searched.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      searched.onSpinDownStatus(FTMSSpinDownStatus.SPIN_DOWN_REQUESTED);
      expect(searched.homingStarted, isTrue);
      expect(searched.markTimedOut(), isTrue);
      expect(searched.phase, CalibrationPhase.failedTimeout);
    });

    // The control point is the only channel this firmware sends
    // unconditionally: 0x2ADA is suppressed when the status value did not
    // change, and log lines are dropped when the firmware's buffer overflows.
    test('a control point response acknowledges the run on its own', () {
      final tracker = CalibrationPhaseTracker()..start();
      tracker.markRequestSent();

      // Not this run's opcode, and not a response frame at all.
      expect(tracker.onControlPointResponse(const [0x80, 0x05, 0x01]), isFalse);
      expect(tracker.acknowledged, isFalse);
      expect(tracker.onControlPointResponse(const [0x13, 0x01]), isFalse);
      expect(tracker.acknowledged, isFalse);

      // The real thing: `80 13 01` plus the mandatory target-speed parameters.
      expect(
        tracker.onControlPointResponse(const [
          0x80,
          0x13,
          0x01,
          0x20,
          0x03,
          0x60,
          0x09,
        ]),
        // Acknowledgement is not progress: homing has not begun.
        isFalse,
      );
      expect(tracker.acknowledged, isTrue);
      expect(tracker.ackSource, CalibrationAckSource.controlPoint);
      expect(tracker.controlPointResult, FTMSResultCodes.SUCCESS);
      expect(tracker.phase, CalibrationPhase.waitingForCadence);
    });

    // Nothing before markRequestSent belongs to this run — a response left over
    // from a workout control write would otherwise acknowledge a run that has
    // not dispatched yet.
    test('a control point response before dispatch is ignored', () {
      final tracker = CalibrationPhaseTracker()..start();
      expect(tracker.onControlPointResponse(const [0x80, 0x13, 0x01]), isFalse);
      expect(tracker.acknowledged, isFalse);
      expect(tracker.ackSource, isNull);
    });

    // Disposal is cancellation: the screen is gone and there is nobody to show
    // a verdict to. Reporting failedToStart here would be noise in the report of
    // a run the user themselves ended.
    test('disposal during start is cancellation, not a failure', () async {
      final session = FakeDirConSession()
        ..failWritesFor(ftmsControlPointUUID, StateError('transport gone'));
      final connector = FakeDirConConnector([session]);
      final deviceData = await _connect(connector, device);
      final monitor = CalibrationMonitor(deviceData: deviceData, device: device);

      final started = monitor.start();
      await _settle();
      monitor.dispose();
      await deviceData.unblockFtmsNotifications(device);
      await started;

      expect(monitor.phase, isNot(CalibrationPhase.failedToStart));

      deviceData.dispose();
    });

    // The write completing means the *stack* accepted it. Against a firmware
    // whose main loop is wedged the command is delivered and never processed —
    // exactly the 2026-08-25 session — and the device answers a spin-down on
    // receipt, so silence past the budget is a real verdict.
    test('a delivered but unacknowledged command ends the run promptly', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;
      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: device,
        logSilenceTimeout: const Duration(milliseconds: 100),
      );

      final started = monitor.start();
      await _settle();
      await deviceData.unblockFtmsNotifications(device);
      await started;

      // Delivered...
      expect(
        session.writesFor(ftmsControlPointUUID),
        contains(orderedEquals(FTMSControlPoint.spinDownCommand(true))),
      );
      // ...and then nothing comes back.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(monitor.phase, CalibrationPhase.failedNoAcknowledgement);
      expect(monitor.acknowledged, isFalse);
      // Machine Status was live, so the device demonstrably ignored the
      // request rather than the app being blind.
      expect(monitor.ackChannelsLive, isTrue);

      monitor.dispose();
      deviceData.dispose();
    });

    test('an acknowledged command leaves the run to the homing timers', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final session = connector.first;
      final monitor = CalibrationMonitor(
        deviceData: deviceData,
        device: device,
        logSilenceTimeout: const Duration(milliseconds: 100),
      );

      final started = monitor.start();
      await _settle();
      await deviceData.unblockFtmsNotifications(device);
      await started;

      // The firmware's answer on receipt, before any pedalling. One frame is
      // deliberately not enough to confirm homing — but it is the
      // acknowledgement.
      session.emitNotification(_machineStatusUuid, [
        FTMSStatusOpCodes.SPIN_DOWN_STATUS,
        FTMSSpinDownStatus.SPIN_DOWN_REQUESTED,
      ]);
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(monitor.acknowledged, isTrue);
      expect(monitor.acknowledgedAfter, isNotNull);
      expect(monitor.phase, isNot(CalibrationPhase.failedNoAcknowledgement));
      expect(monitor.phase, CalibrationPhase.waitingForCadence);

      monitor.dispose();
      deviceData.dispose();
    });

    // The readiness verdict is the difference between a diagnosable report and
    // a guess, and it used to appear only as a parenthetical inside the
    // machine-status section header.
    test('the readiness verdict reaches the transcript and the report', () async {
      final connector = FakeDirConConnector();
      final deviceData = await _connect(connector, device);
      final monitor = CalibrationMonitor(deviceData: deviceData, device: device);

      final started = monitor.start();
      await _settle();
      await deviceData.unblockFtmsNotifications(device);
      await started;

      expect(
        monitor.transcript.map((e) => e.message).join('\n'),
        contains('FTMS readiness: ready'),
      );

      final report = buildCalibrationReport(
        transcript: monitor.transcript,
        droppedLines: monitor.droppedLines,
        phase: monitor.phase,
        minFound: monitor.minFound,
        maxFound: monitor.maxFound,
        usedFtmsPath: monitor.usedFtmsPath,
        sweepTimedOut: monitor.sweepTimedOut,
        logStreamSilent: monitor.logStreamSilent,
        machineStatus: monitor.machineStatusLog,
        droppedStatusFrames: monitor.droppedStatusFrames,
        machineStatusReadiness: monitor.notificationsReadiness,
        acknowledged: monitor.acknowledged,
        acknowledgedAfter: monitor.acknowledgedAfter,
        ackChannelsLive: monitor.ackChannelsLive,
        startFailure: monitor.startFailure,
      );

      expect(report, contains('machineStatusReadiness: ready'));
      expect(report, contains('acknowledged: false'));

      monitor.dispose();
      deviceData.dispose();
    });
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

/// Waits for [condition], failing with [reason] instead of hanging until the
/// suite-level timeout when the behaviour under test regresses.
Future<void> _until(bool Function() condition, String reason) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(reason);
}
