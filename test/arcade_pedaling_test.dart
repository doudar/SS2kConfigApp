import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_pedaling.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_world_painter.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_road.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('ARCADE_SCREENSHOTS')) {
    test('render quarter-turn rider poses for visual inspection', () async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < 4; i++) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(i * 220.0, 0, 220, 220));
        canvas.translate(i * 220.0, 0);
        canvas.scale(2);
        canvas.translate(-335, -115);
        ArcadeWorldPainter(
          road:
              (ArcadeRoad()..update(
                    segments: [
                      WorkoutSegment(
                        type: SegmentType.steadyState,
                        duration: 90,
                        powerLow: 1.2,
                      ),
                    ],
                    seconds: 0,
                    watts: 240,
                    ftp: 200,
                    playing: true,
                  ))
                  .snapshot(),
          segments: [
            WorkoutSegment(
              type: SegmentType.steadyState,
              duration: 90,
              powerLow: 1.2,
            ),
          ],
          seconds: 10,
          animation: 0,
          biome: ArcadeBiome.volcano,
          onTarget: true,
          charge: 0,
          pedalPhase: i * math.pi / 2,
          moving: true,
        ).paint(canvas, const Size(900, 400));
        canvas.restore();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(880, 220);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final file = File('build/arcade_pedaling_poses.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
  }
  test('pedal rotation follows cadence without jumping on RPM changes', () {
    final motion = ArcadePedalMotion();
    motion.advance(seconds: .25, cadence: 60, active: true);
    expect(motion.phase, closeTo(math.pi / 2, 1e-9));
    motion.advance(seconds: .125, cadence: 120, active: true);
    expect(motion.phase, closeTo(math.pi, 1e-9));
    motion.advance(seconds: .25, cadence: 60, active: true);
    expect(motion.phase, closeTo(3 * math.pi / 2, 1e-9));
  });

  test('pause, zero cadence and invalid frame times preserve pose', () {
    final motion = ArcadePedalMotion();
    motion.advance(seconds: .1, cadence: 90, active: true);
    final phase = motion.phase;
    motion.advance(seconds: .2, cadence: 90, active: false);
    motion.advance(seconds: .2, cadence: 0, active: true);
    motion.advance(seconds: -.1, cadence: 90, active: true);
    motion.advance(seconds: .1, cadence: double.nan, active: true);
    expect(motion.phase, phase);
    motion.advance(seconds: .1, cadence: 90, active: true);
    expect(motion.phase, closeTo(phase * 2, 1e-9));
  });

  test('slow segment-transition frames advance with bounded catch-up', () {
    final motion = ArcadePedalMotion();
    for (var frame = 1; frame <= 3; frame++) {
      motion.advance(seconds: .4, cadence: 60, active: true);
      expect(motion.phase, closeTo(frame * math.pi / 2, 1e-9));
    }
    motion.advance(seconds: 30, cadence: 60, active: true);
    expect(motion.phase, closeTo(0, 1e-9));
  });

  test('opposing pedals trace a circle and knees preserve leg lengths', () {
    for (var frame = 0; frame < 120; frame++) {
      final pose = ArcadePedalPose(frame * math.pi / 60);
      expect(
        (pose.nearPedal - ArcadePedalPose.crank).distance,
        closeTo(10, 1e-9),
      );
      expect(
        (pose.farPedal - ArcadePedalPose.crank).distance,
        closeTo(10, 1e-9),
      );
      expect(
        ((pose.nearPedal + pose.farPedal) / 2 - ArcadePedalPose.crank).distance,
        closeTo(0, 1e-9),
      );
      for (final (knee, pedal) in [
        (pose.nearKnee, pose.nearPedal),
        (pose.farKnee, pose.farPedal),
      ]) {
        expect((pose.hip - knee).distance, closeTo(25, 1e-9));
        expect((knee - pedal).distance, closeTo(25, 1e-9));
      }
    }
    final top = ArcadePedalPose(math.pi / 2);
    final opposite = ArcadePedalPose(math.pi * 1.5);
    expect((top.nearPedal - opposite.farPedal).distance, closeTo(0, 1e-9));
    expect((top.nearKnee - opposite.nearKnee).distance, greaterThan(10));
    expect(ArcadePedalPose(0).nearPedal, const Offset(10, -1));
  });
}
