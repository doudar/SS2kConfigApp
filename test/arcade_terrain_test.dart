import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_terrain.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_road.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  WorkoutSegment sector(double power) => WorkoutSegment(
    type: SegmentType.steadyState,
    duration: 30,
    powerLow: power,
  );

  test(
    'checkpoint joins are continuous with climbs and descents after the banner',
    () {
      final spans = [
        ArcadeRoadSpan(sector(.5), 0, 20),
        ArcadeRoadSpan(sector(1.2), 20, 40),
        ArcadeRoadSpan(sector(.4), 40, 60),
      ];
      final road = ArcadeRoadSnapshot(
        position: 10,
        speed: 2,
        spans: spans,
        currentIndex: 0,
      );
      final terrain = ArcadeTerrainProfile(road, 1, reducedMotion: true);
      for (final boundary in [20.0, 40.0]) {
        expect(
          terrain.heightAt(boundary - 1e-6),
          closeTo(terrain.heightAt(boundary), 1e-4),
        );
        expect(
          terrain.heightAt(boundary + 1e-6),
          closeTo(terrain.heightAt(boundary), 1e-4),
        );
      }
      expect(
        terrain.heightAt(20),
        ArcadeTerrain.height(.5, 20, 1, reducedMotion: true),
      );
      expect(terrain.heightAt(22), greaterThan(terrain.heightAt(20)));
      expect(
        terrain.heightAt(24),
        ArcadeTerrain.height(1.2, 24, 1, reducedMotion: true),
      );
      expect(terrain.heightAt(42), lessThan(terrain.heightAt(40)));
      expect(
        terrain.heightAt(44),
        ArcadeTerrain.height(.4, 44, 1, reducedMotion: true),
      );
    },
  );

  test('short and collapsed sections pass their reached elevation forward', () {
    final spans = [
      ArcadeRoadSpan(sector(.5), 0, 20),
      ArcadeRoadSpan(sector(1.4), 20, 21),
      ArcadeRoadSpan(sector(.2), 21, 21),
      ArcadeRoadSpan(sector(.8), 21, 40),
    ];
    final terrain = ArcadeTerrainProfile(
      ArcadeRoadSnapshot(
        position: 20.5,
        speed: 2,
        spans: spans,
        currentIndex: 1,
      ),
      1,
    );
    expect(terrain.heightAt(21 - 1e-6), closeTo(terrain.heightAt(21), 1e-4));
    expect(terrain.heightAt(21 + 1e-6), closeTo(terrain.heightAt(21), 1e-4));
    expect(terrain.heightAt(21), lessThan(ArcadeTerrain.height(1.4, 21, 1)));
  });

  test(
    'crossing a checkpoint and changing speed preserve the rider elevation',
    () {
      final spans = [
        ArcadeRoadSpan(sector(.5), 0, 20),
        ArcadeRoadSpan(sector(1.2), 20, 80),
      ];
      ArcadeTerrainProfile profile(
        int index,
        double position,
        List<ArcadeRoadSpan> route,
      ) => ArcadeTerrainProfile(
        ArcadeRoadSnapshot(
          position: position,
          speed: 2,
          spans: route,
          currentIndex: index,
        ),
        1,
      );
      expect(
        profile(0, 20, spans).heightAt(20),
        profile(1, 20, spans).heightAt(20),
      );
      expect(
        profile(1, 21, spans).heightAt(21),
        profile(1, 21, [
          spans.first,
          ArcadeRoadSpan(spans.last.segment, 20, 140),
        ]).heightAt(21),
      );
      final road = ArcadeRoadSnapshot(
        position: 20,
        speed: 2,
        spans: spans,
        currentIndex: 1,
      );
      expect(road.powerAt(20), 1.2); // ERG target still changes immediately.
      final pieces = road.pieces(23.5, 24.5).toList();
      expect(pieces.map((piece) => piece.end), [24, 24.5]);
    },
  );

  test('relief stays bounded and does not reverse the projected road', () {
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (var i = -2000; i < 2000; i++) {
      final distance = i / 10;
      final height = ArcadeTerrain.relief(distance);
      if (height < low) low = height;
      if (height > high) high = height;
      expect(height, inInclusiveRange(0, 28));
      final grade = (ArcadeTerrain.relief(distance + .1) - height) / .1;
      expect(grade.abs(), lessThanOrEqualTo(2.65));
    }
    expect(high - low, greaterThan(25));
  });

  test(
    'power changes stretch the road without regenerating the rider hill',
    () {
      final road = ArcadeRoad();
      final segments = [
        WorkoutSegment(
          type: SegmentType.steadyState,
          duration: 180,
          powerLow: .75,
        ),
      ];
      void update(double seconds, double watts, bool playing) => road.update(
        segments: segments,
        seconds: seconds,
        watts: watts,
        ftp: 200,
        playing: playing,
      );
      update(0, 200, true);
      update(1, 200, true);
      final before = road.snapshot();
      final height = ArcadeTerrain.height(
        before.powerAt(before.position),
        before.position,
        1,
      );
      update(1, 400, true);
      final faster = road.snapshot();
      expect(faster.spans.single.end, greaterThan(before.spans.single.end));
      expect(
        ArcadeTerrain.height(
          faster.powerAt(faster.position),
          faster.position,
          1,
        ),
        height,
      );
      update(1, 400, false);
      final paused = road.snapshot(aheadSeconds: .1);
      expect(
        ArcadeTerrain.height(
          paused.powerAt(paused.position),
          paused.position,
          1,
        ),
        height,
      );
    },
  );

  test(
    'intensity remains readable and reduced motion removes rolling relief',
    () {
      for (final distance in [0.0, 20.0, 55.0, 100.0]) {
        expect(
          ArcadeTerrain.height(1.2, distance, 1),
          greaterThan(ArcadeTerrain.height(.5, distance, 1) + 20),
        );
        expect(
          ArcadeTerrain.height(.75, distance, 1, reducedMotion: true),
          ArcadeTerrain.height(.75, 0, 1, reducedMotion: true),
        );
      }
      expect(
        ArcadeTerrain.height(double.nan, double.infinity, 1).isFinite,
        isTrue,
      );
    },
  );
}
