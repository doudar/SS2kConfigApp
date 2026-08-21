import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';

void main() {
  group('targetPowerCommand', () {
    test('encodes signed little-endian watts', () {
      expect(FTMSControlPoint.targetPowerCommand(0), [0x05, 0x00, 0x00]);
      expect(FTMSControlPoint.targetPowerCommand(300), [0x05, 0x2c, 0x01]);
      expect(FTMSControlPoint.targetPowerCommand(-1), [0x05, 0xff, 0xff]);
      expect(FTMSControlPoint.targetPowerCommand(-0x8000), [0x05, 0x00, 0x80]);
      expect(FTMSControlPoint.targetPowerCommand(0x7fff), [0x05, 0xff, 0x7f]);
    });

    test('rejects values outside sint16', () {
      expect(
        () => FTMSControlPoint.targetPowerCommand(-0x8001),
        throwsRangeError,
      );
      expect(
        () => FTMSControlPoint.targetPowerCommand(0x8000),
        throwsRangeError,
      );
    });
  });

  group('indoorBikeSimulationCommand', () {
    test('encodes scaled fields in FTMS order', () {
      expect(
        FTMSControlPoint.indoorBikeSimulationCommand(
          windSpeed: -1.234,
          grade: 4.56,
          crr: 0.004,
          cw: 0.51,
        ),
        [0x11, 0x2e, 0xfb, 0xc8, 0x01, 0x28, 0x33],
      );
    });

    test('encodes a zero simulation reset', () {
      expect(
        FTMSControlPoint.indoorBikeSimulationCommand(
          windSpeed: 0,
          grade: 0,
          crr: 0,
          cw: 0,
        ),
        [0x11, 0, 0, 0, 0, 0, 0],
      );
    });

    test('rejects invalid scaled values', () {
      expect(
        () => FTMSControlPoint.indoorBikeSimulationCommand(
          windSpeed: double.infinity,
          grade: 0,
          crr: 0,
          cw: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => FTMSControlPoint.indoorBikeSimulationCommand(
          windSpeed: 0,
          grade: 0,
          crr: -0.0001,
          cw: 0,
        ),
        throwsRangeError,
      );
    });
  });
}
