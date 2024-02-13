import 'dart:convert';

import 'package:flutter/services.dart';

final String csUUID = "77776277-7877-7774-4466-896665500000";
final String ccUUID = "77776277-7877-7774-4466-896665500001";

final String noFirmSupport = "Not supported by firmware version.";
final String passwordVname = "BLE_password             ";
final String saveVname = "BLE_saveToLittleFS       ";
final String foundDevicesVname = "BLE_foundDevices         ";
final String connectedHRMVname = "BLE_connectedHeartMonitor";
final String connectedPWRVname = "BLE_connectedPowerMeter  ";
final String rebootVname = "BLE_reboot               ";
final String resetVname = "BLE_resetToDefaults      ";
final String shiftVname = "BLE_shifterPosition      ";

String defaultDevices =
    '''[{"device -4": {"name": "any", "UUID": "0x180d"},"device -3": {"name": "none", "UUID": "0x180d"},"device -2": {"name": "any", "UUID": "0x1818"},"device -1": {"name": "none", "UUID": "0x1818"},''';

//Using JSON because it's easier to input the data.
//These are shuffled so they are built in a preferred order so most used settings are on top
var customCharacteristicFramework = jsonDecode('''[
{"vName": "BLE_connectedPowerMeter  ", "reference": "0x15", "isSetting": true,  "type":"string",  "humanReadableName":"Saved Power Meter", "min":0, "max":2000},
{"vName": "BLE_connectedHeartMonitor", "reference": "0x16", "isSetting": true,  "type":"string",  "humanReadableName":"Saved HRM", "min":0, "max":2000},
{"vName": "BLE_foundDevices         ", "reference": "0x14", "isSetting": false, "type":"string",  "humanReadableName":"Found Devices", "min":0, "max":2000},
{"vName": "BLE_shiftStep            ", "reference": "0x08", "isSetting": true,  "type":"int"   ,  "humanReadableName":"Shift Step", "min":100, "max":2000},
{"vName": "BLE_shiftDir             ", "reference": "0x20", "isSetting": true,  "type":"bool"   ,  "humanReadableName":"Shifter Direction", "min":0, "max":1},
{"vName": "BLE_inclineMultiplier    ", "reference": "0x0B", "isSetting": true,  "type":"float" ,  "humanReadableName":"Incline Multiplier", "min":0, "max":10},
{"vName": "BLE_ERGSensitivity       ", "reference": "0x1F", "isSetting": true,  "type":"float" ,  "humanReadableName":"ERG Sensitivity", "min":0, "max":10},
{"vName": "BLE_firmwareUpdateURL    ", "reference": "0x01", "isSetting": false, "type":"string",  "humanReadableName":"Firmware Update URL", "min":0, "max":0},
{"vName": "BLE_incline              ", "reference": "0x02", "isSetting": false, "type":"float" ,  "humanReadableName":"Current Incline", "min":-30, "max":30},
{"vName": "BLE_simulatedWatts       ", "reference": "0x03", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current Watts", "min":0, "max":2000},
{"vName": "BLE_simulatedHr          ", "reference": "0x04", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current HR", "min":0, "max":2000},
{"vName": "BLE_simulatedCad         ", "reference": "0x05", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current CAD", "min":0, "max":2000},
{"vName": "BLE_simulatedSpeed       ", "reference": "0x06", "isSetting": false, "type":"float" ,  "humanReadableName":"Current Speed", "min":0, "max":2000},
{"vName": "BLE_deviceName           ", "reference": "0x07", "isSetting": true,  "type":"string",  "humanReadableName":"Name of SmartSpin2k", "min":0, "max":0},
{"vName": "BLE_stepperPower         ", "reference": "0x09", "isSetting": true,  "type":"int"   ,  "humanReadableName":"Stepper Power", "min":0, "max":2000},
{"vName": "BLE_stealthChop          ", "reference": "0x0A", "isSetting": true,  "type":"bool"  ,  "humanReadableName":"Stealth Chop", "min":0, "max":1},
{"vName": "BLE_powerCorrectionFactor", "reference": "0x0C", "isSetting": true,  "type":"float" ,  "humanReadableName":"Power Correction Factor", "min":0.4, "max":2.0},
{"vName": "BLE_simulateHr           ", "reference": "0x0D", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Simulate HR", "min":0, "max":1},
{"vName": "BLE_simulateWatts        ", "reference": "0x0E", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Simulate Watts", "min":0, "max":1},
{"vName": "BLE_simulateCad          ", "reference": "0x0F", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Simulate CAD", "min":0, "max":1},
{"vName": "BLE_FTMSMode             ", "reference": "0x10", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current FTMS Mode", "min":0, "max":2000},
{"vName": "BLE_autoUpdate           ", "reference": "0x11", "isSetting": true,  "type":"bool"  ,  "humanReadableName":"Auto Updates", "min":0, "max":1},
{"vName": "BLE_ssid                 ", "reference": "0x12", "isSetting": true,  "type":"string",  "humanReadableName":"SSID", "min":0, "max":2000},
{"vName": "BLE_password             ", "reference": "0x13", "isSetting": true,  "type":"string",  "humanReadableName":"Password", "min":0, "max":2000},
{"vName": "BLE_shifterPosition      ", "reference": "0x17", "isSetting": false, "type":"int"   ,  "humanReadableName":"Current Gear", "min":0, "max":2000},
{"vName": "BLE_saveToLittleFS       ", "reference": "0x18", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Save to Filesystem", "min":0, "max":1},
{"vName": "BLE_targetPosition       ", "reference": "0x19", "isSetting": false, "type":"long"  ,  "humanReadableName":"Target Stepper Position", "min":0, "max":20000},
{"vName": "BLE_externalControl      ", "reference": "0x1A", "isSetting": false, "type":"bool"  ,  "humanReadableName":"External Control", "min":0, "max":1},
{"vName": "BLE_stepperSpeed         ", "reference": "0x1E", "isSetting": true,  "type":"int"   ,  "humanReadableName":"Stepper Motor Speed", "min":100, "max":10000},
{"vName": "BLE_syncMode             ", "reference": "0x1B", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Sync Mode", "min":0, "max":1},
{"vName": "BLE_reboot               ", "reference": "0x1C", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Reboot SmartSpin2k", "min":0, "max":1},
{"vName": "BLE_resetToDefaults      ", "reference": "0x1D", "isSetting": false, "type":"bool"  ,  "humanReadableName":"Reset to defaults", "min":0, "max":1}
]''');

// the first two bytes are the opacity
final Color activeBackgroundColor = Color(0xffc9ccf5);
final Color deactiveBackgroundColor = Color(0xff686973);
