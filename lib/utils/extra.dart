import 'dart:io';
import 'dart:async';

import 'package:SS2kConfigApp/utils/customcharhelpers.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'utils.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Map<DeviceIdentifier, StreamControllerReemit<bool>> _cglobal = {};
final Map<DeviceIdentifier, StreamControllerReemit<bool>> _dglobal = {};

class BLEData {
  ValueNotifier<int> rssi = ValueNotifier(0);
  ValueNotifier<bool> charReceived = ValueNotifier(false);
  late BluetoothService firmwareService;
  late BluetoothCharacteristic firmwareDataCharacteristic;
  late BluetoothCharacteristic firmwareControlCharacteristic;
  BluetoothCharacteristic? _myCharacteristic;
  BluetoothConnectionState connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];

  ValueNotifier<bool> isReadingOrWriting = ValueNotifier(false);
  bool isConnecting = false;
  bool isDisconnecting = false;

  var customCharacteristic = customCharacteristicFramework;

  late StreamSubscription<BluetoothConnectionState> connectionStateSubscription;
  late StreamSubscription<bool> isConnectingSubscription;
  late StreamSubscription<bool> isDisconnectingSubscription;

  setupConnection(BluetoothDevice device) async {
    if (device.isConnected) {
      await _discoverServices(device);
      if (services.length > 1) {
        await _findChar();
      }
    }
  }

  BluetoothCharacteristic getMyCharacteristic(BluetoothDevice device) {
    late BluetoothCharacteristic _char;
    //while (_myCharacteristic == null) {
    //   if (device.isDisconnected) {
    //if (FlutterBluePlus.isScanningNow) {
    //  FlutterBluePlus.stopScan();
    //}
    //device.connectAndUpdateStream().catchError((e) {});

    if (device.isConnected) {
      _discoverServices(device);
      if (services.length > 1) {
        _findChar();
      }
    }
    try {
      _char = _myCharacteristic!;
    } catch (e) {}
    return _char;
  }

  Future _discoverServices(BluetoothDevice device) async {
    if (!isReadingOrWriting.value) {
      isReadingOrWriting.value = true;
      try {
        if (services.length < 1) {
          services = await device.discoverServices();
        }
      } catch (e) {
        print(e);
      }
      isReadingOrWriting.value = false;
    }
  }

  Future _findChar() async {
    if (!isReadingOrWriting.value) {
      isReadingOrWriting.value = true;
      while (!charReceived.value) {
        try {
          BluetoothService cs = services.first;
          for (BluetoothService s in services) {
            if (s.uuid == Guid(csUUID)) {
              cs = s;
              break;
            }
          }
          List<BluetoothCharacteristic> characteristics = cs.characteristics;
          for (BluetoothCharacteristic c in characteristics) {
            if (c.uuid == Guid(ccUUID)) {
              _myCharacteristic = c;
              break;
            }
          }
          for (BluetoothService s in services) {
            if (s.uuid == Guid("4FAFC201-1FB5-459E-8FCC-C5C9C331914B")) {
              firmwareService = s;
              break;
            }
          }
          characteristics = firmwareService.characteristics;
          for (BluetoothCharacteristic c in characteristics) {
            print(c.uuid.toString());
            if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130005")) {
              firmwareDataCharacteristic = c;
            }
            if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130003")) {
              firmwareControlCharacteristic = c;
            }
          }
          charReceived.value = true;
        } catch (e) {}
      }
    }
    isReadingOrWriting.value = false;
  }
}

/// connect & disconnect + update stream
extension Extra on BluetoothDevice {
  // convenience
  StreamControllerReemit<bool> get _cstream {
    _cglobal[remoteId] ??= StreamControllerReemit(initialValue: false);
    return _cglobal[remoteId]!;
  }

  // convenience
  StreamControllerReemit<bool> get _dstream {
    _dglobal[remoteId] ??= StreamControllerReemit(initialValue: false);
    return _dglobal[remoteId]!;
  }

  // get stream
  Stream<bool> get isConnecting {
    return _cstream.stream;
  }

  // get stream
  Stream<bool> get isDisconnecting {
    return _dstream.stream;
  }

  // connect & update stream
  Future connectAndUpdateStream() async {
    _cstream.add(true);
    bool _connected = false;
    while (!_connected) {
      try {
        await connect(mtu: 527);
        _connected = true;
      } catch (e) {
        sleep(Duration(milliseconds: 50));
      } finally {
        _cstream.add(false);
      }
    }
  }

  // disconnect & update stream
  Future<void> disconnectAndUpdateStream({bool queue = true}) async {
    _dstream.add(true);
    try {
      await disconnect(queue: queue);
    } finally {
      _dstream.add(false);
    }
  }
}
