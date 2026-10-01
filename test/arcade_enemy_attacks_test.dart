import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drone_art.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_cues.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_enemy_art.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_rider_art.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_rider_appearance.dart';

ArcadeDroneFrame _frame(
  ArcadeDroneStyle style,
  double age, {
  ArcadeDronePhase phase = ArcadeDronePhase.departing,
  double clock = 8,
}) => ArcadeDroneFrame(
  phase: phase,
  style: style,
  serial: 2,
  age: age,
  clock: clock,
  charge: 1,
  lockClock: 8,
  departureEntry: 1,
  stolePoints: true,
  levelIndex: 3,
);

ArcadeDroneLayout _layout(ArcadeDroneFrame frame, {bool reduced = false}) =>
    ArcadeDroneLayout(
      size: const Size(400, 220),
      frame: frame,
      worldOrigin: const Offset(160, 225),
      muzzle: const Offset(96, 142),
      scale: .7,
      reducedMotion: reduced,
      flightBounds: const Rect.fromLTWH(180, 15, 210, 200),
    );

void main() {
  test(
    'each story counter emits its own sound once and takes only fifty points',
    () {
      for (var variant = 0; variant < 6; variant++) {
        final game = ArcadeSession()..droneInteractionEnabled = true;
        game.stageOpening(ArcadeStory(variant));
        final segments = [
          WorkoutSegment(
            type: SegmentType.steadyState,
            duration: 90,
            powerLow: 1.2,
          ),
        ];
        var seconds = 0.0;
        final heard = <ArcadeCue>[];
        void step(double dt, {bool pedaling = true}) {
          seconds += dt;
          game.update(
            segments: segments,
            seconds: seconds,
            playing: true,
            watts: pedaling ? 240 : 0,
            target: 240,
            freshSignal: true,
          );
          heard.addAll(game.cues);
        }

        step(0);
        for (var i = 0; i < 100 && !game.drones.snapshot().ready; i++) {
          step(.1);
        }
        final shown = game.drones.snapshot();
        expect(shown.ready, true);
        final before = game.score;
        game.fireDrone(
          serial: shown.serial,
          hit: false,
          aimX: .1,
          aimY: .2,
          shownClock: shown.clock,
        );
        step(.45, pedaling: false);
        expect(game.cues, [ArcadeCue.attackFor(shown.style)]);
        expect(game.reward, contains(shown.style.attackName.toUpperCase()));
        for (var i = 0; i < 20; i++) {
          step(.1, pedaling: false);
        }
        expect(
          heard.where((cue) => cue == ArcadeCue.attackFor(shown.style)),
          hasLength(1),
        );
        expect(game.score, before - 50);
      }
    },
  );
  test('each species has a distinct smooth movement and locked shot pose', () {
    final traces = <String>{};
    for (final style in ArcadeDroneStyle.values) {
      final trace = <String>[];
      Offset? previous;
      for (var i = 0; i < 200; i++) {
        final pose = _layout(
          _frame(style, 1, phase: ArcadeDronePhase.ready, clock: i * .05),
        );
        expect(pose.contains(pose.position), true);
        if (previous != null) {
          expect((pose.position - previous).distance, lessThan(6));
        }
        previous = pose.position;
        trace.add(
          '${pose.position.dx.toStringAsFixed(2)},${pose.position.dy.toStringAsFixed(2)}',
        );
      }
      traces.add(trace.join(';'));
      final locked = _layout(
        _frame(style, .2, phase: ArcadeDronePhase.firing, clock: 10),
      );
      final atShot = _layout(_frame(style, 0, phase: ArcadeDronePhase.ready));
      expect(locked.position, atShot.position);
      expect(locked.bank, atShot.bank);
      final launch = _layout(_frame(style, 0));
      final later = _layout(_frame(style, 1, clock: 9));
      expect(later.attackOrigin, launch.attackOrigin);
      final staticA = _layout(_frame(style, 0), reduced: true);
      final staticB = _layout(_frame(style, 1, clock: 12), reduced: true);
      expect(staticA.position, staticB.position);
      expect(staticA.attackOrigin, staticB.attackOrigin);
    }
    expect(traces.length, ArcadeDroneStyle.values.length);
  });

  test('a last-second hit interrupts the warned special attack', () {
    for (final style in ArcadeDroneStyle.values.where((s) => s.isBoss)) {
      final combat = ArcadeDrones();
      List<ArcadeDroneEvent> step(double dt) => combat.update(
        seconds: dt,
        playing: true,
        enabled: true,
        onTarget: true,
        sector: 0,
        style: style,
        bossHits: 2,
      );
      step(0);
      for (var i = 0; i < 125; i++) {
        step(.1);
      }
      final warning = combat.snapshot();
      expect(warning.attackWarning, true);
      expect(warning.status, contains(style.attackName.toUpperCase()));
      combat.fire(
        serial: warning.serial,
        hit: true,
        aimX: .7,
        aimY: .3,
        shownClock: warning.clock,
      );
      expect(combat.snapshot().attackWarning, false);
      expect(step(.45), [ArcadeDroneEvent.bossHit]);
      expect(combat.snapshot().stolePoints, false);
    }
  });

  testWidgets(
    'all attacks render through wind-up, travel and impact at ride scale',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1120);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('ARCADE_SCREENSHOTS') &&
          Platform.isWindows) {
        await tester.runAsync(() async {
          final bytes = await File(
            '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
          ).readAsBytes();
          await (FontLoader(
            'Roboto',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        });
      }
      final key = GlobalKey();
      for (final reduced in [false, true]) {
        for (final age in [-1.0, 0.0, .45, .9, 1.39]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: const Color(0xff080f21),
                    child: Wrap(
                      children: [
                        for (final style in ArcadeDroneStyle.values)
                          SizedBox(
                            width: 400,
                            height: 280,
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                Text(
                                  style.targetName,
                                  style: TextStyle(
                                    color: ArcadeEnemyArt.tint(style),
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  style.attackName.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Expanded(
                                  child: CustomPaint(
                                    size: const Size(400, 220),
                                    painter: _AttackPreview(
                                      style,
                                      age,
                                      reduced,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('ARCADE_SCREENSHOTS') &&
              !reduced &&
              (age == .45 || age == .9 || age == -1)) {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/arcade_attacks_${age == -1
                    ? 'warning'
                    : age == .45
                    ? 'flight'
                    : 'impact'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    },
  );
}

class _AttackPreview extends CustomPainter {
  const _AttackPreview(this.style, this.age, this.reduced);
  final ArcadeDroneStyle style;
  final double age;
  final bool reduced;
  @override
  void paint(Canvas c, Size size) {
    final frame = _frame(
      style,
      age < 0 ? 7 : age,
      phase: age < 0 ? ArcadeDronePhase.ready : ArcadeDronePhase.departing,
    );
    final layout = _layout(frame, reduced: reduced);
    c.drawLine(
      const Offset(20, 194),
      const Offset(370, 194),
      Paint()
        ..color = Colors.white12
        ..strokeWidth = 2,
    );
    ArcadeRiderArt.paint(
      c,
      const Offset(70, 174),
      rider: const ArcadeRiderAppearance(),
      pedalPhase: age * 4,
    );
    ArcadeDroneArt.paint(
      c,
      size,
      frame,
      layout: layout,
      reducedMotion: reduced,
    );
  }

  @override
  bool shouldRepaint(covariant _AttackPreview old) =>
      style != old.style || age != old.age || reduced != old.reduced;
}
