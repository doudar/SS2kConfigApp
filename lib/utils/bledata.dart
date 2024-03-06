/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'constants.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/snackbar.dart';

class BLEDataManager {
  static final Map<String, BLEData> _dataMap = {};

  static BLEData forDevice(BluetoothDevice device) {
    if (!_dataMap.containsKey(device.remoteId.str)) {
      _dataMap[device.remoteId.str] = BLEData();
    }
    return _dataMap[device.remoteId.str]!;
  }

  static void updateDataForDevice(BluetoothDevice device, BLEData data) {
    _dataMap[device.remoteId.str] = data;
  }

  static void clearDataForDevice(BluetoothDevice device) {
    _dataMap.remove(device.remoteId.str);
  }
}

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
  bool isUpdatingFirmware = false;
  String firmwareVersion = "";

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
    if (_myCharacteristic != null) {
      charReceived.value = true;
      _char = _myCharacteristic!;
    } else {
      charReceived.value = false;
    }
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

  ///Data Helpers****************************************************************

  bool _subscribed = false;
  final _lastRequestStopwatch = Stopwatch();
// only used as a flag to prevent multiple concurrent instances of updateCustomCharacter
  bool _inUpdateLoop = false;

  Future updateCustomCharacter(BluetoothDevice device) async {
    if (_inUpdateLoop) {
      return;
    }
    if (Platform.isAndroid) {
      device.requestMtu(515);
    }
    _inUpdateLoop = true;
    if (!this.getMyCharacteristic(device).isNotifying) notify(device);
    if (!_subscribed) decode(device);
    if (!_lastRequestStopwatch.isRunning) {
      await requestSettings(device);
      _lastRequestStopwatch.start();
    } else if (_lastRequestStopwatch.elapsed > Duration(seconds: 5)) {
      _lastRequestStopwatch.reset();
      await requestSettings(device);
    }
    this.isReadingOrWriting.value = false;
    _inUpdateLoop = false;
  }

  void notify(BluetoothDevice device) {
    if (!this.getMyCharacteristic(device).isNotifying) {
      try {
        this.getMyCharacteristic(device).setNotifyValue(true);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to subscribe to notifications", success: false);
      }
    }
  }

  void findNSave(BluetoothDevice device, Map c, String find) {
    // Firmware that wasn't compatable with the app would reboot whenever this command was read.
    if (!this.configAppCompatableFirmware && c["vName"] == saveVname) {
      return;
    }
    if (c["vName"] == find) {
      try {
        write(device, [0x02, int.parse(c["reference"]), 0x01]);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
      }
    }
  }

  Future saveAllSettings(BluetoothDevice device) async {
    this.isReadingOrWriting.value = true;
    await this.customCharacteristic.forEach((c) => c["isSetting"] ? writeToSS2K(device, c) : ());
    await this.customCharacteristic.forEach((c) => findNSave(device, c, saveVname));
    this.isReadingOrWriting.value = false;
  }

  Future reboot(BluetoothDevice device) async {
    await this.customCharacteristic.forEach((c) => findNSave(device, c, rebootVname));
  }

  Future resetToDefaults(BluetoothDevice device) async {
    this.isReadingOrWriting.value = true;
    await this.customCharacteristic.forEach((c) => findNSave(device, c, resetVname));
    this.isReadingOrWriting.value = false;
  }

//request all settings
  Future requestSettings(BluetoothDevice device) async {
    this.isReadingOrWriting.value = true;
    _write(Map c) {
      // Firmware that wasn't compatable with the app would reboot whenever this command was read.
      if (!this.configAppCompatableFirmware && c["vName"] == saveVname) {
        return;
      }
      try {
        write(device, [0x01, int.parse(c["reference"])]);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
      }
    }

    await this.customCharacteristic.forEach((c) => _write(c));
    this.isReadingOrWriting.value = false;
  }

