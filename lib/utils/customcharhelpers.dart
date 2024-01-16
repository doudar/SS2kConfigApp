import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/snackbar.dart';
import '../utils/constants.dart';

/* String readCC(Map c) {
    while (c["value"] == null) {
      sleep(const Duration(milliseconds: 50));
    }
    return (c["value"].toString());
  }*/

Future updateCustomCharacter(BluetoothCharacteristic? cc, bool initialScan) async {
  if (cc != null) {
    notify(cc);
    if (initialScan && (customCharacteristic[0]["value"] == null)) {
      requestSettings(cc);
    }
    decode(cc);
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

void requestSettings(BluetoothCharacteristic cc) {
  _write(Map c) {
    if (c["isSetting"]) {
      //read settings
      write(cc, [0x01, int.parse(c["reference"])]);
    }
  }

  customCharacteristic.forEach((c) => _write(c));
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

  int t = double.parse(s).round();
  final list = new Uint64List.fromList([t]);
  final bytes = new Uint8List.view(list.buffer);
  final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');

  print('bytes: ${out}');
  List<int> value = [
    0x02,
    int.parse(c["reference"]),
    int.parse(out.elementAt(0)),
    int.parse(out.elementAt(1))
  ]; //////////<<<<<<<<<<<This (s) needs to probably be converted to uint8 before sending.
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
            case "String":
              {
                List<int> reversed = value.reversed.toList();
                reversed.removeRange(length - 2, length);
                try {
                  c["value"] = utf8.decode(reversed);
                } catch (e) {
                  Snackbar.show(ABC.c, "Failed to decode string", success: false);
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
