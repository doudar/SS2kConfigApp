import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

WorkoutSegment sector(double power, {int duration = 100}) => WorkoutSegment(
  type: SegmentType.steadyState,
  duration: duration,
  powerLow: power,
);

void main() {
  test(
    'workout intensities produce distinct worlds, including recovery ramps',
    () {
      expect(biomeFor(sector(.5)), ArcadeBiome.grove);
      expect(biomeFor(sector(.7)), ArcadeBiome.coast);
      expect(biomeFor(sector(.95)), ArcadeBiome.neon);
      expect(biomeFor(sector(1.2)), ArcadeBiome.volcano);
      expect(
        biomeFor(
          WorkoutSegment(
            type: SegmentType.cooldown,
            duration: 60,
            powerLow: .4,
            powerHigh: .7,
            isRamp: true,
          ),
        ),
        ArcadeBiome.grove,
      );
    },
  );

  late ArcadeSession game;
  late List<WorkoutSegment> segments;
  void sample(
    double t, {
    bool playing = true,
    double watts = 200,
    double target = 200,
    bool fresh = true,
  }) => game.update(
    segments: segments,
    seconds: t,
    playing: playing,
    watts: watts,
    target: target,
    freshSignal: fresh,
  );
  setUp(() {
    game = ArcadeSession();
    segments = [sector(1.2)];
  });

  test(
    'sustained target builds capped combos and awards one boss per sector',
    () {
      for (var second = 0; second <= 90; second++) sample(second.toDouble());
      expect(game.combo, 4);
      expect(game.bossesDefeated, 1);
      expect(game.cleared, {0});
      expect(game.chargeFor(0, segments.first), 1);
      expect(game.score, greaterThan(2000));
      final score = game.score;
      sample(91);
      expect(game.score - score, 40, reason: 'Boss reward must not repeat');
    },
  );

  test('overpower, zero power and stale telemetry do not earn energy', () {
    sample(0);
    sample(1, watts: 250);
    sample(2, watts: 0);
    sample(3, fresh: false);
    expect(game.score, 0);
    expect(game.chargeFor(0, segments.first), 0);
    sample(4, watts: 210);
    expect(game.score, 10);
  });

  test(
    'recovery earns the same points and settling grace protects a combo',
    () {
      segments = [sector(.5)];
      for (var i = 0; i <= 16; i++)
        sample(i.toDouble(), watts: 100, target: 100);
      expect(game.combo, 2);
      sample(17, watts: 130, target: 100);
      sample(18, watts: 130, target: 100);
      sample(19, watts: 130, target: 100);
      expect(game.combo, 2);
      sample(20, watts: 130, target: 100);
      expect(game.combo, 1);
    },
  );

  test('pause, repeated callbacks and a resume never backfill points', () {
    sample(0);
    sample(1);
    final score = game.score;
    sample(1, playing: false);
    sample(1, playing: false);
    sample(1);
    expect(game.score, score);
    sample(2);
    expect(game.score, score + 10);
    sample(50);
    expect(
      game.score,
      score + 10,
      reason: 'Large clock jumps are not ridden time',
    );
  });

  test('skip including a subsecond skip earns no credit or completion', () {
    segments = [sector(1.2, duration: 10), sector(.5, duration: 10)];
    sample(0);
    sample(1);
    game.willSkip();
    sample(10);
    expect(game.score, 10);
    expect(game.cleared, isEmpty);
    sample(19.5);
    game.willSkip();
    sample(20, playing: false);
    expect(game.finished, false);
    expect(game.score, 10);
  });

  test('natural end records completion and a restart clears the quest', () {
    segments = [sector(.5, duration: 10)];
    for (var i = 0; i < 10; i++) sample(i.toDouble());
    sample(10, playing: false);
    expect(game.finished, true);
    expect(game.cleared, {0});
    sample(0, playing: false);
    expect(game.finished, false);
    expect(game.score, 0);
    expect(game.cleared, isEmpty);
  });

  test('load resets rewards; free ride has no ERG accuracy requirement', () {
    sample(0);
    sample(1);
    segments = [
      WorkoutSegment(type: SegmentType.freeRide, duration: 100, powerLow: 0),
    ];
    sample(0, target: 0);
    sample(1, target: 0, watts: 80);
    expect(game.score, 10);
    sample(2, target: 0, watts: 0);
    expect(game.score, 10);
  });

  test(
    'all original music assets are playable mono PCM with audible samples',
    () {
      for (final biome in ArcadeBiome.values) {
        final bytes = File(
          'assets/sounds/arcade_${biome.name}.wav',
        ).readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
        expect(data.getUint16(20, Endian.little), 1);
        expect(data.getUint16(22, Endian.little), 1);
        expect(data.getUint32(24, Endian.little), 22050);
        expect(data.getUint32(40, Endian.little), bytes.length - 44);
        var peak = 0;
        for (var i = 44; i < bytes.length; i += 2) {
          final value = data.getInt16(i, Endian.little).abs();
          if (value > peak) peak = value;
        }
        expect(peak, inInclusiveRange(5000, 32000));
      }
    },
  );
}
