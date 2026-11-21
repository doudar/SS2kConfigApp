/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter/material.dart';

import 'ble_sensor_services.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as protocol;

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

final String csUUID = protocol.serviceUuid;
final String ccUUID = protocol.characteristicUuid;

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
final String udpLoggingVname = "BLE_UDPLogging";
final String BLE_logStreamVname = "BLE_BLELogging";
final String gearPresetVname = "BLE_gearPreset";
final String gearTeethVname = "BLE_gearTeeth";

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

final List<Map<String, dynamic>> customCharacteristicFramework = [
  for (final descriptor in protocol.createAppDescriptors())
    {
      ...descriptor,
      'settingType': SettingType.values.byName(
        descriptor['settingType'] as String,
      ),
    },
];
