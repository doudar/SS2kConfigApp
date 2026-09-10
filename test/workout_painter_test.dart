import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/workout_painter.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';
import 'package:ss2kconfigapp/utils/workout/workout_storage.dart';

void main() {
  test('live power keeps target alignment without magnifying small errors', () {
    final block = WorkoutSegment(
      type: SegmentType.steadyState,
      duration: 60,
      powerLow: .8,
    );
    for (final height in [180.0, 400.0, 900.0]) {
      final size = Size(600, height);
      final painter = WorkoutPainter(
        segments: [block],
        maxPower: 1.2,
        totalDuration: 60,
        ftpValue: 250,
        currentProgress: .5,
        actualPowerPoints: const {},
        maxPixelsPerWatt: .75,
      );
      final targetY = painter
          .segmentOutline(block, Offset.zero & size, size)
          .getBounds()
          .top;
      expect(painter.powerY(200, size), closeTo(targetY, 1e-4));
      expect(
        (painter.powerY(202, size) - targetY).abs(),
        lessThanOrEqualTo(1.5),
      );
      expect(
        (painter.powerY(198, size) - targetY).abs(),
        lessThanOrEqualTo(1.5),
      );
      // Large misses and coasting remain proportional, with no target snapping.
      expect(
        targetY - painter.powerY(240, size),
        closeTo(20 * (targetY - painter.powerY(202, size)), 1e-3),
      );
      expect(painter.powerY(0, size), height);
    }
  });

  final segments = WorkoutParser.parseZwoFile('''
    <workout_file><name>Shared profile</name><workout>
    <Warmup Duration="300" PowerLow="0.4" PowerHigh="0.7"/>
    <SteadyState Duration="300" Power="0.7"/>
    <SteadyState Duration="300" Power="0.9"/>
    <IntervalsT Repeat="3" OnDuration="60" OffDuration="60" OnPower="1.2" OffPower="0.5"/>
    <Cooldown Duration="300" PowerLow="0.4" PowerHigh="0.7"/>
    </workout></workout_file>''').segments;

  testWidgets('preview and live use identical silhouettes at the same scale', (
    tester,
  ) async {
    final preview = WorkoutPainter.preview(segments);
    final live = WorkoutPainter(
      segments: segments,
      maxPower: preview.maxPower,
      totalDuration: preview.totalDuration,
      ftpValue: 250,
      currentProgress: 0,
      actualPowerPoints: const {},
      showLabels: false,
    );
    Future<List<int>> pixels(WorkoutPainter painter) async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(320, 80));
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 80);
      final bytes = await image.toByteData();
      final result = bytes!.buffer.asUint8List().toList();
      image.dispose();
      picture.dispose();
      return result;
    }

    await tester.runAsync(() async {
      expect(await pixels(live), await pixels(preview));
      final highlighted = await pixels(
        WorkoutPainter.preview(segments, progress: .2, highlightCurrent: true),
      );
      expect(highlighted, isNot(await pixels(preview)));
    });
  });

  testWidgets(
    'zero-duration free ride stays visible and invalid scales are safe',
    (tester) async {
      final free = WorkoutSegment(
        type: SegmentType.freeRide,
        duration: 0,
        powerLow: 0,
      );
      final painter = WorkoutPainter.preview([free]);
      expect(
        painter
            .segmentOutline(
              free,
              const Rect.fromLTWH(0, 0, 100, 60),
              const Size(100, 60),
            )
            .contains(const Offset(50, 50)),
        isTrue,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      WorkoutPainter(
        segments: segments,
        maxPower: double.nan,
        totalDuration: 0,
        ftpValue: 0,
        currentProgress: double.nan,
        actualPowerPoints: const {},
      ).paint(canvas, const Size(100, 60));
      recorder.endRecording().dispose();
    },
  );

  testWidgets('old cached thumbnails are regenerated and then reused', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'workout_thumbnail_Test': 'old-style',
    });
    const content =
        '<workout_file><workout><SteadyState Duration="60" Power="0.7"/></workout></workout_file>';
    await tester.runAsync(() async {
      final first = await WorkoutStorage.getOrGenerateWorkoutThumbnail(
        workoutName: 'Test',
        workoutContent: content,
      );
      expect(first, startsWith('iVBOR'));
      expect(
        await WorkoutStorage.getOrGenerateWorkoutThumbnail(
          workoutName: 'Test',
          workoutContent: content,
        ),
        first,
      );
    });
  });

  testWidgets(
    'live traces survive missing samples and render at phone and desktop sizes',
    (tester) async {
      const capture = bool.fromEnvironment('WORKOUT_PAINTER_SCREENSHOTS');
      if (capture) {
        await tester.runAsync(() async {
          await (FontLoader('ProfilePreview')..addFont(
                File(
                  'C:/Windows/Fonts/segoeui.ttf',
                ).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        });
        debugWorkoutPainterFontFamily = 'ProfilePreview';
        addTearDown(() => debugWorkoutPainterFontFamily = null);
      }
      for (final width in [320.0, 1000.0]) {
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(const Color(0xff10182e), BlendMode.src);
          canvas.save();
          canvas.translate(20, 20);
          WorkoutPainter.preview(segments).paint(canvas, Size(width - 40, 80));
          canvas.restore();
          canvas.translate(20, 160);
          WorkoutPainter(
            segments: segments,
            maxPower: 1.4,
            totalDuration: 1560,
            ftpValue: 250,
            currentProgress: .7,
            actualPowerPoints: const {},
            currentPower: 295,
            currentHr: 155,
            currentCadence: 92,
            powerPointsList: List.generate(
              1093,
              (i) => i < 300
                  ? 100 + i / 4
                  : i < 600
                  ? 175
                  : i < 900
                  ? 225
                  : i < 960
                  ? 295
                  : i < 1020
                  ? 125
                  : 295,
            ),
            hrPointsList: List.generate(
              1093,
              (i) => i > 600 && i < 620 ? 0 : 100 + i / 20,
            ),
            cadencePointsList: List.generate(
              1093,
              (i) => i > 600 && i < 620 ? 0 : 92,
            ),
          ).paint(canvas, Size(width - 40, 200));
          final picture = recorder.endRecording();
          final image = await picture.toImage(width.toInt(), 400);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(bytes, isNotNull);
          if (capture)
            await File(
              'build/workout-painter-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    },
  );
}
