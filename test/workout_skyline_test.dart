import 'dart:io';
import 'dart:math' as math;

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';
import 'package:ss2kconfigapp/utils/workout/ride_map.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_fit_export.dart';
import 'package:ss2kconfigapp/utils/workout/workout_skyline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const settings = RideMapSettings(drawing: RideDrawing.skyline);

  for (final seconds in [1, 2, 3, 4, 5]) {
    test('$seconds recorded seconds survive saving and re-export', () async {
      final temp = await Directory.systemTemp.createTemp('short_ride');
      addTearDown(() => temp.delete(recursive: true));
      final points = List.generate(
        seconds,
        (i) => TrackPoint(
          timestamp: DateTime.utc(2026, 11, 26).add(Duration(seconds: i)),
          speed: 10,
          power: 140 + i,
          heartRate: 120,
          cadence: 91,
          elevation: 100,
          lat: 0,
          lon: 0,
        ),
      );
      final records = WorkoutFitExport.records(points, settings, ftp: 250);
      final file = File('${temp.path}/ride.fit');
      await file.writeAsBytes(
        GpxToFitConverter.buildActivity(records, ftp: 250).toBytes(),
      );
      Future<bool> verify(String path) async {
        final fit = FitFile.fromBytes(await File(path).readAsBytes());
        final samples = fit.records
            .map((r) => r.message)
            .whereType<RecordMessage>()
            .toList();
        expect(samples.length, seconds);
        expect(samples.map((r) => r.power), points.map((p) => p.power));
        expect(samples.map((r) => r.heartRate), everyElement(120));
        expect(samples.map((r) => r.cadence), everyElement(91));
        expect(samples.last.distance, seconds * 10);
        expect(samples.map((r) => r.positionLat), everyElement(isNull));
        expect(samples.map((r) => r.positionLong), everyElement(isNull));
        return true;
      }

      await verify(file.path);
      expect(
        await WorkoutFitExport.uploadSavedRide(file, settings, verify),
        isTrue,
      );
    });
  }

  test('recorded active seconds supply the skyline and baseline stats', () {
    // Alternating coasting and 300 W yields 150 W in each 30-second NP window.
    final watts = List.generate(3600, (i) => i.isEven ? 0 : 300);
    final skyline = WorkoutSkyline.fromRide(watts, ftp: 200);
    expect(skyline.averageWatts, 150);
    expect(skyline.tss, 56.25);
    expect(skyline.label, 'AVG 150W   56 TSS');
    expect(skyline.toPath().computeMetrics().single.isClosed, isTrue);
    expect(WorkoutSkyline.fromRide([0, 0], ftp: 200).label, 'AVG 0W   0 TSS');
    expect(WorkoutSkyline.fromRide([200], savedTss: 74).tss, 74);
    for (int digit = 0; digit < 10; digit++) {
      final outline = WorkoutSkyline(
        skyline.profile,
        digit,
        digit.toDouble(),
      ).toPath().computeMetrics().single;
      expect(outline.isClosed, isTrue);
    }
  });

  test(
    'recorded roof shows a 30-second rolling mean for every active second',
    () {
      final power = List<int?>.filled(3600, 100);
      power.fillRange(1700, 1730, 400);
      power[100] = null;
      power[101] = 0;
      final profile = WorkoutSkyline.fromRide(power).profile;
      expect(profile.length, 3600);
      expect(profile.first, const Offset(0, 100));
      expect(profile[100].dy, 100);
      expect(profile[101].dy, closeTo(2800 / 29, .0001));
      expect(profile[1700].dy, 110);
      expect(profile[1729], Offset(1729 / 3599, 400));
      expect(profile[1730].dy, 390);
      expect(profile[1759].dy, 100);
      expect(profile.last, const Offset(1, 100));
    },
  );

  test(
    'FIT maps close once at ride distance, preserving samples across a pause',
    () async {
      final start = DateTime.utc(2026, 11, 26);
      final points = List.generate(
        1200,
        (i) => TrackPoint(
          timestamp: start.add(Duration(seconds: i + (i >= 300 ? 1800 : 0))),
          lat: 0,
          lon: 0,
          elevation: 120,
          heartRate: 144,
          cadence: 80,
          power: i < 600 ? 100 : 200,
          speed: 8,
        ),
      );
      final samples = WorkoutFitExport.records(points, settings, ftp: 200);
      final expectedStats = WorkoutSkyline.fromRide(
        points.map((p) => p.power).toList(),
        ftp: 200,
      );
      final route = RideMapRoute.forRide(
        settings,
        start,
        skyline: expectedStats,
        skylineDistance: 1200 * 8,
      )!;
      expect(samples.length, 1200);
      final positions = route
          .positionsForClosedRide(List.generate(1200, (i) => i / 1199))
          .toList();
      var gpsMeters = 0.0;
      const radians = math.pi / 180;
      for (var i = 1; i < samples.length; i++) {
        final a = samples[i - 1], b = samples[i];
        final north = (b.positionLat! - a.positionLat!) * radians;
        final east =
            (b.positionLong! - a.positionLong!) *
            radians *
            math.cos((b.positionLat! + a.positionLat!) * radians / 2);
        gpsMeters +=
            math.sqrt(north * north + east * east) * RideMapRoute.earthRadius;
      }
      expect(gpsMeters, closeTo(samples.last.distance!, 2));
      for (final i in [0, 1, 200, 350, 450, 525, 1000, 1199]) {
        final pos = positions[i];
        expect(samples[i].positionLat, closeTo(pos.lat, 1e-7));
        expect(samples[i].positionLong, closeTo(pos.lon, 1e-7));
        expect(
          samples[i].timestamp,
          points[i].timestamp.millisecondsSinceEpoch,
        );
        expect(samples[i].distance, (i + 1) * 8);
      }
      expect(samples.last.positionLat, samples.first.positionLat);
      expect(samples.last.positionLong, samples.first.positionLong);
      final dir = await Directory.systemTemp.createTemp('skyline_fit');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ride.fit');
      // Save without GPS, then choose the skyline from Past rides. Its original
      // FTP and measured power should reproduce the same GPS trace.
      final plain = WorkoutFitExport.records(
        points,
        const RideMapSettings(drawing: RideDrawing.none),
      );
      await file.writeAsBytes(
        GpxToFitConverter.buildActivity(plain, ftp: 200).toBytes(),
      );
      // Older builds sometimes left a target profile next to the FIT.
      await File('${file.path}.plan.json').writeAsString('[[0,1],[1,1]]');
      await WorkoutFitExport.uploadSavedRide(file, settings, (path) async {
        final fit = FitFile.fromBytes(await File(path).readAsBytes());
        final uploaded = fit.records
            .map((r) => r.message)
            .whereType<RecordMessage>()
            .toList();
        expect(
          uploaded.map((r) => r.positionLat),
          samples.map((r) => r.positionLat),
        );
        expect(
          uploaded.map((r) => r.positionLong),
          samples.map((r) => r.positionLong),
        );
        expect(uploaded.last.distance, 9600);
        return true;
      }, fallbackFtp: 300);
    },
  );

  test(
    'a saved ride without power exports its metrics without a skyline',
    () async {
      final dir = await Directory.systemTemp.createTemp('no_power_fit');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ride.fit');
      final start = DateTime.utc(2026, 11, 26);
      final records = List.generate(
        90,
        (i) => RecordMessage()
          ..timestamp = start.add(Duration(seconds: i)).millisecondsSinceEpoch
          ..heartRate = 140
          ..distance = i * 8.0,
      );
      await file.writeAsBytes(
        GpxToFitConverter.buildActivity(records).toBytes(),
      );
      await WorkoutFitExport.uploadSavedRide(file, const RideMapSettings(), (
        path,
      ) async {
        final copy = FitFile.fromBytes(await File(path).readAsBytes());
        final samples = copy.records
            .map((r) => r.message)
            .whereType<RecordMessage>();
        expect(samples.length, records.length);
        expect(samples.map((r) => r.positionLat), everyElement(isNull));
        expect(samples.map((r) => r.heartRate), everyElement(140));
        expect(samples.last.distance, records.last.distance);
        return true;
      });
    },
  );

  test(
    'short and sparse rides use only the detail their GPS spacing supports',
    () {
      final start = DateTime.utc(2026, 11, 26);
      List<RecordMessage> ride(int count, double speed, {int idle = 0}) =>
          WorkoutFitExport.records(
            List.generate(
              count,
              (i) => TrackPoint(
                timestamp: start.add(Duration(seconds: i)),
                lat: 0,
                lon: 0,
                elevation: 100,
                heartRate: 140,
                cadence: 80,
                power: 150,
                speed: i < idle ? 0 : speed,
              ),
            ),
            settings,
            ftp: 200,
          );
      for (final records in [
        ride(90, 8),
        ride(1200, .25),
        ride(1200, 8, idle: 1100),
      ]) {
        final total = records.last.distance!;
        final first = records.first.distance!;
        final silhouette = RideMapRoute.forRide(
          settings,
          start,
          skyline: WorkoutSkyline.fromRide(
            records.map((r) => r.power).toList(),
          ),
          skylineDistance: total,
          includeLettering: false,
        )!;
        final positions = silhouette
            .positionsForClosedRide(
              records.map((r) => (r.distance! - first) / (total - first)),
            )
            .toList();
        expect(positions.length, records.length);
        for (var i = 0; i < records.length; i++) {
          final r = records[i], p = positions[i];
          expect(r.positionLat, closeTo(p.lat, 1e-7));
          expect(r.positionLong, closeTo(p.lon, 1e-7));
        }
      }
      for (final records in [
        ride(5, 10),
        ride(90, .25),
        ride(1200, 8, idle: 1198),
      ]) {
        expect(
          records.every((r) => r.positionLat == null && r.positionLong == null),
          isTrue,
        );
        expect(records.last.distance, greaterThan(0));
        expect(records.last.power, 150);
      }
    },
  );

  test(
    'new random rides include the skyline; a stationary ride adds no GPS distance',
    () {
      final start = DateTime.utc(2026, 11, 26);
      final day = List.generate(100, (i) => start.add(Duration(days: i)))
          .firstWhere(
            (d) =>
                RideDrawing.random.forRide(d, includeSkyline: true) ==
                RideDrawing.skyline,
          );
      final points = List.generate(
        120,
        (i) => TrackPoint(
          timestamp: day.add(Duration(seconds: i)),
          lat: 0,
          lon: 0,
          elevation: 0,
          heartRate: 130,
          cadence: 85,
          power: 200,
          speed: 8,
        ),
      );
      final random = WorkoutFitExport.records(
        points,
        const RideMapSettings(drawing: RideDrawing.random),
        ftp: 200,
      );
      final chosen = WorkoutFitExport.records(points, settings, ftp: 200);
      expect(
        random.map((r) => r.positionLat),
        chosen.map((r) => r.positionLat),
      );
      final stationary = TrackPoint(
        timestamp: day,
        lat: 0,
        lon: 0,
        elevation: 0,
        heartRate: 0,
        cadence: 0,
        power: 0,
        speed: 0,
      );
      final sample = WorkoutFitExport.records(
        [stationary],
        settings,
        ftp: 200,
      ).single;
      expect(sample.positionLat, isNull);
      expect(sample.distance, 0);
    },
  );
}
