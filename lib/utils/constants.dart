/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter/services.dart';

final String csUUID = "77776277-7877-7774-4466-896665500000";
final String ccUUID = "77776277-7877-7774-4466-896665500001";

final String ftmsServiceUUID = "00001826-0000-1000-8000-00805f9b34fb";
final String ftmsControlPointUUID = "00002AD9-0000-1000-8000-00805f9b34fb";
final String ftmsIndoorBikeDataUUID = "00002AD2-0000-1000-8000-00805f9b34fb";

final Color activeBackgroundColor = Color(0xffc9ccf5);
final Color deactiveBackgroundColor = Color.fromARGB(255, 90, 91, 100);

// String that's inserted if the response from the server is not supported.
final String noFirmSupport = "Not supported by firmware version.";

// Any and None selections pre-formatted so they can be appended to the JSON from the SmartSpin2k easily.
String defaultDevices =
    '''[{"device -4": {"name": "any", "UUID": "0x180d"},"device -3": {"name": "none", "UUID": "0x180d"},"device -2": {"name": "any", "UUID": "0x1818"},"device -1": {"name": "none", "UUID": "0x1818"},''';

// Defining vName variables directly for easier editing
final String passwordVname = "BLE_password";
final String saveVname = "BLE_saveToLittleFS";
final String foundDevicesVname = "BLE_foundDevices";
final String connectedHRMVname = "BLE_connectedHeartMonitor";
final String connectedPWRVname = "BLE_connectedPowerMeter";
final String rebootVname = "BLE_reboot";
final String resetVname = "BLE_resetToDefaults";
final String fwVname = "BLE_firmwareVer";
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

