import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'bleConstants.dart';

/// Handles FTMS Control Point operations according to the FTMS specification
class FTMSControlPoint {
  /// Encodes Set Target Power using signed watts in little-endian order.
  static Uint8List targetPowerCommand(int targetPower) {
    _checkRange(targetPower, -0x8000, 0x7fff, 'targetPower');
    final buffer = ByteData(FTMSDataConfig.TARGET_POWER_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_TARGET_POWER);
    buffer.setInt16(1, targetPower, Endian.little);
    return buffer.buffer.asUint8List();
  }

  /// Writes target speed to the FTMS Control Point characteristic
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [speedKph] - The target speed in kilometers per hour
  static Future<void> writeTargetSpeed(
    BluetoothCharacteristic characteristic,
    double speedKph,
  ) async {
    try {
      final ByteData buffer = ByteData(FTMSDataConfig.TARGET_SPEED_LENGTH);
      buffer.setUint8(0, FTMSOpCodes.SET_TARGET_SPEED);

      // Convert speed to uint16 with 0.01 resolution
      final int speedValue = (speedKph / FTMSDataConfig.SPEED_RESOLUTION)
          .round();
      buffer.setUint16(1, speedValue, Endian.little);

      await characteristic.write(buffer.buffer.asUint8List());
    } catch (e) {
      print('Error writing target speed to FTMS: $e');
      rethrow;
    }
  }

  /// Writes target inclination to the FTMS Control Point characteristic
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [inclinationPercent] - The target inclination in percentage
  static Future<void> writeTargetInclination(
    BluetoothCharacteristic characteristic,
    double inclinationPercent,
  ) async {
    try {
      final ByteData buffer = ByteData(
        FTMSDataConfig.TARGET_INCLINATION_LENGTH,
      );
      buffer.setUint8(0, FTMSOpCodes.SET_TARGET_INCLINATION);

      // Convert inclination to sint16 with 0.1% resolution
      final int inclinationValue =
          (inclinationPercent / FTMSDataConfig.INCLINATION_RESOLUTION).round();
      buffer.setInt16(1, inclinationValue, Endian.little);

      await characteristic.write(buffer.buffer.asUint8List());
    } catch (e) {
      print('Error writing target inclination to FTMS: $e');
      rethrow;
    }
  }

  /// Writes target resistance level to the FTMS Control Point characteristic
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [resistance] - The target resistance level (unitless)
  static Future<void> writeTargetResistance(
    BluetoothCharacteristic characteristic,
    double resistance,
  ) async {
    try {
      final ByteData buffer = ByteData(FTMSDataConfig.TARGET_RESISTANCE_LENGTH);
      buffer.setUint8(0, FTMSOpCodes.SET_TARGET_RESISTANCE_LEVEL);

      // Convert resistance to uint8 with 0.1 resolution
      final int resistanceValue =
          (resistance / FTMSDataConfig.RESISTANCE_RESOLUTION).round();
      buffer.setUint8(1, resistanceValue);

      await characteristic.write(buffer.buffer.asUint8List());
    } catch (e) {
      print('Error writing target resistance to FTMS: $e');
      rethrow;
    }
  }

  /// Writes target heart rate to the FTMS Control Point characteristic
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [heartRate] - The target heart rate in BPM
  static Future<void> writeTargetHeartRate(
    BluetoothCharacteristic characteristic,
    int heartRate,
  ) async {
    try {
      final ByteData buffer = ByteData(FTMSDataConfig.TARGET_HEART_RATE_LENGTH);
      buffer.setUint8(0, FTMSOpCodes.SET_TARGET_HEART_RATE);
      buffer.setUint8(1, heartRate);

      await characteristic.write(buffer.buffer.asUint8List());
    } catch (e) {
      print('Error writing target heart rate to FTMS: $e');
      rethrow;
    }
  }

  /// Writes target cadence to the FTMS Control Point characteristic
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [cadence] - The target cadence in revolutions per minute
  static Future<void> writeTargetCadence(
    BluetoothCharacteristic characteristic,
    double cadence,
  ) async {
    try {
      final ByteData buffer = ByteData(FTMSDataConfig.TARGET_CADENCE_LENGTH);
      buffer.setUint8(0, FTMSOpCodes.SET_TARGET_CADENCE);

      // Convert cadence to uint16 with 0.5 resolution
      final int cadenceValue = (cadence / FTMSDataConfig.CADENCE_RESOLUTION)
          .round();
      buffer.setUint16(1, cadenceValue, Endian.little);

      await characteristic.write(buffer.buffer.asUint8List());
    } catch (e) {
      print('Error writing target cadence to FTMS: $e');
      rethrow;
    }
  }

