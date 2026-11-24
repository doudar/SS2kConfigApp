import 'dart:io';
import 'dart:math' as math;

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';
import 'package:ss2kconfigapp/utils/workout/ride_map.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_fit_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime.utc(2026, 7, 1);
  const center = (name: 'Melbourne', lat: -37.8136, lon: 144.9631);

  test(
    'random picks all four drawings and is repeatable for the same ride',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(RideMapSettings.load(prefs).drawing, RideDrawing.random);
      expect(RideMapSettings.load(prefs).center, RideMapSettings.eauClaire);
      final choices = <RideDrawing>{};
      for (int day = 0; day < 100; day++) {
        final date = start.add(Duration(days: day));
        final drawing = RideDrawing.random.forRide(date);
        expect(RideDrawing.random.forRide(date), drawing);
        choices.add(drawing);
      }
      expect(choices, unorderedEquals(RideDrawing.outlines));
      await const RideMapSettings(
        drawing: RideDrawing.none,
        center: center,
      ).save(prefs);
      expect(RideMapSettings.load(prefs).drawing, RideDrawing.none);
      expect(RideMapSettings.load(prefs).center, center);
    },
  );

  for (final drawing in RideDrawing.outlines) {
    test(
      '${drawing.label} traces 20 miles around the selected city and retraces continuously',
      () {
        final route = RideMapRoute.forRide(
          RideMapSettings(drawing: drawing, center: center),
          start,
        )!;
        var previous = route.position(0);
        double traveled = 0;
        double minLat = previous.lat,
            maxLat = previous.lat,
            minLon = previous.lon,
            maxLon = previous.lon;
        for (var i = 1; i <= 4000; i++) {
          final next = route.position(RideMapRoute.lengthMeters * i / 4000);
          const radians = math.pi / 180;
          final north = (next.lat - previous.lat) * radians;
          final east =
              (next.lon - previous.lon) *
              radians *
              math.cos(next.lat * radians);
          traveled += math.sqrt(north * north + east * east) * 6371000;
          minLat = math.min(minLat, next.lat);
          maxLat = math.max(maxLat, next.lat);
          minLon = math.min(minLon, next.lon);
          maxLon = math.max(maxLon, next.lon);
          previous = next;
        }
        expect(traveled / 1609.344, closeTo(20, .25));
        expect((minLat + maxLat) / 2, closeTo(center.lat, .002));
        expect((minLon + maxLon) / 2, closeTo(center.lon, .002));
        expect(
          route.position(RideMapRoute.lengthMeters + 25),
          route.position(RideMapRoute.lengthMeters - 25),
        );
      },
    );
  }

  final points = List.generate(
    3,
    (i) => TrackPoint(
      timestamp: start.add(Duration(seconds: i)),
      lat: 0,
      lon: 0,
      elevation: 100,
      heartRate: 150,
      cadence: 85,
      power: 215,
      speed: 8.5,
    ),
  );
  test(
    'map-free FIT contains metrics and distances with absent position fields',
    () {
      final records = WorkoutFitExport.records(
        points,
        const RideMapSettings(drawing: RideDrawing.none),
      );
      final fit = FitFile.fromBytes(
        GpxToFitConverter.buildActivity(records).toBytes(),
      );
      final messages = fit.records.map((r) => r.message);
      final samples = messages.whereType<RecordMessage>();
      expect(samples.length, 3);
      for (final record in samples) {
        expect(record.positionLat, isNull);
        expect(record.positionLong, isNull);
        expect(record.power, 215);
        expect(record.heartRate, 150);
        expect(record.cadence, 85);
        expect(record.speed, 8.5);
        expect(record.altitude, 100);
      }
      expect(samples.map((r) => r.distance), [8.5, 17, 25.5]);
      expect(messages.whereType<SessionMessage>().single.totalDistance, 25.5);
      expect(messages.whereType<LapMessage>().single.totalDistance, 25.5);
    },
  );

  test(
    'Past rides applies current settings to a legacy GPS-only upload copy',
    () async {
      final dir = await Directory.systemTemp.createTemp('ride_map_test');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/legacy.fit');
      final legacy = List.generate(
        3,
        (i) => RecordMessage()
          ..timestamp = start.add(Duration(seconds: i)).millisecondsSinceEpoch
          ..power = 210
          ..cadence = 85
          ..heartRate = 150
          ..positionLat = 45 + i * .00008
          ..positionLong = -91,
      );
      final original = GpxToFitConverter.buildActivity(legacy).toBytes();
      await source.writeAsBytes(original);
      for (final drawing in [RideDrawing.none, RideDrawing.smartSpin2k]) {
        late File copy;
        final result = await WorkoutFitExport.uploadSavedRide(
          source,
          RideMapSettings(drawing: drawing, center: center),
          (path) async {
            copy = File(path);
            final fit = FitFile.fromBytes(await copy.readAsBytes());
            final samples = fit.records
                .map((r) => r.message)
                .whereType<RecordMessage>();
            expect(samples.map((r) => r.power), everyElement(210));
            expect(samples.last.distance, closeTo(17.8, .1));
            expect(samples.last.speed, closeTo(8.9, .1));
            if (drawing == RideDrawing.none) {
              expect(samples.map((r) => r.positionLat), everyElement(isNull));
              expect(samples.map((r) => r.positionLong), everyElement(isNull));
            } else {
              expect(samples.last.positionLat, closeTo(center.lat, .1));
              expect(samples.last.positionLong, closeTo(center.lon, .1));
            }
            return true;
          },
        );
        expect(result, isTrue);
        expect(await copy.exists(), isFalse);
        expect(await source.readAsBytes(), original);
      }
    },
  );
}