// Refactored customCharacteristicFramework to directly use Dart map
final dynamic customCharacteristicFramework = [
  {
    "vName": fwVname,
    "reference": "0x25",
    "isSetting": false,
    "type": "string",
    "humanReadableName": "Firmware Version",
    "min": 0,
    "max": 2000,
    "textDescription": "The current loaded firmware.",
    "defaultData": "SmartSpin2k"
  },
  {
    "vName": connectedPWRVname,
    "reference": "0x15",
    "isSetting": true,
    "type": "string",
    "humanReadableName": "Saved Power Meter",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Select your Power Meter from the list. \n Device Not showing up? Check that it's not connected to anything else and press scan again.",
    "defaultData": "any"
  },
  {
    "vName": connectedHRMVname,
    "reference": "0x16",
    "isSetting": true,
    "type": "string",
    "humanReadableName": "Saved HRM",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Select your Heart Rate Monitor from the list. \n Device Not showing up? Check that it's not connected to anything else and press scan again.",
    "defaultData": "any"
  },
  {
    "vName": foundDevicesVname,
    "reference": "0x14",
    "isSetting": false,
    "type": "string",
    "humanReadableName": "Found Devices",
    "min": 0,
    "max": 2000,
    "textDescription": "The following devices have been found",
    "defaultData":
        "[{\"device 0\":{\"name\":\"Polar OH1 B9B6D624 d6\",\"UUID\":\"0x180d\"},\"device 1\":{\"name\":\"Wahoo Kicker\",\"UUID\":\"0x1818\"} }]"
  },
  {
    "vName": shiftStepVname,
    "reference": "0x08",
    "isSetting": true,
    "type": "int",
    "humanReadableName": "Shift Step",
    "min": 100,
    "max": 2000,
    "textDescription":
        "This setting controls how much each click of the shifter turns the dial. The ideal setting is different for each bike and person. Try aiming for a +/- 30 watt change when you click the shifter. Higher values will turn the knob further.",
    "defaultData": "1500"
  },
  {
    "vName": shiftDirVname,
    "reference": "0x20",
    "isSetting": true,
    "type": "bool",
    "humanReadableName": "Swap Shifter Direction",
    "min": 0,
    "max": 1,
    "textDescription":
        "This setting controls which shifter button is up and which is down. Toggle this if you need to invert the direction of the shifters.",
    "defaultData": "true"
  },
  {
    "vName": saveVname,
    "reference": "0x18",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Save to SmartSpin2k",
    "min": 0,
    "max": 1,
    "textDescription": "Saves all of the configuration to the filesystem",
    "defaultData": "false"
  },
  {
    "vName": inclineMultiplierVname,
    "reference": "0x0B",
    "isSetting": true,
    "type": "float",
    "humanReadableName": "Incline Multiplier",
    "min": 0,
    "max": 10,
    "textDescription":
        "This setting affects how much you will feel the impact of hills in sim mode rides. Pick the setting which feels most realistic to you. Higher values will make hills feel steeper while lower values will flatten out the hills.",
    "defaultData": "5.0"
  },
  {
    "vName": ERGSensitivityVname,
    "reference": "0x1F",
    "isSetting": true,
    "type": "float",
    "humanReadableName": "ERG Sensitivity",
    "min": 0,
    "max": 10,
    "textDescription":
        "This setting will impact the sensitivity of Erg Mode. Too low will cause the Erg to be slow at reaching target wattage. Too high will cause it to overshoot and oscillate before settling. Start with the default value of 5 and adjust if necessary.",
    "defaultData": "5.0"
  },
  {
    "vName": firmwareUpdateURLVname,
    "reference": "0x01",
    "isSetting": false,
    "type": "string",
    "humanReadableName": "Firmware Update URL",
    "min": 0,
    "max": 0,
    "textDescription": "URL for firmware updates.",
    "defaultData": "https://raw.githubusercontent.com/doudar/OTAUpdates/main/"
  },
  {
    "vName": inclineVname,
    "reference": "0x02",
    "isSetting": false,
    "type": "float",
    "humanReadableName": "Current Incline",
    "min": -30,
    "max": 30,
    "textDescription": "The incline requested by your training program.",
    "defaultData": "0.0"
  },
  {
    "vName": simulatedWattsVname,
    "reference": "0x03",
    "isSetting": false,
    "type": "int",
    "humanReadableName": "Current Watts",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current watts output.",
    "defaultData": "0"
  },
  {
    "vName": simulatedHrVname,
    "reference": "0x04",
    "isSetting": false,
    "type": "int",
    "humanReadableName": "Current HR",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current heart rate.",
    "defaultData": "0"
  },
  {
    "vName": simulatedTargetWattsVname,
    "reference": "0x28",
    "isSetting": false,
    "type": "int",
    "humanReadableName": "Current TW",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current target watts.",
    "defaultData": "0"
  },
  {
    "vName": simulatedCadVname,
    "reference": "0x05",
    "isSetting": false,
    "type": "int",
    "humanReadableName": "Current CAD",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current cadence.",
    "defaultData": "0"
  },
  {
    "vName": simulatedSpeedVname,
    "reference": "0x06",
    "isSetting": false,
    "type": "float",
    "humanReadableName": "Current Speed",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current speed.",
    "defaultData": "0"
  },
  {
    "vName": deviceNameVname,
    "reference": "0x07",
    "isSetting": true,
    "type": "string",
    "humanReadableName": "Name of SmartSpin2k",
    "min": 0,
    "max": 0,
    "textDescription":
        "Set the name for your SmartSpin2k device. This will also change the URL of the device on the local network to yourName.local",
    "defaultData": "SmartSpin2k"
  },
  {
    "vName": stepperPowerVname,
    "reference": "0x09",
    "isSetting": true,
    "type": "int",
    "humanReadableName": "Stepper Power",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Adjust this setting if you are experiencing overheat issues or if you need additional torque for a felt resistance bike. Do not exceed your power supply's rated limits.",
    "defaultData": "900"
  },
  {
    "vName": stealthChopVname,
    "reference": "0x0A",
    "isSetting": true,
    "type": "bool",
    "humanReadableName": "Stealth Chop",
    "min": 0,
    "max": 1,
    "textDescription":
        "This silences the stepper motor. Leave it on unless it is causing issues. Turning it off may provide some additional torque if you have a felt resistance bike.",
    "defaultData": "true"
  },
  {
    "vName": powerCorrectionFactorVname,
    "reference": "0x0C",
    "isSetting": true,
    "type": "float",
    "humanReadableName": "Power Correction Factor",
    "min": 0.4,
    "max": 2.0,
    "textDescription":
        "Increase or decrease this setting to correct the power reported from your bike. This is typically only needed if your bike is over or under reporting power by a significant amount. IC4/C6 users may want to try a value around 0.7 to .8",
    "defaultData": "1.0"
  },
  {
    "vName": simulateHrVname,
    "reference": "0x0D",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Simulate HR",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated heart rate monitor data.",
    "defaultData": "false"
  },
  {
    "vName": simulateWattsVname,
    "reference": "0x0E",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Simulate Watts",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated power meter data.",
    "defaultData": "false"
  },
  {
    "vName": simulateTargetWattsVname,
    "reference": "0x29",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Simulate Target Watts",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated target watts meter data.",
    "defaultData": "false"
  },
  {
    "vName": simulateCadVname,
    "reference": "0x0F",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Simulate CAD",
    "min": 0,
    "max": 1,
    "textDescription": "Enable to generate simulated cadence sensor data.",
    "defaultData": "false"
  },
  {
    "vName": FTMSModeVname,
    "reference": "0x10",
    "isSetting": false,
    "type": "int",
    "humanReadableName": "Current FTMS Mode",
    "min": 0,
    "max": 2000,
    "textDescription": "Current mode of the Fitness Machine Service (FTMS) profile.",
    "defaultData": "0"
  },
  {
    "vName": autoUpdateVname,
    "reference": "0x11",
    "isSetting": true,
    "type": "bool",
    "humanReadableName": "Auto Updates",
    "min": 0,
    "max": 1,
    "textDescription": "Toggle to enable or disable automatic firmware updates.",
    "defaultData": "true"
  },
  {
    "vName": ssidVname,
    "reference": "0x12",
    "isSetting": true,
    "type": "string",
    "humanReadableName": "WiFi SSID (2.4 Ghz)",
    "min": 0,
    "max": 2000,
    "textDescription":
        "Enter the SSID of a 2.4GHz WiFi network to access SmartSpin2k settings over WiFi. If it doesn't connect, it will start and access point with the device name.",
    "defaultData": "SmartSpin2k"
  },
  {
    "vName": passwordVname,
    "reference": "0x13",
    "isSetting": true,
    "type": "string",
    "humanReadableName": "WiFi Password",
    "min": 0,
    "max": 2000,
    "textDescription": "Enter your WiFi password.",
    "defaultData": "password"
  },
  {
    "vName": shifterPositionVname,
    "reference": "0x17",
    "isSetting": false,
    "type": "int",
    "humanReadableName": "Current Gear",
    "min": 0,
    "max": 2000,
    "textDescription": "Your current gear.",
    "defaultData": "0"
  },
  {
    "vName": targetPositionVname,
    "reference": "0x19",
    "isSetting": false,
    "type": "long",
    "humanReadableName": "Target Stepper Position",
    "min": 0,
    "max": 20000,
    "textDescription": "The target position for the stepper motor.",
    "defaultData": "0"
  },
  {
    "vName": externalControlVname,
    "reference": "0x1A",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "External Control",
    "min": 0,
    "max": 1,
    "textDescription": "Indicates if the device is under external control.",
    "defaultData": "false"
  },
  {
    "vName": stepperSpeedVname,
    "reference": "0x1E",
    "isSetting": true,
    "type": "int",
    "humanReadableName": "Stepper Motor Speed",
    "min": 100,
    "max": 3500,
    "textDescription": "Adjust the motor speed. The default setting is adequate for the majority of users.",
    "defaultData": "1500"
  },
  {
    "vName": syncModeVname,
    "reference": "0x1B",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Sync Mode",
    "min": 0,
    "max": 1,
    "textDescription": "Indicates if the device is in sync mode.",
    "defaultData": "0"
  },
  {
    "vName": minBrakeWattsVname,
    "reference": "0x21",
    "isSetting": true,
    "type": "int",
    "humanReadableName": "Min Brake Watts",
    "min": 0,
    "max": 100,
    "textDescription": "Minimum amount of resistance you can pedal without hitting the low limit stop on your bike.",
    "defaultData": "50"
  },
  {
    "vName": maxBrakeWattsVname,
    "reference": "0x22",
    "isSetting": true,
    "type": "int",
    "humanReadableName": "Max Brake Watts",
    "min": 0,
    "max": 2500,
    "textDescription": "Maximum amount of resistance you can pedal without hitting the high limit stop on your bike.",
    "defaultData": "1400"
  },
  {
    "vName": restartBLEVname,
    "reference": "0x23",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Reconnect Devices",
    "min": 0,
    "max": 1,
    "textDescription": "Disconnect the BLE devices (scan will then happen along with reconnect).",
    "defaultData": "false"
  },
  {
    "vName": scanBLEVname,
    "reference": "0x24",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "BLE Scan",
    "min": 0,
    "max": 1,
    "textDescription":
        "Scan for BLE devices. Scanning is automatic (not needed to be used) unless all devices are connected.",
    "defaultData": "false"
  },
  {
    "vName": rebootVname,
    "reference": "0x1C",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Reboot",
    "min": 0,
    "max": 1,
    "textDescription": "Reboots The SmartSpin2k",
    "defaultData": "false"
  },
  {
    "vName": resetVname,
    "reference": "0x1D",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Reset to defaults",
    "min": 0,
    "max": 1,
    "textDescription": "Reset the SmartSpin2k to defaults",
    "defaultData": "false"
  },
  {
    "vName": resetPowerTableVname,
    "reference": "0x26",
    "isSetting": false,
    "type": "bool",
    "humanReadableName": "Delete the PowerTable",
    "min": 0,
    "max": 1,
    "textDescription": "Delete the active and saved power table",
    "defaultData": "false"
  },
  {
    "vName": powerTableDataVname,
    "reference": "0x27",
    "isSetting": false,
    "type": "powerTableData",
    "humanReadableName": "Power Table Data",
    "min": -32768,
    "max": 32768,
    "textDescription": "Read or Write Data to the Power Table",
    "defaultData": "false"
  }
];
