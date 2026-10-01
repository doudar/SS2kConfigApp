import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_recovery.dart';
import 'package:ss2kconfigapp/utils/workout/workout_fitness_trend.dart';

void main() {
  final now = DateTime(2026, 9, 10, 12);
  final today = DateTime(2026, 9, 10);
  testWidgets('shows latest values and lets the rider inspect an earlier day', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutFitnessTrend(
            now: now,
            history: [
              CoachWellness(
                day: today.subtract(const Duration(days: 1)),
                fitness: 44,
                fatigueLoad: 50,
              ),
              CoachWellness(day: today, fitness: 45, fatigueLoad: 49),
              CoachWellness(
                day: today.add(const Duration(days: 1)),
                fitness: 999,
                fatigueLoad: 999,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('45'), findsOneWidget);
    expect(find.text('49'), findsOneWidget);
    expect(find.text('-4'), findsOneWidget);
    expect(find.text('999'), findsNothing);
    final chart = find.byKey(const ValueKey('fitness-trend-chart'));
    expect(chart, findsOneWidget);
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(32, 50));
    await tester.pump();
    expect(find.text('44'), findsOneWidget);
    expect(find.text('-6'), findsOneWidget);
    expect(find.text('Intervals.icu · Today'), findsNothing);
    await tester.tap(find.text('Latest'));
    await tester.pump();
    expect(find.text('Intervals.icu · Today'), findsOneWidget);
  });

  testWidgets('single day shows numbers without a made-up history graph', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(40),
              child: WorkoutFitnessTrend(
                now: now,
                history: [
                  CoachWellness(day: today, fitness: 45, fatigueLoad: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('+5'), findsOneWidget);
    expect(find.byKey(const ValueKey('fitness-trend-chart')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutFitnessTrend(
          now: now,
          history: [
            CoachWellness(
              day: today.subtract(const Duration(days: 29)),
              fitness: 45,
              fatigueLoad: 49,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Fitness'), findsNothing);
    expect(find.text('45'), findsNothing);
  });
}
