import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/constants.dart';

bool _subscribed = false;
final _lastRequestStopwatch = Stopwatch();

Future updateCustomCharacter(BluetoothCharacteristic? cc, bool initialScan) async {
  if (cc != null) {
    if (!cc.isNotifying) notify(cc);
    if (!_subscribed) decode(cc);
    if (!_lastRequestStopwatch.isRunning) {
      await requestSettings(cc);
      _lastRequestStopwatch.start();
    } else if (_lastRequestStopwatch.elapsed > Duration(seconds: 5)) {
      _lastRequestStopwatch.reset();
      await requestSettings(cc);
    }
  }
}

void notify(BluetoothCharacteristic cc) {
  if (!cc.isNotifying) {
    try {
      cc.setNotifyValue(true);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to subscribe to notifications", success: false);
    }
  }
}

Future saveSettings(BluetoothCharacteristic cc) async {
  findNSave(Map c) {
    if (c["vName"] == "BLE_saveToLittleFS       ") {
      write(cc, [0x02, int.parse(c["reference"]), 0x01]);
    }
  }

  await customCharacteristic.forEach((c) => findNSave(c));
}

Future requestSettings(BluetoothCharacteristic cc) async {
  _write(Map c) {
    if (c["isSetting"]) {
      //read settings
      write(cc, [0x01, int.parse(c["reference"])]);
    }
  }

  await customCharacteristic.forEach((c) => _write(c));
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

void writeToSS2K(BluetoothCharacteristic cc, Map c, {String s = ""}) {
  if (s == "") {
    s = c["value"];
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
      int t = double.parse(s).round();
      final list = new Uint64List.fromList([t]);
      final bytes = new Uint8List.view(list.buffer);
      final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
      print('bytes: ${out}');
      value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
      break;
    case "float":
      int t = double.parse(s).round();
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

  write(cc, value);
}

void write(BluetoothCharacteristic cc, List<int> value) {
  try {
    cc.write(value);
  } catch (e) {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $value", success: false);
  }
}

void decode(BluetoothCharacteristic cc) {
  final subscription = cc.onValueReceived.listen((value) {
    _subscribed = true;
    if (value[0] == 0x80) {
      var length = value.length;
      var t = new Uint8List(length);
      //
      for (var c in customCharacteristic) {
        if (int.parse(c["reference"]) == value[1]) {
          for (var i = 0; i < length; i++) {
            t[i] = value[i];
          }
          var data = t.buffer.asByteData();

          switch (c["type"]) {
            case "int":
              {
                c["value"] = data.getUint16(2, Endian.little).toString();
                break;
              }
            case "bool":
              {
                c["value"] = value[2].toString();

                break;
              }
            case "float":
              {
                c["value"] = data.getUint16(2, Endian.little).toString();
                break;
              }
            case "long":
              {
                c["value"] = data.getUint32(2, Endian.little).toString();

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
      for (var c in customCharacteristic) {
        if (int.parse(c["reference"]) == value[1]) {
          c["value"] = noFirmSupport;
        }
      }
    }
  });
  //widget.device.cancelWhenDisconnected(subscription);
}