//request single setting
  Future requestSetting(BluetoothDevice device, String name) async {
    _request(Map c) {
      // Firmware that wasn't compatable with the app would reboot whenever this command was read.
      if (!this.configAppCompatableFirmware && c["vName"] == saveVname) {
        return;
      }
      if (c["vName"] == name) {
        try {
          write(device, [0x01, int.parse(c["reference"])]);
        } catch (e) {
          Snackbar.show(ABC.c, "Failed to request setting $e", success: false);
        }
      } else {
        //skipped
      }
    }

    await this.customCharacteristic.forEach((c) => _request(c));
  }

  int getPrecision(Map c) {
    int precision = 0;
    switch (c["type"]) {
      case "string":
      case "int":
      case "long":
        precision = 0;
        break;
      default:
        precision = 2;
    }
    return precision;
  }

  void writeToSS2K(BluetoothDevice device, Map c, {String s = ""}) {
    //If a specific value wasn't passed, use the previously saved value
    if (s == "") {
      s = c["value"];
    }
    //If the value wasn't read by the firmware, don't try to set it.
    if (s == noFirmSupport) {
      return;
    }

    List<int> value = [0x02, int.parse(c["reference"])];

    switch (c["type"]) {
      case "string":
        value = value + s.codeUnits;
      case "int":
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
        break;
      case "bool":
        (s == "false") ? s = "0" : s = "1";
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
        break;
      case "float":
        int t = (double.parse(s) * 10).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
        break;
      case "long":
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(32).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1)),
          int.parse(out.elementAt(2)),
          int.parse(out.elementAt(3))
        ];
        break;
      default:
      //value = [0xff];
    }
    try {
      write(device, value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  void write(BluetoothDevice device, List<int> value) {
    this.isReadingOrWriting.value = true;
    if (this.getMyCharacteristic(device).device.isConnected) {
      try {
        this.getMyCharacteristic(device).write(value);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
      }
    } else {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k - Net Connected", success: false);
    }
    this.isReadingOrWriting.value = false;
  }

  void decode(BluetoothDevice device) {
    final subscription = this.getMyCharacteristic(device).onValueReceived.listen((value) {
      this.isReadingOrWriting.value = true;
      _subscribed = true;
      if (value[0] == 0x80) {
        var length = value.length;
        var t = new Uint8List(length);
        //
        for (var c in this.customCharacteristic) {
          if (int.parse(c["reference"]) == value[1]) {
            for (var i = 0; i < length; i++) {
              t[i] = value[i];
            }
            var data = t.buffer.asByteData();

            switch (c["type"]) {
              case "int":
                {
                  if (data.lengthInBytes < 4) {
                    c["value"] = noFirmSupport;
                  } else {
                    c["value"] = data.getInt16(2, Endian.little).toString();
                  }
                  break;
                }
              case "bool":
                {
                  String b = (value[2] == 0) ? "false" : "true";
                  c["value"] = b;
                  break;
                }
              case "float":
                {
                  c["value"] = (data.getInt16(2, Endian.little) / 10).toString();
                  break;
                }
              case "long":
                {
                  c["value"] = data.getInt32(2, Endian.little).toString();

                  break;
                }
              case "string":
                {
                  //remove the data bytes
                  var subT = new Uint8List(length - 2);
                  for (int i = 0; i < length - 2; i++) {
                    subT[i] = t[i + 2];
                  }
                  c["value"] = utf8.decode(subT);
                  // Format Found Devices into a JSON String
                  if (c["vName"] == foundDevicesVname) {
                    String _pm = "";
                    String _hrm = "";
                    for (var i in this.customCharacteristic) {
                      if (i["vName"] == connectedHRMVname) {
                        _hrm = i["value"];
                      }
                      if (i["vName"] == connectedPWRVname) {
                        _pm = i["value"];
                      }
                    }
                    String t = c["value"];
                    String tList = "";
                    if (t == " " || t == "null") {
                      t = "";
                    } else {
                      t = t.substring(1, t.length - 1);
                      t += ",";
                    }
                    tList = defaultDevices +
                        t +
                        '"device -5":{"name":"' +
                        _hrm +
                        '","UUID":"0x180d"},"device -6":{"name":"' +
                        _pm +
                        '","UUID":"0x1818"}}]';
                    c["value"] = tList;
                    print(c["value"]);
                  }
                  //Set the firmware version
                  if (c["vName"] == fwVname) this.firmwareVersion = c["value"];
                  break;
                }
              default:
                {
                  String type = c["type"];
                  print("No decoder found for $type");
                }
            }

            break;
          }
        }
      } else if (value[0] == 0xff) {
        for (var c in this.customCharacteristic) {
          if (int.parse(c["reference"]) == value[1]) {
            c["value"] = noFirmSupport;
          }
        }
      }
      this.isReadingOrWriting.value = false;
    });
    device.cancelWhenDisconnected(subscription);
  }
}
