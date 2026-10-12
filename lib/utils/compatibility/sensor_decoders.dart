/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:math' as math;
import 'dart:typed_data';

// Decoders for the sensor notifications SmartSpin2k firmware consumes from a
// connected power meter or smart bike. Each one mirrors the matching parser in
// the firmware's `lib/SS2K/src/sensors/`, so the compatibility check accepts
// exactly what a SmartSpin2k would.

/// One cumulative crank revolution reading: a 16-bit revolution count and a
/// 16-bit event time in 1/1024 s, both of which roll over.
class CrankRevolutionSample {
  const CrankRevolutionSample(this.revolutions, this.eventTime);

  final int revolutions;
  final int eventTime;
}

class CyclingPowerMeasurement {
  const CyclingPowerMeasurement({required this.power, this.crank});

  final int power;

  /// Null when the meter does not include crank revolution data (flag bit 5).
  /// The firmware has no other way to get cadence from a power meter.
  final CrankRevolutionSample? crank;
}

/// Cycling Power Measurement (0x2A63), as `CyclePowerData::decode` reads it.
CyclingPowerMeasurement? decodeCyclingPowerMeasurement(List<int> value) {
  if (value.length < 4) return null;
  final data = ByteData.sublistView(Uint8List.fromList(value));
  final flags = data.getUint8(0);
  final power = data.getInt16(2, Endian.little);
  var index = 4;
  if (flags & (1 << 0) != 0) index += 1; // pedal power balance
  if (flags & (1 << 2) != 0) index += 2; // accumulated torque
  if (flags & (1 << 4) != 0) index += 6; // wheel revolution data
  CrankRevolutionSample? crank;
  if (flags & (1 << 5) != 0 && index + 4 <= data.lengthInBytes) {
    crank = CrankRevolutionSample(
      data.getUint16(index, Endian.little),
      data.getUint16(index + 2, Endian.little),
    );
  }
  return CyclingPowerMeasurement(power: power, crank: crank);
}

/// Crank data from a CSC Measurement (0x2A5B), as `CscSensorData::decode`
/// reads it. Null when the packet carries no crank revolution data.
CrankRevolutionSample? decodeCscCrankRevolutions(List<int> value) {
  if (value.isEmpty) return null;
  final data = ByteData.sublistView(Uint8List.fromList(value));
  final flags = data.getUint8(0);
  var index = 1;
  if (flags & (1 << 0) != 0) index += 6; // wheel revolution data
  if (flags & (1 << 1) == 0 || index + 4 > data.lengthInBytes) return null;
  return CrankRevolutionSample(
    data.getUint16(index, Endian.little),
    data.getUint16(index + 2, Endian.little),
  );
}

