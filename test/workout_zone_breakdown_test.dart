import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'package:ss2kconfigapp/utils/workout/workout_zone_breakdown.dart';

void main() {
  final choice = WorkoutLobbyChoice(
    source: 'TEST',
    content:
        '<workout_file><workout><SteadyState Duration="900" Power="0.5"/>'
        '<SteadyState Duration="1800" Power="0.7"/>'
        '<Ramp Duration="10" PowerLow="0.5" PowerHigh="1.0"/>'
        '<FreeRide Duration="120"/></workout></workout_file>',
  );
  test('accounts for ramp transitions and leaves free effort unassigned', () {
    final time = WorkoutZoneTime(choice.workout.segments);
    expect(time.total, 2830);
    expect(time.seconds, [902, 1804, 2, 1, 1, 0, 0, 120]);
    expect(time.openEnded, isFalse);
  });
  testWidgets('zone watt ranges update with FTP and fit narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> show(double ftp) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkoutZoneBreakdown(
              segments: choice.workout.segments,
              ftp: ftp,
            ),
          ),
        ),
      ),
    );
    await show(200);
    expect(find.text('111–150 W'), findsOneWidget);
    expect(find.text('Self-paced · 2 min'), findsOneWidget);
    await show(250);
    expect(find.text('138–187 W'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
