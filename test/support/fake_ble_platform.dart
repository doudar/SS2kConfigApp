// A fake [FlutterBluePlusPlatform] and the BLE-connected [DeviceData] harness
// built on it, shared by every test that needs a real
// `BluetoothCharacteristic.write()` to run through DeviceData's actual
// transport selector.
//
// ## Lifecycle rules — these are not optional
//
// 1. **Install the fake on `FlutterBluePlusPlatform.instance` before anything
//    touches `FlutterBluePlus`.** FlutterBluePlus subscribes to the platform
//    event streams exactly once per isolate and never unsubscribes, so
//    restoring a previous instance in `tearDown` does *not* undo those
//    subscriptions. In practice this means a test file that installs this fake
//    must be the only thing in its file using FlutterBluePlus, and the install
//    belongs at the top of `main()`:
//
//    ```dart
//    void main() {
//      TestWidgetsFlutterBinding.ensureInitialized();
//      final blePlatform = FakeBlePlatform();
//      FlutterBluePlusPlatform.instance = blePlatform;
//      ...
//    }
//    ```
//
// 2. **In `tearDown`, dispose the injected `DeviceData`** (or call
//    [BleHarness.dispose], which does it), and call
//    `DeviceDataManager.clearDataForDevice` for any device registered through
//    the manager. A `DeviceData` left alive keeps its transport pump and
//    response timers running into the next test.
//
// 3. **Stop any connection monitor** — `deviceData.stopConnectionMonitor()`.
//    The monitor holds a periodic timer and a `connectionState` subscription.
//
// 4. **Pump the widget tree down** (`await tester.pumpWidget(const
//    SizedBox())` then `await tester.pump()`) before the test ends, so widget
//    timers do not leak between tests and trip the "A Timer is still pending"
//    check.
//
// 5. Call [FakeBlePlatform.reset] at the start of each test, or
//    [FakeBlePlatform.clearObservations] immediately before the transition
//    under test, so assertions see only the writes that transition caused.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';

final _indoorBikeUuid = ftmsIndoorBikeDataUUID;
const _machineStatusUuid = FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID;

/// One `writeCharacteristic` call, with the routing information
/// [FakeBlePlatform.writes] throws away.
///
/// [FakeBlePlatform.writes] records payload bytes only — no UUID, no remote id.
/// A settings sweep emits many `ccUUID` writes, so "assert exactly one write"
/// against `writes` is ambiguous. Filter [FakeBlePlatform.writeCalls] by
/// [characteristicUuid] (and, for custom characteristics, by the setting
/// reference byte at `value[1]`) instead.
typedef BleWriteCall = ({
  DeviceIdentifier remoteId,
  Guid serviceUuid,
  Guid characteristicUuid,
  List<int> value,
});

/// Only the members these tests exercise are overridden; every other member of
/// [FlutterBluePlusPlatform] already has a usable default.
final class FakeBlePlatform extends FlutterBluePlusPlatform {
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
  // Same hazard again: `readRssi` takes `.first` on this. DeviceHeader reads
  // signal strength on every connected BLE session, and the base-class empty
  // stream turns that into a bare "No element" raised inside the widget's
  // initState rather than a modelled reading.
  final StreamController<BmReadRssiResult> _readRssiResults =
      StreamController<BmReadRssiResult>.broadcast();

  /// The value [readRssi] reports. -55 lands in the strongest band.
  int rssiReading = -55;

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

  /// Every `writeCharacteristic` call with its routing information, unlike
  /// [writes] which keeps payload bytes only. See [BleWriteCall].
  final List<BleWriteCall> writeCalls = [];

  /// Every `setNotifyValue` request, in order.
  final List<({String uuid, bool enable})> notifyCalls = [];
  final Map<String, bool> _notifyState = {};
  final Map<String, Completer<void>> _notifyGates = {};
  final Map<String, int> _notifyGateWaiters = {};

  /// Every `connect` request the platform received, in order. A fresh GATT
  /// connect on the DIRCON->BLE fallback is only observable here — the
  /// `markConnected` shortcut the other tests use bypasses `connect` entirely.
  final List<BmConnectRequest> connectCalls = [];

  /// Parks a `writeCharacteristic` for [uuid] until [releaseWriteGate]. Unlike
  /// the notify gate this holds an operation *in flight*, which is what keeps
  /// the transport pump occupied: `TransportOpPriority.control` preempts only
  /// queued work, never the op currently running.
  final Map<String, Completer<void>> _writeGates = {};
  final Map<String, int> _writeGateWaiters = {};

  void holdWriteGate(String uuid) {
    _writeGates[_key(uuid)] = Completer<void>();
    _writeGateWaiters[_key(uuid)] = 0;
  }

