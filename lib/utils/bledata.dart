import 'dart:async';

import 'package:flutter/foundation.dart';

import 'constants.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEData {
  ValueNotifier<int> rssi = ValueNotifier(0);
  ValueNotifier<bool> charReceived = ValueNotifier(false);
  ValueNotifier<bool> isReadingOrWriting = ValueNotifier(false);
  late StreamSubscription<BluetoothConnectionState> connectionStateSubscription;
  late StreamSubscription<bool> isConnectingSubscription;
  late StreamSubscription<bool> isDisconnectingSubscription;
  late BluetoothService firmwareService;
  late BluetoothCharacteristic firmwareDataCharacteristic;
  late BluetoothCharacteristic firmwareControlCharacteristic;
  BluetoothCharacteristic? _myCharacteristic;
  BluetoothConnectionState connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];

  bool isConnecting = false;
  bool isDisconnecting = false;
  bool configAppCompatableFirmware = false;

  var customCharacteristic = customCharacteristicFramework;

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
    } catch (e) {
      charReceived.value = false;
    }
    charReceived.value = true;
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
              configAppCompatableFirmware = true;
              break;
            }
          }
          if (configAppCompatableFirmware) {
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
          }
          charReceived.value = true;
        } catch (e) {
          charReceived.value = false;
        }
      }
    }
    isReadingOrWriting.value = false;
  }
}
