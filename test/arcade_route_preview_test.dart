import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_route_preview.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_segment_profile.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  final warmup = WorkoutSegment(
    type: SegmentType.warmup,
    duration: 60,
    powerLow: .4,
    powerHigh: 1.2,
    isRamp: true,
  );
  final cooldown = WorkoutSegment(
    type: SegmentType.cooldown,
    duration: 60,
    powerLow: .4,
    powerHigh: 1.2,
    isRamp: true,
  );
  final segments = [
    warmup,
    WorkoutSegment(type: SegmentType.steadyState, duration: 120, powerLow: 1.2),
    cooldown,
    WorkoutSegment(type: SegmentType.freeRide, duration: 180, powerLow: 0),
  ];

  test(
    'target labels show direction, FTP changes, free rides and trainer clamps',
    () {
      expect(arcadeTargetLabel(warmup, 200), '80→240 W');
      expect(arcadeTargetLabel(cooldown, 200), '240→80 W');
      expect(arcadeTargetLabel(cooldown, 250), '300→100 W');
      expect(arcadeTargetLabel(cooldown, 250, percent: true), '120→40% FTP');
      expect(arcadeTargetLabel(segments.last, 200), 'FREE RIDE');
      expect(
        arcadeTargetLabel(
          WorkoutSegment(
            type: SegmentType.ramp,
            duration: 60,
            powerLow: -1,
            powerHigh: 200,
            isRamp: true,
          ),
          250,
        ),
        '0→32767 W',
      );
      expect(arcadeSegmentPower(cooldown, .5), closeTo(.8, 1e-9));
    },
  );

  test(
    'route silhouettes actually rise and fall instead of drawing flat maxima',
    () {
      ArcadeIntervalPainter painter(WorkoutSegment s) => ArcadeIntervalPainter(
        startPower: arcadeSegmentPower(s, 0),
        endPower: arcadeSegmentPower(s, 1),
        peak: 1.6,
        color: Colors.cyan,
        current: false,
      );
      final rising = painter(warmup).outline(const Size(100, 30));
      final falling = painter(cooldown).outline(const Size(100, 30));
      expect(rising.contains(const Offset(5, 14)), isFalse);
      expect(rising.contains(const Offset(95, 14)), isTrue);
      expect(falling.contains(const Offset(5, 14)), isTrue);
      expect(falling.contains(const Offset(95, 14)), isFalse);
    },
  );

  testWidgets('phone shows the next target and countdown with details on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArcadeRoutePreview(
            segments: segments,
            index: 0,
            seconds: 25,
            ftp: 200,
            endless: false,
            compact: false,
            cleared: const {},
          ),
        ),
      ),
    );
    expect(find.text('NEXT · IN 0:35'), findsOneWidget);
    expect(find.text('240 W · 2:00'), findsOneWidget);
    expect(find.textContaining('THEN'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('240 W · 2:00'));
    await tester.pumpAndSettle();
    expect(find.text('INTERVAL PLAN'), findsOneWidget);
    expect(find.text('3. 240→80 W'), findsOneWidget);
    expect(find.text('120→40% FTP · starts at 3:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide layout previews three intervals; last and endless rides have clear states',
    (tester) async {
      Future<void> show({int index = 0, bool endless = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ArcadeRoutePreview(
                  segments: segments,
                  index: index,
                  seconds: 25,
                  ftp: 200,
                  endless: endless,
                  compact: true,
                  cleared: const {},
                ),
              ),
            ),
          );
      await show();
      expect(find.text('240 W · 2:00'), findsOneWidget);
      expect(find.text('240→80 W · 1:00'), findsOneWidget);
      expect(find.text('FREE RIDE · 3:00'), findsOneWidget);
      await show(index: 3);
      expect(find.textContaining('FINISH IN'), findsOneWidget);
      await show(endless: true);
      expect(find.text('ENDLESS EXPEDITION'), findsOneWidget);
      expect(find.textContaining('NEXT'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
