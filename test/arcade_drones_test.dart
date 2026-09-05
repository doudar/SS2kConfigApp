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
    for (var i = 0; i < (time * 10).round(); i++) {
      events.addAll(tick(.1, onTarget: onTarget));
    }
    return events;
  }

  setUp(() {
    drones = ArcadeDrones();
    tick(0);
  });

  test(
    'a drone flies in, charges from effort, receives a shot and explodes once',
    () {
      expect(drones.snapshot().phase, ArcadeDronePhase.entering);
      ride(1.8);
      expect(drones.snapshot().phase, ArcadeDronePhase.hovering);
      expect(drones.snapshot().charge, closeTo(.3, 1e-8));
      expect(ride(4.2), [ArcadeDroneEvent.fired]);
      expect(drones.snapshot().phase, ArcadeDronePhase.firing);
      expect(drones.destroyed, 0);
      expect(tick(.45), [ArcadeDroneEvent.destroyed]);
      expect(drones.snapshot().phase, ArcadeDronePhase.exploding);
      expect(drones.destroyed, 1);
      tick(1.1);
      expect(drones.snapshot().phase, ArcadeDronePhase.rearming);
      tick(1.2);
      expect(drones.snapshot().phase, ArcadeDronePhase.entering);
      expect(drones.snapshot().serial, 2);
      expect(drones.snapshot().charge, 0);
      expect(drones.destroyed, 1);
    },
  );

  test('off-target effort holds charge; paused or skipped time earns none', () {
    ride(3);
    ride(10, onTarget: false);
    expect(drones.snapshot().charge, closeTo(.5, 1e-8));
    final before = drones.snapshot();
    tick(1, playing: false);
    expect(drones.snapshot(aheadSeconds: .1).clock, before.clock);
    expect(drones.snapshot().charge, before.charge);
    tick(20);
    expect(drones.snapshot().charge, before.charge);
    expect(drones.destroyed, 0);
    tick(.5, skipped: true);
    expect(drones.snapshot().phase, ArcadeDronePhase.departing);
    expect(drones.snapshot().charge, 0);
    expect(drones.destroyed, 0);
  });

  test(
    'changing sector preserves the entering position and retreats offscreen',
    () {
      tick(.9);
      final clock = drones.snapshot().clock;
      tick(0, sector: 1);
      final exit = drones.snapshot();
      expect(exit.phase, ArcadeDronePhase.departing);
      expect(exit.departureEntry, closeTo(.5, 1e-8));
      expect(exit.lockClock, clock);
      tick(1.4, enabled: false, sector: 1);
      expect(drones.snapshot().visible, isFalse);
      expect(drones.destroyed, 0);
    },
  );

  test('an already earned shot completes across a sector transition', () {
    ride(6);
    final events = tick(.45, enabled: false, sector: 1);
    expect(events, [ArcadeDroneEvent.destroyed]);
    expect(drones.snapshot().phase, ArcadeDronePhase.exploding);
    tick(1.1, enabled: false, sector: 1);
    expect(drones.snapshot().phase, ArcadeDronePhase.dormant);
  });

  test('render interpolation cannot advance combat or invent extra kills', () {
    ride(6);
    final frame = drones.snapshot(aheadSeconds: 1000);
    expect(frame.age, lessThanOrEqualTo(.1 + 1e-8));
    expect(drones.snapshot().phase, ArcadeDronePhase.firing);
    expect(drones.destroyed, 0);
    drones.reset();
    expect(drones.destroyed, 0);
    expect(drones.snapshot().visible, isFalse);
    expect(drones.snapshot().charge, 0);
  });

  test(
    'session shares target freshness, preserves encounters across callbacks and adds no score bonus',
    () {
      final session = ArcadeSession();
      final segments = [
        WorkoutSegment(
          type: SegmentType.steadyState,
          duration: 600,
          powerLow: .7,
        ),
      ];
      void sample(double seconds, {bool fresh = true, double watts = 140}) =>
          session.update(
            segments: segments,
            seconds: seconds,
            playing: true,
            watts: watts,
            target: 140,
            freshSignal: fresh,
          );
      for (var t = 0; t <= 63; t++) sample(t.toDouble());
      expect(session.drones.snapshot().visible, isTrue);
      final charge = session.drones.snapshot().charge;
      sample(64, fresh: false);
      sample(65, watts: 220);
      expect(session.drones.snapshot().charge, charge);
      final serial = session.drones.snapshot().serial;
      sample(65);
      expect(session.drones.snapshot().serial, serial);
      for (var t = 66; t <= 70; t++) {
        final before = session.score;
        sample(t.toDouble());
        expect(
          session.score - before,
          40,
          reason:
              'Drone kills spend visual energy; reward scoring stays unchanged',
        );
      }
      expect(session.drones.destroyed, 1);
      sample(0);
      expect(session.drones.destroyed, 0);
    },
  );
}
