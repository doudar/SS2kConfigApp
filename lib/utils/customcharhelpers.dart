import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:SS2kConfigApp/utils/extra.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/constants.dart';

bool _subscribed = false;
final _lastRequestStopwatch = Stopwatch();

Future updateCustomCharacter(BLEData bleData, bool initialScan) async {
  bleData.isReadingOrWriting.value= true;
  if (!bleData.myCharacteristic.isNotifying) notify(bleData);
  if (!_subscribed) decode(bleData);
  if (!_lastRequestStopwatch.isRunning) {
    await requestSettings(bleData);
    _lastRequestStopwatch.start();
  } else if (_lastRequestStopwatch.elapsed > Duration(seconds: 5)) {
    _lastRequestStopwatch.reset();
    await requestSettings(bleData);
  }
  bleData.isReadingOrWriting.value= false;
}

void notify(BLEData bleData) {
  if (!bleData.myCharacteristic.isNotifying) {
    try {
      bleData.myCharacteristic.setNotifyValue(true);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to subscribe to notifications", success: false);
    }
  }
}

void findNSave(BLEData bleData, Map c, String find) {
  if (c["vName"] == find) {
    try {
      write(bleData, [0x02, int.parse(c["reference"]), 0x01]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }
}

Future saveAllSettings(BLEData bleData) async {
  bleData.isReadingOrWriting.value= true;
  await bleData.customCharacteristic.forEach((c) => c["isSetting"] ? writeToSS2K(bleData, c) : ());
  await bleData.customCharacteristic.forEach((c) => findNSave(bleData, c, saveVname));
  bleData.isReadingOrWriting.value= false;
}

Future reboot(BLEData bleData) async {
  await bleData.customCharacteristic.forEach((c) => findNSave(bleData, c, rebootVname));
}

Future resetToDefaults(BLEData bleData) async {
  bleData.isReadingOrWriting.value= true;
  await bleData.customCharacteristic.forEach((c) => findNSave(bleData, c, resetVname));
  bleData.isReadingOrWriting.value= false;
}

//request all settings
Future requestSettings(BLEData bleData) async {
  bleData.isReadingOrWriting.value= true;
  _write(Map c) {
    try {
      write(bleData, [0x01, int.parse(c["reference"])]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  await bleData.customCharacteristic.forEach((c) => _write(c));
  bleData.isReadingOrWriting.value= false;
}

//request single setting
Future requestSetting(BLEData bleData, String name) async {
  _request(Map c) {
    if (c["vName"] == name) {
      try {
        write(bleData, [0x01, int.parse(c["reference"])]);
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

void writeToSS2K(BLEData bleData, Map c, {String s = ""}) {
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
    write(bleData, value);
  } catch (e) {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
  }
}

void write(BLEData bleData, List<int> value) {
  if (bleData.myCharacteristic.device.isConnected) {
    try {
      bleData.myCharacteristic.write(value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  } else {
    Snackbar.show(ABC.c, "Failed to write to SmartSpin2k - Net Connected", success: false);
  }
}

void decode(BLEData bleData) {
  final subscription = bleData.myCharacteristic.onValueReceived.listen((value) {
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
                c["value"] = data.getInt16(2, Endian.little).toString();
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
  });
  //widget.device.cancelWhenDisconnected(subscription);
}
