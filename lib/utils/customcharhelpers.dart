import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

void findNSave(BluetoothCharacteristic cc, Map c, String find) {
  if (c["vName"] == find) {
    try {
      write(cc, [0x02, int.parse(c["reference"]), 0x01]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }
}

Future saveAllSettings(BluetoothCharacteristic cc) async {
  await customCharacteristic.forEach((c) => c["isSetting"] ? writeToSS2K(cc, c) : ());
  await customCharacteristic.forEach((c) => findNSave(cc, c, saveVname));
}

Future reboot(BluetoothCharacteristic cc) async {
  await customCharacteristic.forEach((c) => findNSave(cc, c, rebootVname));
}

Future resetToDefaults(BluetoothCharacteristic cc) async {
  await customCharacteristic.forEach((c) => findNSave(cc, c, resetVname));
}

Future requestSettings(BluetoothCharacteristic cc) async {
  _write(Map c) {
    try {
      write(cc, [0x01, int.parse(c["reference"])]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
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
    write(cc, value);
  } catch (e) {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
  }
}

void write(BluetoothCharacteristic cc, List<int> value) {
  try {
    cc.write(value);
  } catch (e) {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
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
                String b = (value[2] == 0) ? "false" : "true";
                c["value"] = b;
                break;
              }
            case "float":
              {
                c["value"] = (data.getUint16(2, Endian.little) / 10).toString();
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
                if (c["vName"] == foundDevicesVname) {
                  String _pm = "";
                  String _hrm = "";
                  for (var i in customCharacteristic) {
                    if (i["vName"] == connectedHRMVname) {
                      _hrm = i["value"];
                    }
                    if (i["vName"] == connectedPWRVname) {
                      _pm = i["value"];
                    }
                  }
                  String t = c["value"];
                  String tList = "";
                  if (t == " ") {
                    t = "";
                  } else {
                    t = t.substring(1, t.length - 1);
                    t += ",";
                  }
                  tList = defaultDevices +
                      t +
                      '"device -5": {"name":"' +
                      _hrm +
                      '", "UUID": "0x180d"}, "device -6": {"name":"' +
                      _pm +
                      '", "UUID": "0x1818"}' +
                      '}]';
                  c["value"] = tList;
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
      for (var c in customCharacteristic) {
        if (int.parse(c["reference"]) == value[1]) {
          c["value"] = noFirmSupport;
        }
      }
    }
  });
  //widget.device.cancelWhenDisconnected(subscription);
}
