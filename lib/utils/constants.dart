import 'dart:convert';

final String csUUID = "77776277-7877-7774-4466-896665500000";
final String ccUUID = "77776277-7877-7774-4466-896665500001";
//Using JSON because it's easier to input the data:
var customCharacteristic = jsonDecode('''[
{"vName": "BLE_firmwareUpdateURL    ", "reference": "0x01", "isSetting": false, "type":"string",  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_incline              ", "reference": "0x02", "isSetting": false, "type":"float" ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_simulatedWatts       ", "reference": "0x03", "isSetting": false, "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_simulatedHr          ", "reference": "0x04", "isSetting": false, "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_simulatedCad         ", "reference": "0x05", "isSetting": false, "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_simulatedSpeed       ", "reference": "0x06", "isSetting": false, "type":"float" ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_deviceName           ", "reference": "0x07", "isSetting": true,  "type":"string",  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_shiftStep            ", "reference": "0x08", "isSetting": true,  "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_stepperPower         ", "reference": "0x09", "isSetting": true,  "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_stealthChop          ", "reference": "0x0A", "isSetting": true,  "type":"bool"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_inclineMultiplier    ", "reference": "0x0B", "isSetting": true,  "type":"float" ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_powerCorrectionFactor", "reference": "0x0C", "isSetting": true,  "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_simulateHr           ", "reference": "0x0D", "isSetting": false, "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_simulateWatts        ", "reference": "0x0E", "isSetting": false, "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_simulateCad          ", "reference": "0x0F", "isSetting": false, "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_FTMSMode             ", "reference": "0x10", "isSetting": false, "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_autoUpdate           ", "reference": "0x11", "isSetting": true,  "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_ssid                 ", "reference": "0x12", "isSetting": true,  "type":"string",  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_password             ", "reference": "0x13", "isSetting": true,  "type":"string",  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_foundDevices         ", "reference": "0x14", "isSetting": false, "type":"string",  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_connectedPowerMeter  ", "reference": "0x15", "isSetting": true,  "type":"string",  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_connectedHeartMonitor", "reference": "0x16", "isSetting": true,  "type":"string",  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_shifterPosition      ", "reference": "0x17", "isSetting": false, "type":"int"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_saveToLittleFS       ", "reference": "0x18", "isSetting": false,  "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_targetPosition       ", "reference": "0x19", "isSetting": false, "type":"long"   ,  "humanReadableName":"", "min":0, "max":2000},
{"vName": "BLE_externalControl      ", "reference": "0x1A", "isSetting": false, "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""},
{"vName": "BLE_syncMode             ", "reference": "0x1B", "isSetting": false, "type":"bool"  ,  "humanReadableName":"", "min":0, "max":""}
]''');
