import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'bleConstants.dart';

/// Handles FTMS Control Point operations according to the FTMS specification
class FTMSControlPoint {
  static Future<void> _writeCommand({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
  }) async {
    try {
      await UniversalBle.write(
        deviceId,
        serviceUuid,
        characteristicUuid,
        Uint8List.fromList(value),
      );
    } catch (e) {
      print('Error writing to FTMS characteristic: $e');
      rethrow;
    }
  }

  static Future<void> writeTargetPower({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required int targetPower,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.TARGET_POWER_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_POWER);
    buffer.setInt16(1, targetPower, Endian.little);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> writeTargetSpeed({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required double speedKph,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.TARGET_SPEED_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_SPEED);
    final int speedValue = (speedKph / FTMSDataConfig.SPEED_RESOLUTION).round();
    buffer.setUint16(1, speedValue, Endian.little);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> writeTargetInclination({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required double inclinationPercent,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.TARGET_INCLINATION_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_INCLINATION);
    final int inclinationValue = (inclinationPercent / FTMSDataConfig.INCLINATION_RESOLUTION).round();
    buffer.setInt16(1, inclinationValue, Endian.little);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> writeTargetResistance({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required double resistance,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.TARGET_RESISTANCE_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_RESISTANCE_LEVEL);
    final int resistanceValue = (resistance / FTMSDataConfig.RESISTANCE_RESOLUTION).round();
    buffer.setUint8(1, resistanceValue);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> writeTargetHeartRate({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required int heartRate,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.TARGET_HEART_RATE_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_HEART_RATE);
    buffer.setUint8(1, heartRate);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> writeTargetCadence({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required double cadence,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.TARGET_CADENCE_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_CADENCE);
    final int cadenceValue = (cadence / FTMSDataConfig.CADENCE_RESOLUTION).round();
    buffer.setUint16(1, cadenceValue, Endian.little);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> writeIndoorBikeSimulation({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required double windSpeed,
    required double grade,
    required double crr,
    required double cw,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.INDOOR_BIKE_SIMULATION_LENGTH);
    int offset = 0;
    buffer.setUint8(offset, FTMSOpCodes.SET_INDOOR_BIKE_SIMULATION);
    offset += 1;
    final int windSpeedValue = (windSpeed / FTMSDataConfig.WIND_SPEED_RESOLUTION).round();
    buffer.setInt16(offset, windSpeedValue, Endian.little);
    offset += 2;
    final int gradeValue = (grade / FTMSDataConfig.GRADE_RESOLUTION).round();
    buffer.setInt16(offset, gradeValue, Endian.little);
    offset += 2;
    final int crrValue = (crr / FTMSDataConfig.CRR_RESOLUTION).round();
    buffer.setUint8(offset, crrValue);
    offset += 1;
    final int cwValue = (cw / FTMSDataConfig.CW_RESOLUTION).round();
    buffer.setUint8(offset, cwValue);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> requestControl({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: [FTMSOpCodes.REQUEST_CONTROL],
    );
  }

  static Future<void> reset({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: [FTMSOpCodes.RESET],
    );
  }

  static Future<void> startOrResume({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: [FTMSOpCodes.START_OR_RESUME],
    );
  }

  static Future<void> stopOrPause({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required bool stop,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.STOP_PAUSE_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.STOP_OR_PAUSE);
    buffer.setUint8(1, stop ? FTMSStopPauseParams.STOP : FTMSStopPauseParams.PAUSE);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }

  static Future<void> spinDownControl({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required bool start,
  }) async {
    final ByteData buffer = ByteData(FTMSDataConfig.SPIN_DOWN_CONTROL_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SPIN_DOWN_CONTROL);
    buffer.setUint8(1, start ? FTMSSpinDownParams.START : FTMSSpinDownParams.IGNORE);
    await _writeCommand(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: buffer.buffer.asUint8List(),
    );
  }
}
