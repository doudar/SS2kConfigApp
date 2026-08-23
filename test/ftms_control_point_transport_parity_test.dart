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
}

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

  final List<List<int>> writes = [];

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
