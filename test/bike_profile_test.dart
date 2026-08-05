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

  group('hasPhysicalEndStops', () {
    test('is false only for the Bike+', () async {
      expect(BikeProfile.hasPhysicalEndStops(BikeType.pelotonBikePlus), isFalse);

      for (final bikeType in BikeType.values.where((b) => b != BikeType.pelotonBikePlus)) {
        expect(BikeProfile.hasPhysicalEndStops(bikeType), isTrue, reason: '$bikeType');
      }
    });

    test('assumes end stops when the bike is unknown', () async {
      expect(BikeProfile.hasPhysicalEndStops(null), isTrue);
    });
  });
}
