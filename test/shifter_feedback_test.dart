import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/shifter_feedback.dart';

void main() {
  String feedback({
    bool connected = true,
    bool homing = false,
    bool noCadence = false,
    int mode = 0x11,
    int delta = 1,
    double position = 950,
    double maximum = 1000,
    double stepSize = 100,
  }) => shiftFeedback(
    connected: connected,
    homing: homing,
    noCadence: noCadence,
    mode: mode,
    delta: delta,
    position: position,
    minimum: 0,
    maximum: maximum,
    stepSize: stepSize,
  );

  test('travel gauge normalizes calibrated range and clamps endpoints', () {
    expect(stepperTravelProgress(150, 100, 300), .25);
    expect(stepperTravelProgress(50, 100, 300), 0);
    expect(stepperTravelProgress(350, 100, 300), 1);
    expect(stepperTravelProgress(0, -100, 100), .5);
  });
  test('missing, unhomed and invalid ranges remain unknown', () {
    expect(stepperTravelProgress(null, 0, 100), isNull);
    expect(stepperTravelProgress(10, 0, 100000000), isNull);
    expect(stepperTravelProgress(10, -2147483648, 100), isNull);
    expect(stepperTravelProgress(10, 100, 100), isNull);
    expect(stepperTravelProgress(10, 200, 100), isNull);
    expect(stepperTravelProgress(double.nan, 0, 100), isNull);
  });
  test('reports observed homing before other possible blockers', () {
    expect(
      feedback(homing: true, noCadence: true),
      contains('Homing is active'),
    );
  });
  test('explains travel limits only in the requested direction', () {
    expect(feedback(), contains('upper travel limit'));
    expect(feedback(position: 50, delta: -1), contains('lower travel limit'));
    expect(feedback(delta: -1), isNot(contains('travel limit')));
    expect(feedback(maximum: 100000000), isNot(contains('travel limit')));
  });
  test('cadence explanation is distinct from a connection failure', () {
    expect(
      feedback(position: 500, noCadence: true),
      contains('Start pedaling'),
    );
    expect(
      feedback(position: 500, noCadence: true),
      isNot(contains('connection')),
    );
    expect(feedback(connected: false), contains('disconnected'));
  });
  test('ERG limits use watts, not travel position', () {
    expect(
      feedback(mode: FTMSOpCodes.SET_TARGET_POWER),
      isNot(contains('travel limit')),
    );
    expect(
      shiftFeedback(
        connected: true,
        homing: false,
        noCadence: false,
        mode: FTMSOpCodes.SET_TARGET_POWER,
        delta: 1,
        targetWatts: 395,
        maxWatts: 400,
      ),
      contains('target power limit'),
    );
  });
  test('unknown reason stays neutral about connectivity', () {
    expect(feedback(position: 500), contains('may be blocked'));
    expect(feedback(position: 500), isNot(contains('Check your connection')));
  });
}
