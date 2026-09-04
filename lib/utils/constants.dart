/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter/material.dart';

import 'ble_sensor_services.dart';

enum SettingType {
  basic,
  bluetooth,
  network,
  advanced;

  Color get color {
    switch (this) {
      case SettingType.basic:
        return Colors.green;
      case SettingType.bluetooth:
        return Colors.blue;
      case SettingType.network:
        return Colors.orange;
      case SettingType.advanced:
        return Colors.red;
    }
  }
}

// Constants
const int INT32_MIN = -2147483648;
const double MIN_POWER_RANGE = 900.0; // Minimum watts range for power table
const double MIN_RESISTANCE_RANGE =
    2000.0; // Minimum resistance range for power table

final String csUUID = "77776277-7877-7774-4466-896665500000";
final String ccUUID = "77776277-7877-7774-4466-896665500001";

const String ftmsServiceUUID = bleFitnessMachineServiceUuid128;
final String ftmsControlPointUUID = "00002AD9-0000-1000-8000-00805f9b34fb";
final String ftmsIndoorBikeDataUUID = "00002AD2-0000-1000-8000-00805f9b34fb";

final Color activeBackgroundColor = Color(0xffc9ccf5);
final Color deactiveBackgroundColor = Color.fromARGB(255, 90, 91, 100);

// String that's inserted if the response from the server is not supported.
final String noFirmSupport = "Not supported by firmware version.";

// Any and None selections pre-formatted so they can be appended to the JSON from the SmartSpin2k easily.
String defaultDevices =
    '''[{"device -4": {"name": "any", "UUID": "$bleHeartRateDeviceUuid"},"device -3": {"name": "none", "UUID": "$bleHeartRateDeviceUuid"},"device -2": {"name": "any", "UUID": "$bleCyclingPowerDeviceUuid"},"device -1": {"name": "none", "UUID": "$bleCyclingPowerDeviceUuid"},''';

// Defining vName variables directly for easier editing
final String passwordVname = "BLE_password";
final String saveVname = "BLE_saveToLittleFS";
final String foundDevicesVname = "BLE_foundDevices";
final String connectedHRMVname = "BLE_connectedHeartMonitor";
final String connectedPWRVname = "BLE_connectedPowerMeter";
final String rebootVname = "BLE_reboot";
final String resetVname = "BLE_resetToDefaults";
final String fwVname = "BLE_firmwareVer";
final String hardwareVersionVname = "BLE_hardwareVersion";
final String restartBLEVname = "BLE_restartBLE";
final String shiftStepVname = "BLE_shiftStep";
final String shiftDirVname = "BLE_shiftDir";
final String inclineMultiplierVname = "BLE_inclineMultiplier";
final String ERGSensitivityVname = "BLE_ERGSensitivity";
final String firmwareUpdateURLVname = "BLE_firmwareUpdateURL";
final String inclineVname = "BLE_incline";
final String simulatedWattsVname = "BLE_simulatedWatts";
final String simulatedHrVname = "BLE_simulatedHr";
final String simulatedCadVname = "BLE_simulatedCad";
final String simulatedSpeedVname = "BLE_simulatedSpeed";
final String deviceNameVname = "BLE_deviceName";
final String stepperPowerVname = "BLE_stepperPower";
final String stealthChopVname = "BLE_stealthChop";
final String powerCorrectionFactorVname = "BLE_powerCorrectionFactor";
final String simulateHrVname = "BLE_simulateHr";
final String simulateWattsVname = "BLE_simulateWatts";
final String simulateCadVname = "BLE_simulateCad";
final String FTMSModeVname = "BLE_FTMSMode";
final String autoUpdateVname = "BLE_autoUpdate";
final String ssidVname = "BLE_ssid";
final String shifterPositionVname = "BLE_shifterPosition";
final String targetPositionVname = "BLE_targetPosition";
final String externalControlVname = "BLE_externalControl";
final String stepperSpeedVname = "BLE_stepperSpeed";
final String syncModeVname = "BLE_syncMode";
final String minBrakeWattsVname = "BLE_minBrakeWatts";
final String maxBrakeWattsVname = "BLE_maxBrakeWatts";
final String scanBLEVname = "BLE_scanBLE";
final String resetPowerTableVname = "BLE_resetPowerTable";
final String powerTableDataVname = "BLE_powerTableData";
final String simulatedTargetWattsVname = "BLE_simulatedTargetWatts";
final String simulateTargetWattsVname = "BLE_simulateTargetWatts";
final String BLE_hMinVname = "BLE_homingMin";
final String BLE_hMaxVname = "BLE_homingMax";
final String homingSensitivityVname = "BLE_homingSensitivity";
final String pTab4pwrVname = "BLE_pTab4pwr";
final String BLE_logStreamVname = "BLE_BLELogging";

