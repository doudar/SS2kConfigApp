/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

enum BleSensorCategory { powerMeter, heartRate, auxiliary }

class BleSensorServiceDefinition {
  const BleSensorServiceDefinition({
    required this.advertisedUuid,
    required this.deviceUuid,
    required this.category,
    this.requiredName,
  });

  /// UUID form returned by FlutterBluePlus after advertisement normalization.
  final String advertisedUuid;

  /// Identifier form used by SmartSpin2k's found-device protocol.
  final String deviceUuid;
  final BleSensorCategory category;
  final String? requiredName;
}

const String bleCyclingPowerServiceUuid = '1818';
const String bleCyclingSpeedCadenceServiceUuid = '1816';
const String bleHeartRateServiceUuid = '180d';
const String bleFitnessMachineServiceUuid = '1826';
const String bleFitnessMachineServiceUuid128 =
    '0000$bleFitnessMachineServiceUuid-0000-1000-8000-00805f9b34fb';
const String bleHumanInterfaceDeviceServiceUuid = '1812';
const String bleEchelonServiceUuid = '0bf669f0-45f2-11e7-9598-0800200c9a66';
const String bleEchelonSecondaryServiceUuid =
    '0bf669f1-45f2-11e7-9598-0800200c9a66';
const String blePelotonUartServiceUuid = 'a026ee07-0a7d-4ab3-97fa-f1500f9feb8b';
const String bleFlywheelUartServiceUuid =
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

const String bleCyclingPowerDeviceUuid = '0x$bleCyclingPowerServiceUuid';
const String bleCyclingSpeedCadenceDeviceUuid =
    '0x$bleCyclingSpeedCadenceServiceUuid';
const String bleHeartRateDeviceUuid = '0x$bleHeartRateServiceUuid';
const String bleFitnessMachineDeviceUuid = '0x$bleFitnessMachineServiceUuid';
const String bleHumanInterfaceDeviceUuid =
    '0x$bleHumanInterfaceDeviceServiceUuid';

/// Sensor services accepted by SmartSpin2k firmware, in firmware priority
/// order. Keep this list synchronized with `SUPPORTED_SERVICES` in firmware.
const List<BleSensorServiceDefinition> supportedBleSensorServices = [
  BleSensorServiceDefinition(
    advertisedUuid: bleCyclingPowerServiceUuid,
    deviceUuid: bleCyclingPowerDeviceUuid,
    category: BleSensorCategory.powerMeter,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleCyclingSpeedCadenceServiceUuid,
    deviceUuid: bleCyclingSpeedCadenceDeviceUuid,
    category: BleSensorCategory.powerMeter,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleHeartRateServiceUuid,
    deviceUuid: bleHeartRateDeviceUuid,
    category: BleSensorCategory.heartRate,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleEchelonServiceUuid,
    deviceUuid: bleEchelonServiceUuid,
    category: BleSensorCategory.powerMeter,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleEchelonSecondaryServiceUuid,
    deviceUuid: bleEchelonSecondaryServiceUuid,
    category: BleSensorCategory.powerMeter,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: blePelotonUartServiceUuid,
    deviceUuid: blePelotonUartServiceUuid,
    category: BleSensorCategory.powerMeter,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleFitnessMachineServiceUuid,
    deviceUuid: bleFitnessMachineDeviceUuid,
    category: BleSensorCategory.powerMeter,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleHumanInterfaceDeviceServiceUuid,
    deviceUuid: bleHumanInterfaceDeviceUuid,
    category: BleSensorCategory.auxiliary,
  ),
  BleSensorServiceDefinition(
    advertisedUuid: bleFlywheelUartServiceUuid,
    deviceUuid: bleFlywheelUartServiceUuid,
    category: BleSensorCategory.powerMeter,
    requiredName: 'Flywheel 1',
  ),
];

bool isPowerMeterDeviceServiceUuid(String? uuid) =>
    _isDeviceServiceCategory(uuid, BleSensorCategory.powerMeter);

bool isHeartRateDeviceServiceUuid(String? uuid) =>
    _isDeviceServiceCategory(uuid, BleSensorCategory.heartRate);

bool _isDeviceServiceCategory(String? uuid, BleSensorCategory category) {
  final normalized = uuid?.toLowerCase();
  if (normalized == null) return false;
  return supportedBleSensorServices.any(
    (service) =>
        service.category == category && service.deviceUuid == normalized,
  );
}
