import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_profile.dart';
import 'package:ss2kconfigapp/utils/workout/workout_painter.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';
import 'package:ss2kconfigapp/utils/workout/workout_zone_breakdown.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_road.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_world_painter.dart';

WorkoutSegment steady(double power) => WorkoutSegment(
  type: SegmentType.steadyState,
  duration: 60,
  powerLow: power,
);

void main() {
  test('display zone boundaries distinguish sweet spot, threshold and VO2', () {
    final cases = {
      .55: WorkoutPowerZone.recovery,
      .5501: WorkoutPowerZone.endurance,
      .75: WorkoutPowerZone.endurance,
      .7501: WorkoutPowerZone.tempo,
      .87: WorkoutPowerZone.tempo,
      .8701: WorkoutPowerZone.sweetSpot,
      .94: WorkoutPowerZone.sweetSpot,
      .9401: WorkoutPowerZone.threshold,
      1.05: WorkoutPowerZone.threshold,
      1.0501: WorkoutPowerZone.vo2max,
      1.2: WorkoutPowerZone.vo2max,
      1.2001: WorkoutPowerZone.anaerobic,
      -1.0: WorkoutPowerZone.selfPaced,
      double.nan: WorkoutPowerZone.selfPaced,
    };
    for (final entry in cases.entries) {
      expect(WorkoutPowerZone.forPower(entry.key), entry.value);
    }
  });

  testWidgets('all seven zone colors agree in profiles, durations and roads', (
    tester,
  ) async {
    const powers = [.5, .7, .8, .9, 1.0, 1.1, 1.3];
    final segments = powers.map(steady).toList();
    expect(WorkoutZoneTime(segments).seconds, [60, 60, 60, 60, 60, 60, 60, 0]);
    for (var i = 0; i < powers.length; i++) {
      final expected = WorkoutPowerZone.values[i].color;
      final road = ArcadeRoadSnapshot(
        position: 0,
        speed: 1,
        spans: [ArcadeRoadSpan(segments[i], 0, 10)],
        currentIndex: 0,
      );
      expect(arcadeRoadPowerColor(road, 5), expected);
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        WorkoutPainter.preview([
          segments[i],
        ]).paint(Canvas(recorder), const Size(100, 60));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 60);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!;
        final offset = (55 * 100 + 50) * 4;
        expect(data.getUint8(offset), closeTo(expected.r * 255, 2));
        expect(data.getUint8(offset + 1), closeTo(expected.g * 255, 2));
        expect(data.getUint8(offset + 2), closeTo(expected.b * 255, 2));
        image.dispose();
        picture.dispose();
      });
    }
  });

  test('ramp color crossings reverse with cooldowns and track road target', () {
    for (final type in [SegmentType.warmup, SegmentType.cooldown]) {
      final ramp = WorkoutSegment(
        type: type,
        duration: 100,
        powerLow: .4,
        powerHigh: 1.3,
        isRamp: true,
      );
      final stops = workoutZoneStops(ramp);
      expect(stops, hasLength(8));
      final seen = <WorkoutPowerZone>[];
      for (var i = 0; i < stops.length - 1; i++) {
        final progress = (stops[i] + stops[i + 1]) / 2;
        final zone = WorkoutPowerZone.forSegment(ramp, progress);
        seen.add(zone);
        final road = ArcadeRoadSnapshot(
          position: progress * 100,
          speed: 1,
          spans: [ArcadeRoadSpan(ramp, 0, 100)],
          currentIndex: 0,
          currentProgress: progress,
        );
        expect(arcadeRoadPowerColor(road, road.position), zone.color);
      }
      final expected = WorkoutPowerZone.values.take(7);
      expect(
        seen,
        type == SegmentType.cooldown ? expected.toList().reversed : expected,
      );
    }
    for (final type in [SegmentType.freeRide, SegmentType.maxEffort]) {
      final free = WorkoutSegment(type: type, duration: 60, powerLow: 1.3);
      expect(WorkoutPowerZone.forSegment(free), WorkoutPowerZone.selfPaced);
      expect(WorkoutZoneTime([free]).seconds.last, 60);
    }
  });
}
