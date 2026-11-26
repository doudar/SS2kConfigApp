import 'dart:io';

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';
import 'package:ss2kconfigapp/utils/workout/ride_map.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_fit_export.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';
import 'package:ss2kconfigapp/utils/workout/workout_skyline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plan = skylinePlan([
    WorkoutSegment(
      type: SegmentType.warmup,
      duration: 150,
      powerLow: .5,
      powerHigh: 1,
      isRamp: true,
    ),
    WorkoutSegment(type: SegmentType.steadyState, duration: 150, powerLow: .6),
  ]);
  const settings = RideMapSettings(drawing: RideDrawing.skyline);

  test(
    'target ramps and steps set the roof; only actual active seconds set the stats',
    () {
      expect(plan, [
        const Offset(0, .5),
        const Offset(.5, 1),
        const Offset(.5, .6),
        const Offset(1, .6),
      ]);
      // Alternating coasting and 300 W yields 150 W in each 30-second NP window.
      final watts = List.generate(3600, (i) => i.isEven ? 0 : 300);
      final skyline = WorkoutSkyline.fromRide(watts, plan: plan, ftp: 200);
      expect(skyline.averageWatts, 150);
      expect(skyline.tss, 56.25);
      expect(skyline.label, 'AVG 150W   56 TSS');
      expect(skyline.toPath().computeMetrics().single.isClosed, isTrue);
      expect(
        WorkoutSkyline.fromRide(watts, plan: [], ftp: 200).profile,
        isNot(plan),
      );
      expect(
        WorkoutSkyline.fromRide([0, 0], plan: [], ftp: 200).label,
        'AVG 0W   0 TSS',
      );
      expect(WorkoutSkyline.fromRide([200], plan: [], savedTss: 74).tss, 74);
      for (int digit = 0; digit < 10; digit++) {
        final outline = WorkoutSkyline(
          plan,
          digit,
          digit.toDouble(),
        ).toPath().computeMetrics().single;
        expect(outline.isClosed, isTrue);
      }
    },
  );

  test(
    'FIT maps close once at ride distance, preserving samples across a pause',
    () async {
      final start = DateTime.utc(2026, 11, 26);
      final points = List.generate(
        600,
        (i) => TrackPoint(
          timestamp: start.add(Duration(seconds: i + (i >= 300 ? 1800 : 0))),
          lat: 0,
          lon: 0,
          elevation: 120,
          heartRate: 144,
          cadence: 80,
          power: 150,
          speed: 8,
        ),
      );
      final samples = WorkoutFitExport.records(
        points,
        settings,
        plan: plan,
        ftp: 200,
      );
      final expectedStats = WorkoutSkyline(plan, 150, 600 / 36 * .75 * .75);
      final route = RideMapRoute.forRide(
        settings,
        start,
        skyline: expectedStats,
        skylineDistance: 599 * 8,
      )!;
      expect(samples.length, 600);
      for (final i in [0, 1, 200, 350, 450, 525, 599]) {
        final pos = route.position(i * 8);
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
      // plan and FTP must win over the new FTP and the measured flat power line.
      final plain = WorkoutFitExport.records(
        points,
        const RideMapSettings(drawing: RideDrawing.none),
      );
      await file.writeAsBytes(
        GpxToFitConverter.buildActivity(plain, ftp: 200).toBytes(),
      );
      await WorkoutFitExport.savePlan(file.path, plan);
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
        expect(uploaded.last.distance, 4800);
        return true;
      }, fallbackFtp: 300);
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
        const RideMapSettings(),
        plan: plan,
        ftp: 200,
      );
      final chosen = WorkoutFitExport.records(
        points,
        settings,
        plan: plan,
        ftp: 200,
      );
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
