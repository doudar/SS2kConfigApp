import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/bike_profile.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_step_machine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns null on a clean install', () async {
    expect(await BikeProfile.load(), isNull);
  });

  test('round-trips every bike type', () async {
    for (final bikeType in BikeType.values) {
      await BikeProfile.save(bikeType);
      expect(await BikeProfile.load(), bikeType);
      expect(await BikeProfile.loadCalibrationSetup(), BikeProfile.calibrationSetupFor(bikeType));
    }
  });

  test('survives a SharedPreferences reload', () async {
    await BikeProfile.save(BikeType.pelotonBikePlus);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    expect(await BikeProfile.load(), BikeType.pelotonBikePlus);
  });

  test('saving twice keeps the latest value', () async {
    await BikeProfile.save(BikeType.mostSpinBikes);
    await BikeProfile.save(BikeType.pelotonOriginal);

    expect(await BikeProfile.load(), BikeType.pelotonOriginal);
  });

  test('is stored by name, so reordering the enum cannot remap it', () async {
    SharedPreferences.setMockInitialValues({'bike_type': 'pelotonBikePlus'});

    expect(await BikeProfile.load(), BikeType.pelotonBikePlus);
  });

  test('an unrecognised stored value degrades to null rather than throwing', () async {
    SharedPreferences.setMockInitialValues({'bike_type': 'someBikeFromTheFuture'});

    expect(await BikeProfile.load(), isNull);
  });

  group('calibration setup', () {
    test('is null when neither calibration nor onboarding has identified the bike', () async {
      expect(await BikeProfile.loadCalibrationSetup(), isNull);
    });

    test('maps legacy Bike+ profiles to the continuous-knob setup', () async {
      SharedPreferences.setMockInitialValues({'bike_type': 'pelotonBikePlus'});

      expect(await BikeProfile.loadCalibrationSetup(), CalibrationSetup.pelotonBikePlus);
    });

    test('maps other legacy bike profiles to physical stops', () async {
      SharedPreferences.setMockInitialValues({'bike_type': 'pelotonOriginal'});

      expect(await BikeProfile.loadCalibrationSetup(), CalibrationSetup.physicalStops);
    });

    test('stores a calibration answer without inventing a bike type', () async {
      await BikeProfile.saveCalibrationSetup(CalibrationSetup.physicalStops);

      expect(await BikeProfile.loadCalibrationSetup(), CalibrationSetup.physicalStops);
      expect(await BikeProfile.load(), isNull);
    });

    test('an explicit calibration answer takes precedence over the onboarding profile', () async {
      SharedPreferences.setMockInitialValues({'bike_type': 'pelotonBikePlus', 'calibration_setup': 'physicalStops'});

      expect(await BikeProfile.loadCalibrationSetup(), CalibrationSetup.physicalStops);
    });
  });
}