/// Returns a deep copy of the characteristic framework so each DeviceData
/// instance gets its own independent mutable state.
List<Map<String, dynamic>> createCustomCharacteristicFramework() {
  return customCharacteristicFramework
      .map<Map<String, dynamic>>((c) => Map<String, dynamic>.from(c as Map))
      .toList();
}

/// The firmware snapshot normally uses the characteristic vName without its
/// `BLE_` prefix. A descriptor can provide `settingsSnapshotKey` only when a
/// legacy firmware JSON key does not follow that convention.
String? settingsSnapshotKeyForCharacteristic(Map characteristic) {
  final override = characteristic['settingsSnapshotKey'];
  if (override is String) return override;

  final vName = characteristic['vName']?.toString();
  if (vName == null || !vName.startsWith('BLE_')) return null;
  return vName.substring(4);
}

/// Resolves snapshot JSON through the canonical characteristic descriptors.
/// New conventionally named characteristics need no snapshot-specific entry.
Map<int, dynamic> settingsSnapshotValuesByReference(
  Map<String, dynamic> snapshot,
  Iterable<Map> characteristics,
) {
  final referencesByKey = <String, int>{};
  for (final characteristic in characteristics) {
    final key = settingsSnapshotKeyForCharacteristic(characteristic);
    final referenceText = characteristic['reference']?.toString();
    if (key == null || referenceText == null) continue;

    final reference = int.parse(referenceText);
    final previous = referencesByKey[key];
    if (previous != null && previous != reference) {
      throw StateError('Duplicate settings snapshot key: $key');
    }
    referencesByKey[key] = reference;
  }

  return <int, dynamic>{
    for (final entry in snapshot.entries)
      if (referencesByKey[entry.key] case final reference?)
        reference: entry.value,
  };
}

