import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reorderables/reorderables.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/classic_workout_preview.dart';
import 'package:ss2kconfigapp/utils/workout/workout_metric_row.dart';
import 'package:ss2kconfigapp/utils/workout/workout_painter.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';
import 'package:ss2kconfigapp/utils/workout/workout_visuals.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final segments = WorkoutParser.parseZwoFile('''
    <workout_file><workout>
    <Warmup Duration="120" PowerLow="0.4" PowerHigh="0.8"/>
    <SteadyState Duration="120" Power="0.8"/>
    <IntervalsT Repeat="3" OnDuration="60" OffDuration="60" OnPower="1.1" OffPower="0.5"/>
    <Cooldown Duration="120" PowerLow="0.4" PowerHigh="0.8"/>
    </workout></workout_file>''').segments;
  List<WorkoutMetric> metrics(int watts) => [
    WorkoutMetric.power(watts: watts),
    const WorkoutMetric(label: 'Target', value: '200', unit: 'W'),
    WorkoutMetric.cadence(rpm: 92),
    WorkoutMetric.heartRate(bpm: 145),
    WorkoutMetric.elapsedTime(seconds: 180),
    const WorkoutMetric(label: 'Next Block', value: '00:01:00'),
    WorkoutMetric.remainingTime(
      totalSeconds: 720,
      elapsedSeconds: 180,
      workoutProgressSeconds: 180,
    ),
    WorkoutMetric.speed(mph: 18.3),
    WorkoutMetric.distance(miles: 1.14),
  ];

  testWidgets(
    'metric columns stay centered through value changes and saved reorders',
    (tester) async {
      Future<void> show(int watts) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WorkoutMetricRow(metrics: metrics(watts))),
        ),
      );
      await show(99);
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const ValueKey('Power')));
      await show(1000);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('Power'))), before);
      for (final tile in tester.widgetList<MetricBox>(find.byType(MetricBox))) {
        final box = tester.getRect(find.byKey(ValueKey(tile.metric.label)));
        final number = tester.getRect(
          find.byKey(ValueKey('metric-value-${tile.metric.label}')),
        );
        expect(number.center.dx, closeTo(box.center.dx, .01));
        expect(box.width, closeTo(before.width, .01));
      }
      final wrap = tester.widget<ReorderableWrap>(find.byType(ReorderableWrap));
      final original = wrap.children
          .map((e) => (e as MetricBox).metric.label)
          .toList();
      wrap.onReorder(0, 2);
      await tester.pumpAndSettle();
      // Final destination index is supplied directly by ReorderableWrap.
      final moved = [...original];
      moved.insert(2, moved.removeAt(0));
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'workout_metric_order',
        ),
        moved,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Classic preview, metrics and traces fit phone, desktop and large text',
    (tester) async {
      const capture = bool.fromEnvironment('CLASSIC_STYLE_SCREENSHOTS');
      if (capture) {
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(
            await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
          );
          for (final family in ['Ahem', 'Roboto', 'ClassicPreview']) {
            await (FontLoader(family)..addFont(Future.value(bytes))).load();
          }
        });
        debugWorkoutPainterFontFamily = 'ClassicPreview';
        addTearDown(() => debugWorkoutPainterFontFamily = null);
      }
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final (size, scale) in [
        (const Size(360, 800), 1.0),
        (const Size(1200, 800), 1.0),
        (const Size(360, 800), 1.5),
        (const Size(800, 360), 1.0),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: captureKey,
                  child: ClassicWorkoutSurface(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: WorkoutMetricRow(metrics: metrics(202)),
                        ),
                        const WorkoutTraceLegend(),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                            child: CustomPaint(
                              painter: WorkoutPainter(
                                segments: segments,
                                maxPower: 1.21,
                                totalDuration: 720,
                                ftpValue: 250,
                                currentProgress: .25,
                                actualPowerPoints: const {},
                                maxPixelsPerWatt: .75,
                                currentPower: 202,
                                currentCadence: 92,
                                currentHr: 145,
                                powerPointsList: List.generate(
                                  181,
                                  (i) => i < 120
                                      ? 100 + i * 100 / 120
                                      : 200.0 + (i % 5 - 2),
                                ),
                                cadencePointsList: List.filled(181, 92),
                                hrPointsList: List.generate(
                                  181,
                                  (i) => 115.0 + i / 6,
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        ClassicWorkoutPreview(
                          segments: segments,
                          index: 1,
                          seconds: 180,
                          ftp: 250,
                          endless: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('INTERVAL 2/9'), findsOneWidget);
        expect(find.text('NEXT · IN 1:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture && scale == 1) {
          await tester.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/classic-style-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text('275 W · 1:00').first);
        await tester.pumpAndSettle();
        expect(find.text('INTERVAL PLAN'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
