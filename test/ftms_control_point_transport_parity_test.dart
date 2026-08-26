// Plan §7.2: BLE and DIRCON must receive identical encoded target commands.
//
// This file installs a fake FlutterBluePlusPlatform so a real
// BluetoothCharacteristic.write() runs through DeviceData's actual transport
// selector. FlutterBluePlus subscribes to the platform event streams exactly
// once per isolate and never unsubscribes, so these tests must stay in their
// own file — restoring the previous instance in tearDown does not undo those
// subscriptions.
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
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
      // Data stays assigned so the pass still has work to do.
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
