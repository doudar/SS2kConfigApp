import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  late ArcadeDrones drones;
  List<ArcadeDroneEvent> tick(
    double time, {
    bool onTarget = true,
    bool playing = true,
    bool enabled = true,
    int sector = 0,
    bool skipped = false,
  }) => drones.update(
    seconds: time,
    playing: playing,
    enabled: enabled,
    onTarget: onTarget,
    sector: sector,
    style: ArcadeDroneStyle.wheel,
    skipped: skipped,
  );
  List<ArcadeDroneEvent> ride(double time, {bool onTarget = true}) {
    final events = <ArcadeDroneEvent>[];
    for (var i = 0; i < (time * 20).round(); i++) {
      events.addAll(tick(.05, onTarget: onTarget));
    }
    return events;
  }

  double until(ArcadeDronePhase phase, {bool onTarget = true}) {
    var elapsed = 0.0;
    while (drones.snapshot().phase != phase && elapsed < 45) {
      tick(.05, onTarget: onTarget);
      elapsed += .05;
    }
    expect(drones.snapshot().phase, phase);
    return elapsed;
  }

  List<ArcadeDroneEvent> fire({bool hit = true, int? serial}) {
    final frame = drones.snapshot();
    return drones.fire(
      serial: serial ?? frame.serial,
      hit: hit,
      aimX: .8,
      aimY: .2,
      shownClock: frame.clock,
    );
  }

  setUp(() {
    drones = ArcadeDrones(random: math.Random(42));
    tick(0);
  });

  test('arrivals have bounded random gaps, including the first encounter', () {
    expect(drones.snapshot().phase, ArcadeDronePhase.rearming);
    expect(drones.snapshot().visible, false);
    expect(ride(17.9), isEmpty);
    final firstGap = 17.9 + until(ArcadeDronePhase.entering);
    expect(firstGap, inInclusiveRange(18, 38.05));
    until(ArcadeDronePhase.ready);
    fire();
    tick(.45);
    tick(1.1);
    final secondGap = until(ArcadeDronePhase.entering);
    expect(secondGap, inInclusiveRange(18, 38.05));
    expect((firstGap - secondGap).abs(), greaterThan(.1));
    expect(drones.snapshot().serial, 2);
    expect(drones.snapshot().charge, lessThan(.02));
  });

  test('charging never auto-fires; a tap commits exactly one hit', () {
    expect(fire(), isEmpty);
    until(ArcadeDronePhase.ready);
    expect(drones.snapshot().charge, 1);
    expect(ride(1), isEmpty);
    expect(drones.destroyed, 0);
    expect(fire(serial: -1), isEmpty);
    expect(fire(), [ArcadeDroneEvent.fired]);
    expect(fire(), isEmpty);
    expect(drones.snapshot().phase, ArcadeDronePhase.firing);
    expect(tick(.45), [ArcadeDroneEvent.destroyed]);
    expect(drones.destroyed, 1);
    expect(drones.snapshot().phase, ArcadeDronePhase.exploding);
  });

  test('a miss keeps its aim, steals once, and escapes without a kill', () {
    until(ArcadeDronePhase.ready);
    expect(fire(hit: false), [ArcadeDroneEvent.fired]);
    expect(drones.snapshot().aimX, .8);
    expect(drones.snapshot().aimY, .2);
    expect(tick(.45), [ArcadeDroneEvent.escaped]);
    expect(drones.snapshot().stolePoints, true);
    expect(drones.snapshot().phase, ArcadeDronePhase.departing);
    expect(ride(3), isEmpty);
    expect(drones.destroyed, 0);
  });

  test('ignoring a full blaster or never charging both expire once', () {
    until(ArcadeDronePhase.ready);
    expect(ride(8), [ArcadeDroneEvent.escaped]);
    expect(fire(), isEmpty);
    drones.reset();
    tick(0);
    until(ArcadeDronePhase.hovering, onTarget: false);
    expect(ride(24, onTarget: false), [ArcadeDroneEvent.escaped]);
    expect(drones.destroyed, 0);
  });

  test('pause and rejected time freeze the shot window', () {
    until(ArcadeDronePhase.ready);
    final before = drones.snapshot();
    tick(1, playing: false);
    expect(fire(), isEmpty);
    expect(drones.snapshot(aheadSeconds: 1).clock, before.clock);
    expect(drones.snapshot().age, before.age);
    expect(tick(20), isEmpty);
    expect(drones.snapshot().age, before.age);
    expect(fire(), [ArcadeDroneEvent.fired]);
  });

  test('sector changes and skips release an unshot drone without theft', () {
    until(ArcadeDronePhase.entering);
    tick(.5);
    final before = drones.snapshot();
    expect(tick(0, sector: 1), isEmpty);
    expect(
      drones.snapshot().departureEntry,
      closeTo(before.age / ArcadeDrones.entrySeconds, 1e-8),
    );
    expect(drones.snapshot().lockClock, before.clock);
    expect(drones.snapshot().stolePoints, false);
    expect(tick(1.4, sector: 1, enabled: false), isEmpty);
    expect(drones.snapshot().phase, ArcadeDronePhase.dormant);
    tick(0);
    until(ArcadeDronePhase.ready);
    expect(tick(.5, skipped: true), isEmpty);
    expect(drones.snapshot().phase, ArcadeDronePhase.departing);
    expect(drones.snapshot().stolePoints, false);
  });

  test(
    'committed shots finish across sector changes; rendering is read-only',
    () {
      until(ArcadeDronePhase.ready);
      fire();
      drones.snapshot(aheadSeconds: 1000);
      expect(drones.destroyed, 0);
      expect(tick(.45, sector: 1, enabled: false), [
        ArcadeDroneEvent.destroyed,
      ]);
      tick(1.1, sector: 1, enabled: false);
      expect(drones.snapshot().visible, false);
    },
  );

  group('session theft and interaction', () {
    late ArcadeSession session;
    late List<WorkoutSegment> segments;
    double seconds = 0;
    void sample({bool fresh = true, double watts = 140}) {
      session.update(
        segments: segments,
        seconds: seconds,
        playing: true,
        watts: watts,
        target: 140,
        freshSignal: fresh,
        endless: true,
      );
    }

    void advance(double duration, {bool fresh = true, double watts = 140}) {
      for (var i = 0; i < (duration * 20).round(); i++) {
        seconds += .05;
        sample(fresh: fresh, watts: watts);
      }
    }

    void charge() {
      for (var i = 0; i < 1000 && !session.drones.snapshot().ready; i++) {
        advance(.05);
      }
      expect(session.drones.snapshot().ready, true);
    }

    setUp(() {
      seconds = 0;
      session = ArcadeSession(drones: ArcadeDrones(random: math.Random(42)))
        ..droneInteractionEnabled = true;
      segments = [
        WorkoutSegment(type: SegmentType.freeRide, duration: 600, powerLow: .7),
      ];
      sample();
      session.openingSeen = true;
    });
    test('a miss deducts 50 once and the same penalty applies to timeout', () {
      charge();
      final before = session.score;
      final frame = session.drones.snapshot();
      expect(
        session.fireDrone(
          serial: frame.serial,
          hit: false,
          aimX: -.5,
          aimY: .4,
          shownClock: frame.clock,
        ),
        true,
      );
      advance(.5, watts: 0);
      expect(session.score, before - 50);
      advance(2, watts: 0);
      expect(session.score, before - 50);
      charge();
      final beforeTimeout = session.score;
      advance(8, watts: 0);
      expect(session.score, beforeTimeout - 50);
    });
    test('no charge still times out; a small score stops at zero', () {
      // Earn ten points, then allow a drone to exhaust its charging window.
      advance(1);
      expect(session.score, lessThan(50));
      advance(70, watts: 0);
      expect(session.score, 0);
      expect(session.drones.destroyed, 0);
    });
    test('Classic and lost telemetry do not expire a charged encounter', () {
      charge();
      final before = session.drones.snapshot();
      session.droneInteractionEnabled = false;
      advance(15, watts: 0);
      expect(session.drones.snapshot().age, before.age);
      session.droneInteractionEnabled = true;
      advance(15, fresh: false);
      expect(session.drones.snapshot().age, before.age);
      expect(
        session.fireDrone(
          serial: before.serial,
          hit: true,
          aimX: .8,
          aimY: .2,
          shownClock: before.clock,
        ),
        false,
      );
      sample();
      expect(
        session.fireDrone(
          serial: before.serial,
          hit: true,
          aimX: .8,
          aimY: .2,
          shownClock: before.clock,
        ),
        true,
      );
    });
  });
}
