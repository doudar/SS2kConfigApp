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

void updateCustomCharacter(BluetoothCharacteristic? cc) {
  if (cc != null) {
    notify(cc);
    requestSettings(cc);
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

void writeToSS2K(BluetoothCharacteristic cc, Map c, String s) {
  int t = double.parse(s).round();
  final list = new Uint64List.fromList([t]);
  final bytes = new Uint8List.view(list.buffer);
  final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');

  print('bytes: ${out}');
  List<int> value = [
    0x02,
    int.parse(c["reference"]),
    int.parse(out.elementAt(0)), int.parse(out.elementAt(1)) 
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
      String logString = "";
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
                c["value"] = data.getUint16(2, Endian.little);
                logString = c["value"].toString();
                break;
              }
            case "bool":
              {
                c["value"] = value[2];
                logString = c["value"].toString();
                break;
              }
            case "float":
              {
                c["value"] = data.getUint16(2, Endian.little);
                logString = c["value"].toString();
                break;
              }
            case "long":
              {
                c["value"] = data.getUint32(2, Endian.little);
                logString = c["value"].toString();
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
                logString = c["value"].toString();
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

      print("Received value: $logString");
    } else if (value[0] == 0xff) {
      for (var c in customCharacteristic) {
        if (int.parse(c["reference"]) == value[1]) {
          c["value"] = "Not supported by firmware version.";
        }
      }
    }
  });
  //widget.device.cancelWhenDisconnected(subscription);
}