// Refactored customCharacteristicFramework to directly use Dart map
final dynamic customCharacteristicFramework = [
  {
    "vName": hardwareVersionVname,
    "reference": "0x2F",
    "isSetting": false,
    "settingType": SettingType.basic,
    "type": "string",
    "humanReadableName": "Hardware Version",
    "min": 0,
    "max": 2000,
    "textDescription":
        "The device hardware revision used for firmware selection.",
    "defaultData": "Revision Two",
  },
  {
    "vName": fwVname,
    "reference": "0x25",
    "settingsSnapshotKey": "firmwareVersion",
    "isSetting": false,
    "settingType": SettingType.basic,
    "type": "string",
    "humanReadableName": "Firmware Version",
    "min": 0,
    "max": 2000,
    "textDescription": "The current loaded firmware.",
    "defaultData": "SmartSpin2k",
  },
  {
    "vName": connectedPWRVname,
    "reference": "0x15",
    "isSetting": true,
    "settingType": SettingType.bluetooth,
    "type": "string",
    "humanReadableName": "Saved Power Meter",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Select your Power Meter from the list. \n Device Not showing up? Check that it's not connected to anything else and press scan again.",
    "defaultData": "any",
  },
  {
    "vName": connectedHRMVname,
    "reference": "0x16",
    "isSetting": true,
    "settingType": SettingType.bluetooth,
    "type": "string",
    "humanReadableName": "Saved HRM",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Select your Heart Rate Monitor from the list. \n Device Not showing up? Check that it's not connected to anything else and press scan again.",
    "defaultData": "any",
  },
  {
    "vName": foundDevicesVname,
    "reference": "0x14",
    "isSetting": false,
    "settingType": SettingType.bluetooth,
    "type": "string",
    "humanReadableName": "Found Devices",
    "min": 0,
    "max": 2000,
    "textDescription": "The following devices have been found",
    "defaultData":
        "[{\"device 0\":{\"name\":\"Polar OH1 B9B6D624 d6\",\"UUID\":\"$bleHeartRateDeviceUuid\"},\"device 1\":{\"name\":\"Wahoo Kicker\",\"UUID\":\"$bleCyclingPowerDeviceUuid\"} }]",
  },
  {
    "vName": shiftStepVname,
    "reference": "0x08",
    "isSetting": true,
    "settingType": SettingType.basic,
    "type": "int",
    "humanReadableName": "Shift Step",
    "min": 10,
    "max": 6000,
    "textDescription":
        "This setting controls how much each click of the shifter turns the dial. The ideal setting is different for each bike and person. Try aiming for a +/- 30 watt change when you click the shifter. Higher values will turn the knob further.",
    "defaultData": "1500",
  },
  {
    "vName": shiftDirVname,
    "reference": "0x20",
    "isSetting": true,
    "settingType": SettingType.basic,
    "type": "bool",
    "humanReadableName": "Swap Shifter Direction",
    "min": 0,
    "max": 1,
    "textDescription":
        "This setting controls which shifter button is up and which is down. Toggle this if you need to invert the direction of the shifters.",
    "defaultData": "true",
  },
  {
    "vName": saveVname,
    "reference": "0x18",
    "isSetting": false,
    "settingType": SettingType.basic,
    "type": "bool",
    "humanReadableName": "Save to SmartSpin2k",
    "min": 0,
    "max": 1,
    "textDescription": "Saves all of the configuration to the filesystem",
    "defaultData": "false",
  },
  {
    "vName": inclineMultiplierVname,
    "reference": "0x0B",
    "isSetting": true,
    "settingType": SettingType.basic,
    "type": "float",
    "humanReadableName": "Incline Multiplier",
    "min": 0,
    "max": 10,
    "textDescription":
        "This setting affects how much you will feel the impact of hills in sim mode rides. Pick the setting which feels most realistic to you. Higher values will make hills feel steeper while lower values will flatten out the hills.",
    "defaultData": "5.0",
  },
  {
    "vName": ERGSensitivityVname,
    "reference": "0x1F",
    "isSetting": true,
    "settingType": SettingType.basic,
    "type": "float",
    "humanReadableName": "ERG Sensitivity",
    "min": 0,
    "max": 20,
    "textDescription":
        "This setting will impact the sensitivity of Erg Mode. Too low will cause the Erg to be slow at reaching target wattage. Too high will cause it to overshoot and oscillate before settling. Start with the default value of 5 and adjust if necessary.",
    "defaultData": "5.0",
  },
  {
    "vName": firmwareUpdateURLVname,
    "reference": "0x01",
    "isSetting": false,
    "settingType": SettingType.network,
    "type": "string",
    "humanReadableName": "Firmware Update URL",
    "min": 0,
    "max": 0,
    "textDescription": "URL for firmware updates.",
    "defaultData": "https://raw.githubusercontent.com/doudar/OTAUpdates/main/",
  },
  {
    "vName": inclineVname,
    "reference": "0x02",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "float",
    "humanReadableName": "Current Incline",
    "min": -30,
    "max": 30,
    "textDescription": "The incline requested by your training program.",
    "defaultData": "0.0",
  },
  {
    "vName": simulatedWattsVname,
    "reference": "0x03",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Current Watts",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current watts output.",
    "defaultData": "0",
  },
  {
    "vName": simulatedHrVname,
    "reference": "0x04",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Current HR",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current heart rate.",
    "defaultData": "0",
  },
  {
    "vName": simulatedTargetWattsVname,
    "reference": "0x28",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Current TW",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current target watts.",
    "defaultData": "0",
  },
  {
    "vName": simulatedCadVname,
    "reference": "0x05",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Current CAD",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current cadence.",
    "defaultData": "0",
  },
  {
    "vName": simulatedSpeedVname,
    "reference": "0x06",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "float",
    "humanReadableName": "Current Speed",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current speed.",
    "defaultData": "0",
  },
  {
    "vName": deviceNameVname,
    "reference": "0x07",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "string",
    "humanReadableName": "Name of SmartSpin2k",
    "min": 0,
    "max": 0,
    "textDescription":
        "Set the name for your SmartSpin2k device. This will also change the URL of the device on the local network to yourName.local",
    "defaultData": "SmartSpin2k",
  },
  {
    "vName": stepperPowerVname,
    "reference": "0x09",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Stepper Power",
    "min": 100,
    "max": 2000,
    "textDescription":
        "Adjust this setting if you are experiencing overheat issues or if you need additional torque for a felt resistance bike. Do not exceed your power supply's rated limits.",
    "defaultData": "900",
  },
  {
    "vName": stealthChopVname,
    "reference": "0x0A",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Stealth Chop",
    "min": 0,
    "max": 1,
    "textDescription":
        "This silences the stepper motor. Leave it on unless it is causing issues. Turning it off may provide some additional torque if you have a felt resistance bike.",
    "defaultData": "true",
  },
  {
    "vName": powerCorrectionFactorVname,
    "reference": "0x0C",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "float",
    "humanReadableName": "Power Correction Factor",
    "min": 0.4,
    "max": 2.5,
    "textDescription":
        "Increase or decrease this setting to correct the power reported from your bike. This is typically only needed if your bike is over or under reporting power by a significant amount. IC4/C6 users may want to try a value around 0.7 to .8",
    "defaultData": "1.0",
  },
  {
    "vName": simulateHrVname,
    "reference": "0x0D",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Simulate HR",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated heart rate monitor data.",
    "defaultData": "false",
  },
  {
    "vName": simulateWattsVname,
    "reference": "0x0E",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Simulate Watts",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated power meter data.",
    "defaultData": "false",
  },
  {
    "vName": simulateTargetWattsVname,
    "reference": "0x29",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Simulate Target Watts",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated target watts meter data.",
    "defaultData": "false",
  },
  {
    "vName": simulateCadVname,
    "reference": "0x0F",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Simulate CAD",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated cadence sensor data.",
    "defaultData": "false",
  },
  {
    "vName": FTMSModeVname,
    "reference": "0x10",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Current FTMS Mode",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Current mode of the Fitness Machine Service (FTMS) profile.",
    "defaultData": "0",
  },
  {
    "vName": autoUpdateVname,
    "reference": "0x11",
    "isSetting": true,
    "settingType": SettingType.network,
    "type": "bool",
    "humanReadableName": "Auto Updates",
    "min": 0,
    "max": 1,
    "textDescription":
        "Toggle to enable or disable automatic firmware updates.",
    "defaultData": "true",
  },
  {
    "vName": ssidVname,
    "reference": "0x12",
    "isSetting": true,
    "settingType": SettingType.network,
    "type": "string",
    "humanReadableName": "WiFi SSID (2.4 Ghz)",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Enter the SSID of a 2.4GHz WiFi network to access SmartSpin2k settings over WiFi. If it doesn't connect, it will start and access point with the device name.",
    "defaultData": "SmartSpin2k",
  },
  {
    "vName": passwordVname,
    "reference": "0x13",
    "isSetting": true,
    "settingType": SettingType.network,
    "type": "string",
    "humanReadableName": "WiFi Password",
    "min": 0,
    "max": 2000,
    "textDescription": "Enter your WiFi password.",
    "defaultData": "password",
  },
  {
    "vName": shifterPositionVname,
    "reference": "0x17",
    "isSetting": false,
    "settingType": SettingType.basic,
    "type": "int",
    "humanReadableName": "Current Gear",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current gear.",
    "defaultData": "0",
  },
  {
    "vName": targetPositionVname,
    "reference": "0x19",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "long",
    "humanReadableName": "Target Stepper Position",
    "min": 0,
    "max": 20000,
    "textDescription": "The target position for the stepper motor.",
    "defaultData": "0",
  },
  {
    "vName": externalControlVname,
    "reference": "0x1A",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "External Control",
    "min": 0,
    "max": 1,
    "textDescription": "Indicates if the device is under external control.",
    "defaultData": "false",
  },
  {
    "vName": stepperSpeedVname,
    "reference": "0x1E",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Stepper Motor Speed",
    "min": 100,
    "max": 3500,
    "textDescription":
        "Adjust the motor speed. The default setting is adequate for the majority of users.",
    "defaultData": "1500",
  },
  {
    "vName": syncModeVname,
    "reference": "0x1B",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Sync Mode",
    "min": 0,
    "max": 1,
    "textDescription": "Indicates if the device is in sync mode.",
    "defaultData": "0",
  },
  {
    "vName": minBrakeWattsVname,
    "reference": "0x21",
    "settingsSnapshotKey": "minWatts",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Min Brake Watts",
    "min": 0,
    "max": 200,
    "textDescription":
        "Minimum amount of resistance you can pedal without hitting the low limit stop on your bike.",
    "defaultData": "50",
  },
  {
    "vName": maxBrakeWattsVname,
    "reference": "0x22",
    "settingsSnapshotKey": "maxWatts",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Max Brake Watts",
    "min": 0,
    "max": 2500,
    "textDescription":
        "Maximum amount of resistance you can pedal without hitting the high limit stop on your bike.",
    "defaultData": "1000",
  },
  {
    "vName": restartBLEVname,
    "reference": "0x23",
    "isSetting": false,
    "settingType": SettingType.bluetooth,
    "type": "bool",
    "humanReadableName": "Reconnect Devices",
    "min": 0,
    "max": 1,
    "textDescription":
        "Disconnect the BLE devices (scan will then happen along with reconnect).",
    "defaultData": "false",
  },
  {
    "vName": scanBLEVname,
    "reference": "0x24",
    "isSetting": false,
    "settingType": SettingType.bluetooth,
    "type": "bool",
    "humanReadableName": "BLE Scan",
    "min": 0,
    "max": 1,
    "textDescription":
        "Scan for BLE devices. Scanning is automatic (not needed to be used) unless all devices are connected.",
    "defaultData": "false",
  },
  {
    "vName": rebootVname,
    "reference": "0x1C",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Reboot",
    "min": 0,
    "max": 1,
    "textDescription": "Reboots The SmartSpin2k",
    "defaultData": "false",
  },
  {
    "vName": resetVname,
    "reference": "0x1D",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Reset to defaults",
    "min": 0,
    "max": 1,
    "textDescription": "Reset the SmartSpin2k to defaults",
    "defaultData": "false",
  },
  {
    "vName": resetPowerTableVname,
    "reference": "0x26",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Delete the PowerTable",
    "min": 0,
    "max": 1,
    "textDescription": "Delete the active and saved power table",
    "defaultData": "false",
  },
  {
    "vName": powerTableDataVname,
    "reference": "0x27",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "powerTableData",
    "humanReadableName": "Power Table Data",
    "min": -32768,
    "max": 32768,
    "textDescription": "Read or Write Data to the Power Table",
    "defaultData": "false",
  },
  {
    "vName": simulatedTargetWattsVname,
    "reference": "0x28",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Target Watts",
    "min": 0,
    "max": 2000,
    "textDescription": "Your target watt output.",
    "defaultData": "0",
  },
  {
    "vName": simulateTargetWattsVname,
    "reference": "0x29",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Target Simulate Watts",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated target watt data.",
    "defaultData": "false",
  },
  {
    "vName": BLE_hMinVname,
    "reference": "0x2A",
    "settingsSnapshotKey": "hMin",
    "isSetting": false,
    "settingType": SettingType.advanced,
    // int32 on the wire (BLE_Custom_Characteristic.cpp:755-769). "int" would
    // read only the low 16 bits and truncate any real step count over 32767.
    "type": "long",
    "humanReadableName": "Homing Min",
    "min": 0,
    "max": 100000000,
    "textDescription": "The minimum value for the homing sequence.",
    "defaultData": "0",
  },
  {
    "vName": BLE_hMaxVname,
    "reference": "0x2B",
    "settingsSnapshotKey": "hMax",
    "isSetting": false,
    "settingType": SettingType.advanced,
    // int32 on the wire (BLE_Custom_Characteristic.cpp:772-789), as hMin above.
    "type": "long",
    "humanReadableName": "Homing Max",
    "min": 0,
    "max": 100000000,
    "textDescription": "The maximum value for the homing sequence.",
    "defaultData": "100000000",
  },
  {
    "vName": homingSensitivityVname,
    "reference": "0x2C",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "int",
    "humanReadableName": "Homing Force",
    "min": 10,
    "max": 100,
    "textDescription":
        "Adjust lower if homing hits the limit too hard/grinds, higher if it stops too soon.",
    "defaultData": "50",
  },
  {
    "vName": pTab4pwrVname,
    "reference": "0x2D",
    "settingsSnapshotKey": "pTab4Pwr",
    "isSetting": true,
    "settingType": SettingType.advanced,
    "type": "bool",
    "humanReadableName": "Power Table for Power",
    "min": 0,
    "max": 1,
    "textDescription":
        "Enable to use the power table for power instead of a power meter",
    "defaultData": "false",
  },
  {
    "vName": BLE_logStreamVname,
    "reference": "0x30",
    "isSetting": false,
    "settingType": SettingType.advanced,
    "type": "string",
    "humanReadableName": "BLE Log Stream",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Read last BLE log message or enable/disable BLE log streaming",
    "defaultData": "",
  },
];