  /// Encodes Indoor Bike Simulation parameters using FTMS field resolutions.
  static Uint8List indoorBikeSimulationCommand({
    required double windSpeed,
    required double grade,
    required double crr,
    required double cw,
  }) {
    final windSpeedValue = _scaledValue(
      windSpeed,
      FTMSDataConfig.WIND_SPEED_RESOLUTION,
      -0x8000,
      0x7fff,
      'windSpeed',
    );
    final gradeValue = _scaledValue(
      grade,
      FTMSDataConfig.GRADE_RESOLUTION,
      -0x8000,
      0x7fff,
      'grade',
    );
    final crrValue = _scaledValue(
      crr,
      FTMSDataConfig.CRR_RESOLUTION,
      0,
      0xff,
      'crr',
    );
    final cwValue = _scaledValue(
      cw,
      FTMSDataConfig.CW_RESOLUTION,
      0,
      0xff,
      'cw',
    );

    final buffer = ByteData(FTMSDataConfig.INDOOR_BIKE_SIMULATION_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SET_INDOOR_BIKE_SIMULATION);
    buffer.setInt16(1, windSpeedValue, Endian.little);
    buffer.setInt16(3, gradeValue, Endian.little);
    buffer.setUint8(5, crrValue);
    buffer.setUint8(6, cwValue);
    return buffer.buffer.asUint8List();
  }

  /// Requests control of the fitness machine
  /// [characteristic] - The FTMS Control Point characteristic to write to
  static Future<void> requestControl(
    BluetoothCharacteristic characteristic,
  ) async {
    try {
      final List<int> command = [FTMSOpCodes.REQUEST_CONTROL];
      await characteristic.write(command);
    } catch (e) {
      print('Error requesting FTMS control: $e');
      rethrow;
    }
  }

  /// Resets the fitness machine to default values
  /// [characteristic] - The FTMS Control Point characteristic to write to
  static Future<void> reset(BluetoothCharacteristic characteristic) async {
    try {
      final List<int> command = [FTMSOpCodes.RESET];
      await characteristic.write(command);
    } catch (e) {
      print('Error resetting FTMS: $e');
      rethrow;
    }
  }

  /// Starts or resumes the workout session
  /// [characteristic] - The FTMS Control Point characteristic to write to
  static Future<void> startOrResume(
    BluetoothCharacteristic characteristic,
  ) async {
    try {
      final List<int> command = [FTMSOpCodes.START_OR_RESUME];
      await characteristic.write(command);
    } catch (e) {
      print('Error starting/resuming FTMS session: $e');
      rethrow;
    }
  }

  /// Stops or pauses the workout session
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [stop] - If true, stops the session. If false, pauses the session.
  static Future<void> stopOrPause(
    BluetoothCharacteristic characteristic,
    bool stop,
  ) async {
    try {
      final ByteData buffer = ByteData(FTMSDataConfig.STOP_PAUSE_LENGTH);
      buffer.setUint8(0, FTMSOpCodes.STOP_OR_PAUSE);
      buffer.setUint8(
        1,
        stop ? FTMSStopPauseParams.STOP : FTMSStopPauseParams.PAUSE,
      );

      await characteristic.write(buffer.buffer.asUint8List());
    } catch (e) {
      print('Error stopping/pausing FTMS session: $e');
      rethrow;
    }
  }

  /// Controls the spin down procedure
  /// [characteristic] - The FTMS Control Point characteristic to write to
  /// [start] - If true, starts the spin down procedure. If false, ignores it.
  static Uint8List spinDownCommand(bool start) {
    final ByteData buffer = ByteData(FTMSDataConfig.SPIN_DOWN_CONTROL_LENGTH);
    buffer.setUint8(0, FTMSOpCodes.SPIN_DOWN_CONTROL);
    buffer.setUint8(
      1,
      start ? FTMSSpinDownParams.START : FTMSSpinDownParams.IGNORE,
    );
    return buffer.buffer.asUint8List();
  }

  static Future<void> spinDownControl(
    BluetoothCharacteristic characteristic,
    bool start,
  ) async {
    try {
      await characteristic.write(spinDownCommand(start));
    } catch (e) {
      print('Error controlling spin down procedure: $e');
      rethrow;
    }
  }

  static int _scaledValue(
    double value,
    double resolution,
    int minimum,
    int maximum,
    String name,
  ) {
    if (!value.isFinite) throw RangeError.value(value, name);
    final scaled = (value / resolution).round();
    _checkRange(scaled, minimum, maximum, name);
    return scaled;
  }

  static void _checkRange(int value, int minimum, int maximum, String name) {
    if (value < minimum || value > maximum) {
      throw RangeError.range(value, minimum, maximum, name);
    }
  }
}
