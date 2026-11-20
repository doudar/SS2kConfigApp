import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_cues.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  late ArcadeSession game;
  late List<WorkoutSegment> segments;
  late List<ArcadeCue> heard;
  var seconds = 0.0;
  void step({
    double dt = .1,
    double watts = 240,
    bool playing = true,
    bool fresh = true,
    double? ridden,
  }) {
    seconds += dt;
    game.update(
      segments: segments,
      seconds: seconds,
      playing: playing,
      watts: watts,
      target: 240,
      freshSignal: fresh,
      endless: true,
      riddenSeconds: ridden,
    );
    heard.addAll(game.cues);
  }

  void advance(double duration, {double watts = 240, bool fresh = true}) {
    for (var i = 0; i < (duration * 10).round(); i++) {
      step(watts: watts, fresh: fresh);
    }
  }

  void shoot() {
    final shown = game.drones.snapshot();
    expect(
      game.fireDrone(
        serial: shown.serial,
        hit: true,
        aimX: .5,
        aimY: .3,
        shownClock: shown.clock,
      ),
      true,
    );
    heard.addAll(game.cues);
  }

  setUp(() {
    game = ArcadeSession(drones: ArcadeDrones(random: math.Random(42)))
      ..droneInteractionEnabled = true;
    segments = [
      WorkoutSegment(
        type: SegmentType.steadyState,
        duration: 300,
        powerLow: 1.2,
      ),
    ];
    heard = [];
    seconds = 0;
    step(dt: 0);
    game.openingSeen = true;
    heard.clear();
  });

  test('charge, warning and armor hit are distinct and emitted once', () {
    advance(6);
    expect(heard.where((c) => c == ArcadeCue.blasterReady), hasLength(1));
    heard.clear();
    advance(6.2, watts: 0);
    expect(heard.where((c) => c == ArcadeCue.attackWarning), hasLength(1));
    step(dt: 0);
    step(dt: 0, playing: false);
    expect(heard.where((c) => c == ArcadeCue.attackWarning), hasLength(1));
    step(dt: 0);
    shoot();
    expect(heard.last, ArcadeCue.bolt);
    advance(.5);
    expect(heard.where((c) => c == ArcadeCue.bossHit), hasLength(1));
    expect(heard, isNot(contains(ArcadeCue.droneHit)));
  });

  test('a hit before the warning cancels that warning', () {
    advance(6);
    shoot();
    advance(2);
    expect(heard, isNot(contains(ArcadeCue.attackWarning)));
  });

  test('arrivals and destruction have one cue per encounter', () {
    segments = [
      WorkoutSegment(type: SegmentType.freeRide, duration: 600, powerLow: .7),
    ];
    step(dt: 0);
    game.openingSeen = true;
    heard.clear();
    for (var i = 0; i < 500 && !game.drones.snapshot().ready; i++) {
      step();
    }
    expect(game.drones.snapshot().ready, true);
    expect(heard.where((c) => c == ArcadeCue.enemyArrive), hasLength(1));
    expect(heard.where((c) => c == ArcadeCue.blasterReady), hasLength(1));
    shoot();
    advance(.5);
    expect(heard.where((c) => c == ArcadeCue.droneHit), hasLength(1));
  });

  test(
    'combo loss sounds once after the grace period, never for stale data',
    () {
      advance(16);
      heard.clear();
      advance(2.9, watts: 0);
      expect(heard, isNot(contains(ArcadeCue.comboLost)));
      advance(2.1, watts: 0);
      expect(heard.where((c) => c == ArcadeCue.comboLost), hasLength(1));
      advance(16);
      heard.clear();
      advance(5, fresh: false);
      expect(heard, isNot(contains(ArcadeCue.comboLost)));
    },
  );

  test('sector and difficulty cues require forward progress, not skipping', () {
    segments = [
      WorkoutSegment(type: SegmentType.steadyState, duration: 5, powerLow: .5),
      WorkoutSegment(
        type: SegmentType.steadyState,
        duration: 600,
        powerLow: .7,
      ),
    ];
    step(dt: 0);
    heard.clear();
    advance(5.1);
    expect(heard.where((c) => c == ArcadeCue.sectorStart), hasLength(1));
    step(ridden: 479.9);
    heard.clear();
    step(ridden: 480);
    step(dt: 0, ridden: 480);
    expect(heard.where((c) => c == ArcadeCue.difficultyUp), hasLength(1));
    heard.clear();
    game.willSkip();
    step(dt: 100, ridden: 960);
    expect(heard, isEmpty);
  });
}