/// Turns successive crank revolution samples into rpm the way the firmware
/// does: the first sample is only a baseline, readings above 200 rpm are
/// treated as missed packets, and cadence falls to 0 after 2.5 s without a
/// new crank event.
class CrankCadenceCalculator {
  CrankCadenceCalculator({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const Duration staleAfter = Duration(milliseconds: 2500);

  final DateTime Function() _clock;
  CrankRevolutionSample? _last;
  DateTime? _lastUpdate;
  double _cadence = 0;

  double add(CrankRevolutionSample sample) {
    final last = _last;
    _last = sample;
    if (last == null) {
      _lastUpdate = _clock();
      return _cadence = 0;
    }

    final revolutions = (sample.revolutions - last.revolutions) & 0xFFFF;
    final elapsed = (sample.eventTime - last.eventTime) & 0xFFFF;
    if (revolutions != 0 && elapsed != 0) {
      final computed = revolutions * 1024 * 60 / elapsed;
      if (computed > 1 && computed <= 200) {
        _cadence = computed;
        _lastUpdate = _clock();
      }
    } else if (_clock().difference(_lastUpdate!) > staleAfter) {
      _cadence = 0;
    }
    return _cadence;
  }
}

/// The fields of one FTMS Indoor Bike Data (0x2AD2) notification. A field is
/// null when its flag says it is absent.
class IndoorBikeDataSample {
  const IndoorBikeDataSample({
    this.speed,
    this.cadence,
    this.resistance,
    this.power,
    this.heartRate,
    required this.complete,
  });

  /// km/h, truncated to a whole number.
  final int? speed;

  /// rpm, truncated from the 0.5 rpm wire resolution.
  final int? cadence;
  final int? resistance;
  final int? power;
  final int? heartRate;

  /// False when the packet ended before a field its flags announced. The
  /// fields read before that point are still reported.
  final bool complete;
}

/// FTMS Indoor Bike Data (0x2AD2). Flag bit 0 ("More Data") is inverted: the
/// instantaneous speed field is present only when it is clear, matching
/// `FitnessMachineIndoorBikeData::decode`.
IndoorBikeDataSample? decodeIndoorBikeData(List<int> value) {
  if (value.length < 2) return null;
  final data = ByteData.sublistView(Uint8List.fromList(value));
  final flags = data.getUint16(0, Endian.little);
  var index = 2;
  int? speed, cadence, resistance, power, heartRate;

  bool has(int bytes) => index + bytes <= data.lengthInBytes;
  IndoorBikeDataSample result({required bool complete}) => IndoorBikeDataSample(
    speed: speed,
    cadence: cadence,
    resistance: resistance,
    power: power,
    heartRate: heartRate,
    complete: complete,
  );

  if (flags & (1 << 0) == 0) {
    if (!has(2)) return result(complete: false);
    speed = data.getUint16(index, Endian.little) ~/ 100; // resolution 0.01
    index += 2;
  }
  if (flags & (1 << 1) != 0) {
    if (!has(2)) return result(complete: false);
    index += 2; // average speed
  }
  if (flags & (1 << 2) != 0) {
    if (!has(2)) return result(complete: false);
    cadence = data.getUint16(index, Endian.little) ~/ 2; // resolution 0.5
    index += 2;
  }
  if (flags & (1 << 3) != 0) {
    if (!has(2)) return result(complete: false);
    index += 2; // average cadence
  }
  if (flags & (1 << 4) != 0) {
    if (!has(3)) return result(complete: false);
    index += 3; // total distance
  }
  if (flags & (1 << 5) != 0) {
    if (!has(2)) return result(complete: false);
    resistance = data.getInt16(index, Endian.little);
    index += 2;
  }
  if (flags & (1 << 6) != 0) {
    if (!has(2)) return result(complete: false);
    power = data.getInt16(index, Endian.little);
    index += 2;
  }
  if (flags & (1 << 7) != 0) {
    if (!has(2)) return result(complete: false);
    index += 2; // average power
  }
  if (flags & (1 << 8) != 0) {
    if (!has(1)) return result(complete: false);
    index += 1; // expended energy (first byte, as the app always has)
  }
  if (flags & (1 << 9) != 0) {
    if (!has(1)) return result(complete: false);
    heartRate = data.getUint8(index);
    index += 1;
  }
  return result(complete: true);
}

/// Echelon bikes report cadence and resistance in separate packets; power is
/// estimated from the two with the firmware's formula (`EchelonData::decode`).
class EchelonDecoder {
  int? cadence;
  int? resistance;

  /// Estimated watts, or null until both a cadence and a resistance packet
  /// have arrived.
  int? get power {
    final cad = cadence, res = resistance;
    if (cad == null || res == null) return null;
    if (cad == 0 || res == 0) return 0;
    return (math.pow(1.090112, res) * math.pow(1.015343, cad) * 7.228958)
        .toInt();
  }

  void decode(List<int> value) {
    if (value.length < 2) return;
    switch (value[1]) {
      case 0xD1:
        if (value.length >= 11) cadence = (value[9] << 8) + value[10];
      case 0xD2:
        if (value.length >= 4) resistance = value[3];
    }
  }
}