  void releaseWriteGate(String uuid) {
    final gate = _writeGates.remove(_key(uuid));
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// How many `writeCharacteristic` calls are currently parked on [uuid]'s gate.
  int writeGateWaiters(String uuid) => _writeGateWaiters[_key(uuid)] ?? 0;

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
  /// characteristicUuid, instanceId *and* success. [BleHarness] builds its
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

  /// Drops recorded calls without touching configuration or gate state.
  ///
  /// Call this immediately before the transition under test so a
  /// "exactly one write" assertion cannot be satisfied — or defeated — by
  /// writes from the setup that preceded it.
  void clearObservations() {
    writes.clear();
    writeCalls.clear();
    notifyCalls.clear();
    connectCalls.clear();
  }

  void reset() {
    writes.clear();
    writeCalls.clear();
    notifyCalls.clear();
    _notifyState.clear();
    // Complete before clearing: a test that failed mid-hold must not strand a
    // parked write or enable into the next test's run.
    for (final gate in [..._notifyGates.values, ..._writeGates.values]) {
      if (!gate.isCompleted) gate.complete();
    }
    _notifyGates.clear();
    _notifyGateWaiters.clear();
    _writeGates.clear();
    _writeGateWaiters.clear();
    connectCalls.clear();
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
  Stream<BmReadRssiResult> get onReadRssi => _readRssiResults.stream;

  @override
  Future<bool> readRssi(BmReadRssiRequest request) async {
    // The plugin subscribes to onReadRssi before awaiting this call's result,
    // so the reading has to land after we return, not during.
    scheduleMicrotask(
      () => _readRssiResults.add(
        BmReadRssiResult(
          remoteId: request.remoteId,
          rssi: rssiReading,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      ),
    );
    return true;
  }

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
    final gateKey = _key(request.characteristicUuid.str);
    final gate = _writeGates[gateKey];
    if (gate != null) {
      _writeGateWaiters[gateKey] = (_writeGateWaiters[gateKey] ?? 0) + 1;
      await gate.future;
      _writeGateWaiters[gateKey] = (_writeGateWaiters[gateKey] ?? 1) - 1;
    }
    writes.add(List<int>.from(request.value));
    writeCalls.add((
      remoteId: request.remoteId,
      serviceUuid: request.serviceUuid,
      characteristicUuid: request.characteristicUuid,
      value: List<int>.from(request.value),
    ));
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
            // This harness models firmware from before 0x31. Unknown reads
            // are explicitly rejected, which exercises the production app's
            // legacy per-setting fallback without weakening its strict rule.
            value: reference == 0x31
                ? const [0xff, 0x31]
                : [0x80, reference],
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

  void markDisconnected(DeviceIdentifier remoteId) {
    _connectionStates.add(
      BmConnectionStateResponse(
        remoteId: remoteId,
        connectionState: BmConnectionStateEnum.disconnected,
        disconnectReasonCode: null,
        disconnectReasonString: null,
      ),
    );
  }

  // The real plugin resolves `connect()` first and only then publishes the
  // connected state on its event stream, as a separate asynchronous step.
  // `device.connect()` subscribes to that stream before awaiting our return,
  // so a synchronous add would not actually be lost — deferring it a microtask
  // is about staying faithful to the plugin's ordering (connect completes,
  // then the state event lands), not about preventing event loss.
  @override
  Future<bool> connect(BmConnectRequest request) async {
    connectCalls.add(request);
    scheduleMicrotask(() => markConnected(request.remoteId));
    return true;
  }
}

/// A BLE-connected [DeviceData] with the FTMS characteristics assigned
/// directly.
///
/// Service discovery is not modelled: `indoorBikeCharacteristic` and
/// `machineStatusCharacteristic` are public fields, so assigning them is enough
/// for the notification lifecycle to run — the same shortcut `_sendOverBle`
/// already takes for the control point.
class BleHarness {
  BleHarness(this.device, this.deviceData);

  final BluetoothDevice device;
  final DeviceData deviceData;

  static int _nextId = 0;

  static Future<BleHarness> connect(
    FakeBlePlatform platform, {
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
    await waitUntil(() => deviceData.isTransportActive);

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
    return BleHarness(device, deviceData);
  }

  /// Like [connect], but lets `setupConnection` run real service discovery and
  /// assign the characteristics itself — the path A6 lives on.
  static Future<BleHarness> connectViaDiscovery(
    FakeBlePlatform platform, {
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
    await waitUntil(() => deviceData.isTransportActive);

    await deviceData.setupConnection(device);
    return BleHarness(device, deviceData);
  }

  void dispose() {
    deviceData.stopConnectionMonitor();
    deviceData.dispose();
  }
}

/// Runs [body] with every `print` line also appended to [sink], so a test can
/// assert on a specific transport log line without silencing normal output.
Future<void> withPrintCapture(
  List<String> sink,
  Future<void> Function() body,
) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        sink.add(line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> waitUntil(
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
