/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/constants.dart';
import '../utils/bledata.dart';

bool _subscribed = false;
final _lastRequestStopwatch = Stopwatch();
// only used as a flag to prevent multiple concurrent instances of updateCustomCharacter
bool _inUpdateLoop = false;

Future updateCustomCharacter(BLEData bleData, BluetoothDevice device) async {
  if (_inUpdateLoop) {
    return;
  }
  device.requestMtu(515);
  _inUpdateLoop = true;
  if (!bleData.getMyCharacteristic(device).isNotifying) notify(bleData, device);
  if (!_subscribed) decode(bleData, device);
  if (!_lastRequestStopwatch.isRunning) {
    await requestSettings(bleData, device);
    _lastRequestStopwatch.start();
  } else if (_lastRequestStopwatch.elapsed > Duration(seconds: 5)) {
    _lastRequestStopwatch.reset();
    await requestSettings(bleData, device);
  }
  bleData.isReadingOrWriting.value = false;
  _inUpdateLoop = false;
}

void notify(BLEData bleData, BluetoothDevice device) {
  if (!bleData.getMyCharacteristic(device).isNotifying) {
    try {
      bleData.getMyCharacteristic(device).setNotifyValue(true);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to subscribe to notifications", success: false);
    }
  }
}

void findNSave(BLEData bleData, BluetoothDevice device, Map c, String find) {
  // Firmware that wasn't compatable with the app would reboot whenever this command was read.
  if (!bleData.configAppCompatableFirmware && c["vName"] == saveVname) {
    return;
  }
  if (c["vName"] == find) {
    try {
      write(bleData, device, [0x02, int.parse(c["reference"]), 0x01]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }
}

Future saveAllSettings(BLEData bleData, BluetoothDevice device) async {
  bleData.isReadingOrWriting.value = true;
  await bleData.customCharacteristic.forEach((c) => c["isSetting"] ? writeToSS2K(bleData, device, c) : ());
  await bleData.customCharacteristic.forEach((c) => findNSave(bleData, device, c, saveVname));
  bleData.isReadingOrWriting.value = false;
}

Future reboot(BLEData bleData, BluetoothDevice device) async {
  await bleData.customCharacteristic.forEach((c) => findNSave(bleData, device, c, rebootVname));
}

Future resetToDefaults(BLEData bleData, BluetoothDevice device) async {
  bleData.isReadingOrWriting.value = true;
  await bleData.customCharacteristic.forEach((c) => findNSave(bleData, device, c, resetVname));
  bleData.isReadingOrWriting.value = false;
}

//request all settings
Future requestSettings(BLEData bleData, BluetoothDevice device) async {
  bleData.isReadingOrWriting.value = true;
  _write(Map c) {
    // Firmware that wasn't compatable with the app would reboot whenever this command was read.
    if (!bleData.configAppCompatableFirmware && c["vName"] == saveVname) {
      return;
    }
    try {
      write(bleData, device, [0x01, int.parse(c["reference"])]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  await bleData.customCharacteristic.forEach((c) => _write(c));
  bleData.isReadingOrWriting.value = false;
}

//request single setting
Future requestSetting(BLEData bleData, BluetoothDevice device, String name) async {
  _request(Map c) {
    // Firmware that wasn't compatable with the app would reboot whenever this command was read.
    if (!bleData.configAppCompatableFirmware && c["vName"] == saveVname) {
      return;
    }
    if (c["vName"] == name) {
      try {
        write(bleData, device, [0x01, int.parse(c["reference"])]);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to request setting $e", success: false);
      }
    } else {
      //skipped
    }
  }

  await bleData.customCharacteristic.forEach((c) => _request(c));
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

void writeToSS2K(BLEData bleData, BluetoothDevice device, Map c, {String s = ""}) {
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
    write(bleData, device, value);
  } catch (e) {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
  }
}

void write(BLEData bleData, BluetoothDevice device, List<int> value) {
  bleData.isReadingOrWriting.value = true;
  if (bleData.getMyCharacteristic(device).device.isConnected) {
    try {
      bleData.getMyCharacteristic(device).write(value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  } else {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k - Net Connected", success: false);
  }
  bleData.isReadingOrWriting.value = false;
}

void decode(BLEData bleData, BluetoothDevice device) {
  final subscription = bleData.getMyCharacteristic(device).onValueReceived.listen((value) {
    bleData.isReadingOrWriting.value = true;
    _subscribed = true;
    if (value[0] == 0x80) {
      var length = value.length;
      var t = new Uint8List(length);
      //
      for (var c in bleData.customCharacteristic) {
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
                if (c["vName"] == foundDevicesVname) {
                  String _pm = "";
                  String _hrm = "";
                  for (var i in bleData.customCharacteristic) {
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
      for (var c in bleData.customCharacteristic) {
        if (int.parse(c["reference"]) == value[1]) {
          c["value"] = noFirmSupport;
        }
      }
    }
    bleData.isReadingOrWriting.value = false;
  });
  device.cancelWhenDisconnected(subscription);
}

// Future findChar(BLEData bleData, BluetoothDevice device) async {
//   while (!bleData.charReceived) {
//     try {
//       BluetoothService cs = bleData.services.first;
//       for (BluetoothService s in bleData.services) {
//         if (s.uuid == Guid(csUUID)) {
//           cs = s;
//           break;
//         }
//       }
//       List<BluetoothCharacteristic> characteristics = cs.characteristics;
//       for (BluetoothCharacteristic c in characteristics) {
//         if (c.uuid == Guid(ccUUID)) {
//           bleData.getMyCharacteristic(device) = c;
//           break;
//         }
//       }
//       for (BluetoothService s in bleData.services) {
//         if (s.uuid == Guid("4FAFC201-1FB5-459E-8FCC-C5C9C331914B")) {
//           bleData.firmwareService = s;
//           break;
//         }
//       }
//       characteristics = bleData.firmwareService.characteristics;
//       for (BluetoothCharacteristic c in characteristics) {
//         print(c.uuid.toString());
//         if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130005")) {
//           bleData.firmwareDataCharacteristic = c;
//         }
//         if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130003")) {
//           bleData.firmwareControlCharacteristic = c;
//         }
//       }
//       bleData.charReceived = true;
//     } catch (e) {}
//   }
// }
