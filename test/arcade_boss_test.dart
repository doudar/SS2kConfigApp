import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_cues.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  test('a boss bypasses a pending drone arrival gap', () {
    final combat = ArcadeDrones();
    combat.update(
      seconds: 0,
      playing: true,
      enabled: true,
      onTarget: true,
      sector: 0,
      style: ArcadeDroneStyle.wheel,
    );
    expect(combat.snapshot().phase, ArcadeDronePhase.rearming);
    combat.update(
      seconds: 0,
      playing: true,
      enabled: true,
      onTarget: true,
      sector: 1,
      style: ArcadeDroneStyle.golem,
      bossHits: 2,
    );
    expect(combat.snapshot().phase, ArcadeDronePhase.hovering);
    expect(combat.snapshot().requiredHits, 2);
    expect(combat.snapshot().charge, 0);
  });
  late ArcadeSession game;
  late List<WorkoutSegment> segments;
  double seconds = 0;
  WorkoutSegment hard(int duration) => WorkoutSegment(
    type: SegmentType.steadyState,
    duration: duration,
    powerLow: 1.2,
  );
  void step(double dt, {double watts = 240, bool fresh = true}) {
    seconds += dt;
    game.update(
      segments: segments,
      seconds: seconds,
      playing: true,
      watts: watts,
      target: 240,
      freshSignal: fresh,
    );
  }

  void advance(double duration, {double watts = 240, bool fresh = true}) {
    for (var i = 0; i < (duration * 10).round(); i++) {
      step(.1, watts: watts, fresh: fresh);
    }
  }

  void ready() {
    for (var i = 0; i < 100 && !game.drones.snapshot().ready; i++) {
      step(.1);
    }
    expect(game.drones.snapshot().ready, true);
  }

  bool fire({bool hit = true}) {
    final frame = game.drones.snapshot();
    return game.fireDrone(
      serial: frame.serial,
      hit: hit,
      aimX: .8,
      aimY: .25,
      shownClock: frame.clock,
    );
  }

  setUp(() {
    seconds = 0;
    segments = [hard(90), hard(90)];
    game = ArcadeSession()..droneInteractionEnabled = true;
    step(0);
  });

  test('boss shares charge and targeting; only landed shots remove armor', () {
    expect(game.drones.snapshot().isBoss, true);
    expect(game.drones.snapshot().requiredHits, 3);
    expect(fire(), false);
    for (var hit = 1; hit <= 3; hit++) {
      ready();
      expect(game.drones.snapshot().charge, 1);
      expect(game.drones.snapshot().hits, hit - 1);
      final before = game.score;
      expect(fire(), true);
      expect(game.cues, contains(ArcadeCue.bolt));
      expect(fire(), false);
      step(.45, watts: 0);
      expect(game.chargeFor(0, segments.first), closeTo(hit / 3, 1e-8));
      expect(game.score - before, hit == 3 ? 500 : 0);
    }
    expect(game.bossesDefeated, 1);
    expect(game.cleared, {0});
    expect(
      game.drones.destroyed,
      0,
      reason: 'Boss kills do not inflate the drone count',
    );
    expect(game.cues, contains(ArcadeCue.bossDefeat));
    final score = game.score;
    advance(3, watts: 0);
    expect(game.score, score);
    expect(game.bossesDefeated, 1);
    expect(game.drones.snapshot().visible, false);
  });

  test(
    'misses and expired shots counterattack once, then recharge the same boss',
    () {
      ready();
      final serial = game.drones.snapshot().serial;
      final before = game.score;
      expect(fire(hit: false), true);
      step(.45, watts: 0);
      expect(game.score, before - 50);
      expect(game.drones.snapshot().damage, 0);
      step(1.4, watts: 0);
      expect(game.drones.snapshot().phase, ArcadeDronePhase.hovering);
      ready();
      final beforeTimeout = game.score;
      advance(8, watts: 0);
      expect(game.score, beforeTimeout - 50);
      expect(game.drones.snapshot().serial, serial);
      expect(game.drones.snapshot().damage, 0);
      expect(game.bossesDefeated, 0);
    },
  );

  test('hidden views and stale telemetry freeze the boss shot window', () {
    ready();
    final before = game.drones.snapshot();
    game.droneInteractionEnabled = false;
    advance(10, watts: 0);
    expect(game.drones.snapshot().age, before.age);
    expect(fire(), false);
    game.droneInteractionEnabled = true;
    advance(10, fresh: false);
    expect(game.drones.snapshot().age, before.age);
    expect(fire(), false);
    step(0);
    expect(fire(), true);
  });

  test(
    'a finishing shot crossing sectors rewards the old boss, not the new one',
    () {
      segments = [hard(10), hard(60)];
      seconds = 0;
      step(0);
      ready();
      while (seconds < 9.8) {
        step(.1, watts: 0);
      }
      expect(fire(), true);
      step(.45, watts: 0);
      expect(game.cleared, {0});
      expect(game.bossesDefeated, 1);
      step(1.1, watts: 0);
      step(.1, watts: 0);
      expect(game.drones.snapshot().sector, 1);
      expect(game.drones.snapshot().hits, 0);
      expect(game.drones.snapshot().requiredHits, 2);
      expect(game.chargeFor(1, segments[1]), 0);
    },
  );
}
