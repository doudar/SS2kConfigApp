import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/compatibility/sensor_decoders.dart';

List<int> le16(int v) => [v & 0xff, (v >> 8) & 0xff];

void main() {
  group('decodeCyclingPowerMeasurement', () {
    test('power only, no crank data', () {
      final m = decodeCyclingPowerMeasurement([0x00, 0x00, ...le16(215)])!;
      expect(m.power, 215);
      expect(m.crank, isNull);
    });

    test('crank data after balance, torque and wheel fields', () {
      // flags: balance(0) + torque(2) + wheel(4) + crank(5)
      final flags = (1 << 0) | (1 << 2) | (1 << 4) | (1 << 5);
      final m = decodeCyclingPowerMeasurement([
        flags,
        0x00,
        ...le16(180),
        50, // balance
        ...le16(0), // torque
        1, 2, 3, 4, 5, 6, // wheel revs + time
        ...le16(1234),
        ...le16(40000),
      ])!;
      expect(m.power, 180);
      expect(m.crank!.revolutions, 1234);
      expect(m.crank!.eventTime, 40000);
    });

    test('too short is rejected', () {
      expect(decodeCyclingPowerMeasurement([0x00, 0x00, 0x10]), isNull);
    });

    test('crank flag without the bytes reports no crank data', () {
      final m = decodeCyclingPowerMeasurement([1 << 5, 0, ...le16(100), 1]);
      expect(m!.crank, isNull);
    });
  });

  group('decodeCscCrankRevolutions', () {
    test('crank data after wheel data', () {
      final crank = decodeCscCrankRevolutions([
        0x03,
        1, 2, 3, 4, 5, 6, // wheel
        ...le16(77),
        ...le16(2048),
      ])!;
      expect(crank.revolutions, 77);
      expect(crank.eventTime, 2048);
    });

    test('wheel-only packet has no cadence', () {
      expect(decodeCscCrankRevolutions([0x01, 1, 2, 3, 4, 5, 6]), isNull);
    });
  });

  group('CrankCadenceCalculator', () {
    late DateTime now;
    late CrankCadenceCalculator calc;

    setUp(() {
      now = DateTime(2026);
      calc = CrankCadenceCalculator(clock: () => now);
    });

    test('first sample is only a baseline', () {
      expect(calc.add(const CrankRevolutionSample(10, 0)), 0);
    });

    test('one revolution per second is 60 rpm', () {
      calc.add(const CrankRevolutionSample(10, 0));
      expect(calc.add(const CrankRevolutionSample(11, 1024)), 60);
    });

    test('16-bit rollover of revolutions and time', () {
      calc.add(const CrankRevolutionSample(0xFFFF, 0xFC00));
      // +2 revs, +2048 ticks (2 s) across both rollovers => 60 rpm.
      expect(calc.add(const CrankRevolutionSample(1, 0x0400)), 60);
    });

    test('readings above 200 rpm keep the previous cadence', () {
      calc.add(const CrankRevolutionSample(0, 0));
      calc.add(const CrankRevolutionSample(1, 1024)); // 60
      expect(calc.add(const CrankRevolutionSample(11, 2048)), 60);
    });

    test('drops to 0 after 2.5 s without a new crank event', () {
      calc.add(const CrankRevolutionSample(0, 0));
      calc.add(const CrankRevolutionSample(1, 1024));
      now = now.add(const Duration(seconds: 2));
      expect(calc.add(const CrankRevolutionSample(1, 1024)), 60);
      now = now.add(const Duration(seconds: 1));
      expect(calc.add(const CrankRevolutionSample(1, 1024)), 0);
    });
  });

  group('decodeIndoorBikeData', () {
    test('speed, cadence, resistance, power and heart rate', () {
      final flags = (1 << 2) | (1 << 5) | (1 << 6) | (1 << 9);
      final s = decodeIndoorBikeData([
        ...le16(flags),
        ...le16(2550), // 25.50 km/h
        ...le16(181), // 90.5 rpm
        ...le16(30),
        ...le16(250),
        142,
      ])!;
      expect(s.complete, isTrue);
      expect(s.speed, 25);
      expect(s.cadence, 90);
      expect(s.resistance, 30);
      expect(s.power, 250);
      expect(s.heartRate, 142);
    });

    test('More Data flag means speed is absent', () {
      final flags = (1 << 0) | (1 << 2) | (1 << 6);
      final s = decodeIndoorBikeData([
        ...le16(flags),
        ...le16(160),
        ...le16(200),
      ])!;
      expect(s.speed, isNull);
      expect(s.cadence, 80);
      expect(s.power, 200);
    });

    test('truncated packet keeps earlier fields and is incomplete', () {
      final flags = (1 << 2) | (1 << 6);
      final s = decodeIndoorBikeData([...le16(flags), ...le16(1000), 120])!;
      expect(s.complete, isFalse);
      expect(s.speed, 10);
      expect(s.cadence, isNull);
      expect(s.power, isNull);
    });
  });

  group('EchelonDecoder', () {
    test('power needs both a cadence and a resistance packet', () {
      final d = EchelonDecoder();
      d.decode([0xF0, 0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 85]);
      expect(d.cadence, 85);
      expect(d.power, isNull);
      d.decode([0xF0, 0xD2, 0, 20]);
      expect(d.resistance, 20);
      // pow(1.090112, 20) * pow(1.015343, 85) * 7.228958
      expect(d.power, 148);
    });

    test('zero cadence means zero power', () {
      final d = EchelonDecoder()
        ..decode([0xF0, 0xD2, 0, 20])
        ..decode([0xF0, 0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(d.power, 0);
    });
  });
}
