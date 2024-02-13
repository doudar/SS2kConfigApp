import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'utils.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Map<DeviceIdentifier, StreamControllerReemit<bool>> _cglobal = {};
final Map<DeviceIdentifier, StreamControllerReemit<bool>> _dglobal = {};

class BLEData {
  int? rssi;
  bool charReceived = false;

  late BluetoothCharacteristic myCharacteristic;
  BluetoothConnectionState connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];

  ValueNotifier<bool> isReadingOrWriting = ValueNotifier(false);
  bool isConnecting = false;
  bool isDisconnecting = false;

  var customCharacteristic = customCharacteristicFramework;

  late StreamSubscription<BluetoothConnectionState> connectionStateSubscription;
  late StreamSubscription<bool> isConnectingSubscription;
  late StreamSubscription<bool> isDisconnectingSubscription;
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
  Future<void> connectAndUpdateStream() async {
    _cstream.add(true);
    bool _connected = false;
    while (!_connected) {
      try {
        await connect(mtu: 512);
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
