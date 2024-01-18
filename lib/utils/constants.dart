import 'dart:convert';

import 'package:flutter/services.dart';

final String csUUID = "77776277-7877-7774-4466-896665500000";
final String ccUUID = "77776277-7877-7774-4466-896665500001";

final String noFirmSupport = "Not supported by firmware version.";
//Using JSON because it's easier to input the data:
var customCharacteristic = jsonDecode('''[
{"vName": "BLE_firmwareUpdateURL    ", "reference": "0x01", "isSetting": false, "type":"string",  "humanReadableName":"Firmware Update URL", "min":0, "max":0},
{"vName": "BLE_incline              ", "reference": "0x02", "isSetting": false, "type":"float" ,  "humanReadableName":"Current Incline", "min":-30, "max":30},
{"vName": "BLE_simulatedWatts       ", "reference": "0x03", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current Watts", "min":0, "max":2000},
{"vName": "BLE_simulatedHr          ", "reference": "0x04", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current HR", "min":0, "max":2000},
{"vName": "BLE_simulatedCad         ", "reference": "0x05", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current CAD", "min":0, "max":2000},
{"vName": "BLE_simulatedSpeed       ", "reference": "0x06", "isSetting": false, "type":"float" ,  "humanReadableName":"Current Speed", "min":0, "max":2000},
{"vName": "BLE_deviceName           ", "reference": "0x07", "isSetting": true,  "type":"string",  "humanReadableName":"Name of SmartSpin2k", "min":0, "max":0},
{"vName": "BLE_shiftStep            ", "reference": "0x08", "isSetting": true,  "type":"int"   ,  "humanReadableName":"Shift Step", "min":0, "max":2000},
{"vName": "BLE_stepperPower         ", "reference": "0x09", "isSetting": true,  "type":"int"   ,  "humanReadableName":"Stepper Power", "min":0, "max":2000},
{"vName": "BLE_stealthChop          ", "reference": "0x0A", "isSetting": true,  "type":"bool"   ,  "humanReadableName":"Stealth Chop", "min":0, "max":1},
{"vName": "BLE_inclineMultiplier    ", "reference": "0x0B", "isSetting": true,  "type":"float" ,  "humanReadableName":"Incline Multiplier", "min":0, "max":10},
{"vName": "BLE_powerCorrectionFactor", "reference": "0x0C", "isSetting": true,  "type":"int"   ,  "humanReadableName":"Power Correction Factor", "min":0, "max":2000},
{"vName": "BLE_simulateHr           ", "reference": "0x0D", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Simulate HR", "min":0, "max":1},
{"vName": "BLE_simulateWatts        ", "reference": "0x0E", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Simulate Watts", "min":0, "max":1},
{"vName": "BLE_simulateCad          ", "reference": "0x0F", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Simulate CAD", "min":0, "max":1},
{"vName": "BLE_FTMSMode             ", "reference": "0x10", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current FTMS Mode", "min":0, "max":2000},
{"vName": "BLE_autoUpdate           ", "reference": "0x11", "isSetting": true,  "type":"bool"  ,  "humanReadableName":"Auto Updates", "min":0, "max":1},
{"vName": "BLE_ssid                 ", "reference": "0x12", "isSetting": true,  "type":"string",  "humanReadableName":"SSID", "min":0, "max":2000},
{"vName": "BLE_password             ", "reference": "0x13", "isSetting": true,  "type":"string",  "humanReadableName":"Password", "min":0, "max":2000},
{"vName": "BLE_foundDevices         ", "reference": "0x14", "isSetting": false, "type":"string",  "humanReadableName":"Found Devices", "min":0, "max":2000},
{"vName": "BLE_connectedPowerMeter  ", "reference": "0x15", "isSetting": true,  "type":"string",  "humanReadableName":"Saved Power Meter", "min":0, "max":2000},
{"vName": "BLE_connectedHeartMonitor", "reference": "0x16", "isSetting": true,  "type":"string",  "humanReadableName":"Saved HRM", "min":0, "max":2000},
{"vName": "BLE_shifterPosition      ", "reference": "0x17", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current Gear", "min":0, "max":2000},
{"vName": "BLE_saveToLittleFS       ", "reference": "0x18", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Save to Filesystem", "min":0, "max":1},
{"vName": "BLE_targetPosition       ", "reference": "0x19", "isSetting": false, "type":"long"   ,  "humanReadableName":"Target Stepper Position", "min":0, "max":20000},
{"vName": "BLE_externalControl      ", "reference": "0x1A", "isSetting": false, "type":"bool"  ,  "humanReadableName":"External Control", "min":0, "max":1},
{"vName": "BLE_syncMode             ", "reference": "0x1B", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Sync Mode", "min":0, "max":1}
]''');

// the first two bytes are the opacity
final Color activeBackgroundColor = Color(0xffc9ccf5);
final Color deactiveBackgroundColor = Color(0xff686973);
