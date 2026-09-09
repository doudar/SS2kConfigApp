import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drone_art.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_enemy_art.dart';

void main() {
  List<ArcadeDroneEvent> step(
    ArcadeDrones combat, {
    double seconds = .1,
    ArcadeDroneStyle style = ArcadeDroneStyle.wheel,
    int level = 0,
    bool playing = true,
    int hits = 1,
  }) => combat.update(
    seconds: seconds,
    playing: playing,
    enabled: true,
    onTarget: true,
    sector: 0,
    style: style,
    levelIndex: level,
    bossHits: hits,
  );

  ArcadeDroneFrame frame(
    ArcadeDroneStyle style,
    double clock,
    int level, {
    ArcadeDronePhase phase = ArcadeDronePhase.ready,
    double lockClock = 0,
  }) => ArcadeDroneFrame(
    phase: phase,
    style: style,
    serial: 3,
    age: 1,
    clock: clock,
    charge: 1,
    lockClock: lockClock,
    departureEntry: 1,
    levelIndex: level,
  );

  ArcadeDroneLayout layout(ArcadeDroneFrame frame, {bool reduced = false}) =>
      ArcadeDroneLayout(
        size: const Size(1000, 700),
        frame: frame,
        worldOrigin: const Offset(420, 420),
        muzzle: const Offset(450, 340),
        scale: 1,
        reducedMotion: reduced,
        flightBounds: const Rect.fromLTWH(180, 100, 790, 500),
      );

  test(
    'all six bosses share manual charge, hit health and counterattack rules',
    () {
      final bosses = ArcadeDroneStyle.values
          .where((style) => style.isBoss)
          .toList();
      expect(bosses, hasLength(6));
      expect(bosses.map((style) => style.targetName).toSet(), hasLength(6));
      for (final style in bosses) {
        final combat = ArcadeDrones(random: math.Random(4));
        step(combat, seconds: 0, style: style, level: 5, hits: 2);
        expect(combat.snapshot().style, style);
        expect(combat.snapshot().requiredHits, 2);
        for (var i = 0; i < 60; i++) {
          step(combat, style: style, level: 5, hits: 2);
        }
        var shown = combat.snapshot();
        expect(shown.ready, true);
        expect(shown.targetName, style.targetName);
        expect(shown.status, contains(style.targetName.toUpperCase()));
        combat.fire(
          serial: shown.serial,
          hit: false,
          aimX: .1,
          aimY: .1,
          shownClock: shown.clock,
        );
        expect(step(combat, style: style, seconds: .45, level: 5), [
          ArcadeDroneEvent.bossCounter,
        ]);
        step(combat, style: style, seconds: 1.4, level: 5);
        expect(combat.snapshot().hits, 0);
        for (var hit = 1; hit <= 2; hit++) {
          for (var i = 0; i < 60; i++) {
            step(combat, style: style, level: 5);
          }
          shown = combat.snapshot();
          expect(shown.ready, true);
          combat.fire(
            serial: shown.serial,
            hit: true,
            aimX: .6,
            aimY: .3,
            shownClock: shown.clock,
          );
          expect(step(combat, style: style, seconds: .45, level: 5), [
            hit == 2
                ? ArcadeDroneEvent.bossDestroyed
                : ArcadeDroneEvent.bossHit,
          ]);
          expect(combat.snapshot().hits, hit);
          if (hit == 1) step(combat, style: style, seconds: 1.1, level: 5);
        }
        expect(combat.destroyed, 0);
        expect(combat.snapshot().defeated, true);
      }
    },
  );

  test('a level change preserves an active encounter, its health and shot', () {
    final combat = ArcadeDrones();
    step(
      combat,
      seconds: 0,
      style: ArcadeDroneStyle.bramble,
      level: 1,
      hits: 2,
    );
    for (var i = 0; i < 60; i++) {
      step(combat, style: ArcadeDroneStyle.bramble, level: 1, hits: 2);
    }
    final shown = combat.snapshot();
    step(combat, style: ArcadeDroneStyle.voidRegent, level: 5, hits: 6);
    expect(combat.snapshot().style, ArcadeDroneStyle.bramble);
    expect(combat.snapshot().levelIndex, 1);
    expect(combat.snapshot().requiredHits, 2);
    combat.fire(
      serial: shown.serial,
      hit: true,
      aimX: .6,
      aimY: .2,
      shownClock: shown.clock,
    );
    expect(
      step(combat, seconds: .45, style: ArcadeDroneStyle.voidRegent, level: 5),
      [ArcadeDroneEvent.bossHit],
    );
    step(combat, seconds: 1.1, style: ArcadeDroneStyle.voidRegent, level: 5);
    expect(combat.snapshot().serial, shown.serial);
    expect(combat.snapshot().hits, 1);
    expect(combat.snapshot().style, ArcadeDroneStyle.bramble);
    expect(combat.snapshot().levelIndex, 1);
  });

  test(
    'later nonboss encounters include the unlocked variety with sparse gaps',
    () {
      final found = <ArcadeDroneStyle>{};
      for (var seed = 0; seed < 50; seed++) {
        final combat = ArcadeDrones(random: math.Random(seed));
        var elapsed = 0.0;
        while (!combat.snapshot().visible && elapsed < 40) {
          step(combat, level: 5);
          elapsed += .1;
        }
        final target = combat.snapshot();
        expect(elapsed, inInclusiveRange(18, 38.2));
        expect(target.isBoss, false);
        expect(target.levelIndex, 5);
        found.add(target.style);
      }
      expect(
        found,
        containsAll([
          ArcadeDroneStyle.wheel,
          ArcadeDroneStyle.sentinel,
          ArcadeDroneStyle.beetle,
          ArcadeDroneStyle.wasp,
          ArcadeDroneStyle.orb,
        ]),
      );
    },
  );

  test(
    'all moving targets stay bounded, hittable and stationary in reduced motion',
    () {
      for (final style in ArcadeDroneStyle.values) {
        final firstReduced = layout(frame(style, 0, 5), reduced: true);
        var lowMin = double.infinity, lowMax = double.negativeInfinity;
        var highMin = double.infinity, highMax = double.negativeInfinity;
        for (var i = 0; i < 160; i++) {
          final clock = i * .1;
          final low = layout(frame(style, clock, 0));
          final high = layout(frame(style, clock, 5));
          lowMin = math.min(lowMin, low.position.dx);
          lowMax = math.max(lowMax, low.position.dx);
          highMin = math.min(highMin, high.position.dx);
          highMax = math.max(highMax, high.position.dx);
          expect(high.contains(high.position), true);
          expect(
            const Rect.fromLTWH(180, 100, 790, 500).contains(high.position),
            true,
          );
          final reduced = layout(frame(style, clock, 5), reduced: true);
          expect(reduced.position, firstReduced.position);
          expect(reduced.bank, 0);
          final locked = layout(
            frame(
              style,
              clock,
              5,
              phase: ArcadeDronePhase.firing,
              lockClock: 2,
            ),
          );
          expect(locked.position, layout(frame(style, 2, 5)).position);
        }
        expect(highMax - highMin, greaterThan((lowMax - lowMin) * 2));
      }
    },
  );

  testWidgets('new enemy silhouettes paint in compact static portraits', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final style in ArcadeDroneStyle.values.where(
                (style) =>
                    style != ArcadeDroneStyle.wheel &&
                    style != ArcadeDroneStyle.sentinel,
              ))
                SizedBox(
                  width: 130,
                  height: 155,
                  child: CustomPaint(painter: _Portrait(style)),
                ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

class _Portrait extends CustomPainter {
  _Portrait(this.style);
  final ArcadeDroneStyle style;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    ArcadeEnemyArt.paint(canvas, style, 0, damage: .6);
  }

  @override
  bool shouldRepaint(_Portrait oldDelegate) => style != oldDelegate.style;
}
