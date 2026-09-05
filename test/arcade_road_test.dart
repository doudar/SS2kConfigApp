import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_road.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

WorkoutSegment _sector(int duration, double power) => WorkoutSegment(
  type: SegmentType.steadyState,
  duration: duration,
  powerLow: power,
);

void main() {
  test(
    'ramp terrain follows time at the rider while remaining distance changes',
    () {
      final ramp = WorkoutSegment(
        type: SegmentType.warmup,
        duration: 10,
        powerLow: .4,
        powerHigh: 1.2,
        isRamp: true,
      );
      final road = ArcadeRoad();
      final route = [
        ramp,
        WorkoutSegment(
          type: SegmentType.cooldown,
          duration: 10,
          powerLow: .4,
          powerHigh: 1.2,
          isRamp: true,
        ),
      ];
      void sample(double seconds, double watts) => road.update(
        segments: route,
        seconds: seconds,
        watts: watts,
        ftp: 200,
        playing: true,
      );
      for (var i = 0; i <= 5; i++) sample(i.toDouble(), 200);
      final before = road.snapshot();
      expect(before.powerAt(before.position), closeTo(.8, 1e-9));
      sample(5, 400);
      final faster = road.snapshot();
      expect(faster.position, before.position);
      expect(faster.spans.first.end, greaterThan(before.spans.first.end));
      expect(faster.powerAt(faster.position), closeTo(.8, 1e-9));
      final pieces = faster.pieces(9, 11).toList();
      expect(pieces, hasLength(2));
      expect(pieces.first.endPower, closeTo(.8, 1e-9));
      expect(pieces.last.startPower, closeTo(.8, 1e-9));
      expect(pieces.first.startPower, lessThan(pieces.last.endPower));
      expect(faster.pieces(29, 30).last.endPower, closeTo(1.2, 1e-9));
      // The following cooldown starts high, then falls along its road span.
      expect(faster.powerAt(30), closeTo(1.2, 1e-9));
      expect(faster.powerAt(35), lessThan(faster.powerAt(30)));
    },
  );
  late ArcadeRoad road;
  late List<WorkoutSegment> segments;
  void sample(
    double time, {
    double watts = 200,
    double ftp = 200,
    bool playing = true,
  }) => road.update(
    segments: segments,
    seconds: time,
    watts: watts,
    ftp: ftp,
    playing: playing,
  );
  setUp(() {
    road = ArcadeRoad();
    segments = [_sector(5, 1), _sector(10, .5), _sector(5, 1.5)];
  });

  test(
    'visual speed scales with actual output / FTP, not target or cadence',
    () {
      expect(arcadeRoadSpeed(100, 200), 1);
      expect(arcadeRoadSpeed(200, 200), 2);
      expect(arcadeRoadSpeed(300, 200), 3);
      expect(arcadeRoadSpeed(200, 400), 1);
      expect(arcadeRoadSpeed(200, 200) / (1 / 6), 12);
      for (final pair in [
        (0.0, 200.0),
        (-10.0, 200.0),
        (200.0, 0.0),
        (double.nan, 200.0),
      ]) {
        expect(arcadeRoadSpeed(pair.$1, pair.$2), 0);
      }
    },
  );

  test('remaining road stretches with power without moving ridden terrain', () {
    for (var t = 0; t <= 4; t++) sample(t.toDouble());
    expect(road.snapshot().position, 8);
    expect(road.snapshot().spans.first.end, 10);
    sample(4, watts: 400);
    expect(road.snapshot().position, 8);
    expect(road.snapshot().spans.first.end, 12);
    expect(road.snapshot().spans[1].start, 12);
    expect(road.snapshot().spans[1].length, 10);
    sample(4, watts: 100);
    expect(road.snapshot().position, 8);
    expect(road.snapshot().spans.first.end, 9);
    sample(4, watts: 400);
    sample(5, watts: 100);
    expect(road.snapshot().position, 12);
    expect(road.snapshot().currentIndex, 1);
    expect(road.snapshot().spans.first.end, 12);
    expect(road.snapshot().spans[1].start, 12);
    sample(6, watts: 200);
    expect(road.snapshot().position, 13);
    expect(
      road.snapshot().spans.first.end,
      12,
      reason: 'Completed road stays fixed',
    );
  });

  test(
    'rendered tiles split at the moving boundary, including sub-tile spans',
    () {
      for (var t = 0; t <= 4; t++) sample(t.toDouble());
      var pieces = road.snapshot().pieces(9, 11).toList();
      expect(pieces.map((p) => p.segment), [segments[0], segments[1]]);
      expect(pieces.first.end, 10);
      sample(4, watts: 400);
      pieces = road.snapshot().pieces(11, 13).toList();
      expect(pieces.first.end, 12);
      expect(pieces.last.start, 12);
      expect(road.snapshot().segmentAt(11.99), segments[0]);
      expect(road.snapshot().segmentAt(12), segments[1]);
    },
  );

  test(
    'interpolation is smooth, bounded and never crosses the interval early',
    () {
      sample(0);
      sample(1);
      expect(road.snapshot(aheadSeconds: .05).position, closeTo(2.1, 1e-9));
      expect(road.snapshot(aheadSeconds: 100).position, closeTo(2.2, 1e-9));
      sample(2);
      sample(3);
      sample(4);
      sample(4.98);
      final frame = road.snapshot(aheadSeconds: .1);
      expect(frame.position, closeTo(10, 1e-9));
      expect(frame.spans.first.end, closeTo(10, 1e-9));
      sample(5);
      expect(road.snapshot().position, closeTo(frame.position, 1e-9));
    },
  );

  test('pauses and skips do not turn skipped time into camera movement', () {
    sample(0);
    sample(1);
    sample(1, playing: false, watts: 0);
    expect(road.snapshot(aheadSeconds: .1).position, 2);
    expect(road.snapshot().spans.first.end, 10);
    sample(1);
    sample(2);
    expect(road.snapshot().position, 4);
    road.willSkip();
    sample(5);
    expect(road.snapshot().position, 4);
    expect(road.snapshot().spans[1].start, 4);
    sample(6);
    expect(road.snapshot().position, 6);
    sample(0, playing: false);
    expect(road.snapshot().position, 0);
  });

  test('zero power stops travel; an FTP change rescales only the future', () {
    sample(0);
    sample(1);
    sample(1, watts: 0);
    sample(2, watts: 0);
    expect(road.snapshot(aheadSeconds: .1).position, 2);
    sample(2, ftp: 400);
    expect(road.snapshot().speed, 1);
    expect(road.snapshot().spans.first.end, 5);
    sample(3, ftp: 400);
    expect(road.snapshot().position, 3);
  });

  test(
    'future ramps use their average intensity; empty/zero spans remain safe',
    () {
      segments = [
        _sector(5, 1),
        WorkoutSegment(
          type: SegmentType.cooldown,
          duration: 10,
          powerLow: .4,
          powerHigh: .8,
          isRamp: true,
        ),
        _sector(0, 1),
      ];
      sample(0);
      expect(road.snapshot().spans[1].length, closeTo(12, 1e-9));
      expect(road.snapshot().pieces(9, 30).toList(), hasLength(3));
      segments = [];
      sample(0);
      expect(road.snapshot().pieces(-12, 12), isEmpty);
      expect(road.snapshot().segmentAt(0), isNull);
    },
  );

  test('extending an endless ride preserves accumulated road distance', () {
    segments = [
      WorkoutSegment(type: SegmentType.freeRide, duration: 3600, powerLow: 0),
    ];
    sample(0);
    sample(1);
    segments = [
      WorkoutSegment(type: SegmentType.freeRide, duration: 7200, powerLow: 0),
    ];
    sample(2);
    expect(road.snapshot().position, 4);
    expect(road.snapshot().spans.first.end, 14400);
    // The controller extends unlimited free rides by replacing an item in place.
    segments[0] = WorkoutSegment(
      type: SegmentType.freeRide,
      duration: 10800,
      powerLow: 0,
    );
    sample(3);
    expect(road.snapshot().position, 6);
    expect(road.snapshot().spans.first.end, 21600);
  });
}
