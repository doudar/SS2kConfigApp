import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/services/intervals_service.dart';
import 'package:ss2kconfigapp/services/intervals_workout_converter.dart';
import 'package:ss2kconfigapp/utils/workout/intervals_today_card.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';

Map<String, dynamic> event(String name) => {
  'name': name,
  'type': 'Ride',
  'workout_doc': {
    'steps': [
      {
        'duration': 600,
        'power': {'value': 70, 'units': '%ftp'},
      },
    ],
  },
};

void main() {
  testWidgets(
    'features today once, loads only on tap, and refreshes after login/logout',
    (tester) async {
      var connected = false;
      var loads = 0;
      WorkoutLobbyChoice? selected;
      final key = GlobalKey();
      Widget app(double ftp) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: IntervalsTodayCard(
              key: key,
              ftp: ftp,
              onSelect: (choice) => selected = choice,
              isConnected: () async => connected,
              loadToday: () async {
                loads++;
                return event('Tempo & endurance');
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(200));
      await tester.pumpAndSettle();
      expect(loads, 0);
      expect(find.byKey(const ValueKey('intervals-today-card')), findsNothing);
      connected = true;
      IntervalsService.connectionChanges.value++;
      await tester.pumpAndSettle();
      expect(find.text('Tempo & endurance'), findsOneWidget);
      expect(find.text('10:00 · 1 interval'), findsOneWidget);
      expect(selected, isNull);
      await tester.pumpWidget(app(250));
      await tester.pumpAndSettle();
      expect(loads, 1); // FTP / telemetry rebuilds do not refetch the plan.
      await tester.tap(find.text('Load today’s ride'));
      expect(selected!.name, 'Tempo & endurance');
      expect(selected!.workout.segments.single.powerLow, .7);
      connected = false;
      IntervalsService.connectionChanges.value++;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('intervals-today-card')), findsNothing);
    },
  );

  testWidgets('missing or failed plans allow retry without a load action', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntervalsTodayCard(
            ftp: 200,
            onSelect: (_) => throw StateError('No plan to load'),
            isConnected: () async => true,
            loadToday: () async {
              if (fail) throw Exception('Offline');
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No planned ride available for today.'), findsOneWidget);
    expect(find.text('Load today’s ride'), findsNothing);
    fail = true;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Today’s ride couldn’t be loaded.'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('late responses cannot restore a plan after disconnect', (
    tester,
  ) async {
    var connected = true;
    final pending = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntervalsTodayCard(
            ftp: 200,
            onSelect: (_) {},
            isConnected: () async => connected,
            loadToday: () => pending.future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Checking today’s plan…'), findsOneWidget);
    connected = false;
    IntervalsService.connectionChanges.value++;
    await tester.pump();
    pending.complete(event('Yesterday'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('intervals-today-card')), findsNothing);
  });

  testWidgets('refreshes on return to app and supports narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var name = 'First plan';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: IntervalsTodayCard(
                ftp: 200,
                onSelect: (_) {},
                isConnected: () async => true,
                loadToday: () async => event(name),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    name = 'Updated plan with a longer title';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(name), findsOneWidget);
    expect(find.text('First plan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('today selects cycling events instead of other sports', () {
    expect(IntervalsService.isRideWorkoutEvent(event('Ride')), isTrue);
    expect(
      IntervalsService.isRideWorkoutEvent({
        ...event('Indoor'),
        'type': 'VirtualRide',
      }),
      isTrue,
    );
    expect(
      IntervalsService.isRideWorkoutEvent({...event('Run'), 'type': 'Run'}),
      isFalse,
    );
    expect(IntervalsService.isRideWorkoutEvent({'category': 'NOTE'}), isFalse);
    expect(IntervalsService.isRideWorkoutEvent(null), isFalse);
  });

  test(
    'shared event conversion preserves ZWO files and scheduled free ride duration',
    () {
      const zwo =
          '<workout_file><name>File ride</name><workout><FreeRide Duration="900"/></workout></workout_file>';
      expect(
        IntervalsWorkoutConverter.convertEventToZwo({'workout_file': zwo}),
        zwo,
      );
      final content = IntervalsWorkoutConverter.convertEventToZwo({
        'name': 'Easy ride',
        'workout_doc': <String, dynamic>{},
        'moving_time': 1800,
      });
      final choice = WorkoutLobbyChoice(content: content!, source: 'TODAY');
      expect(choice.workout.segments.single.duration, 1800);
      expect(
        IntervalsWorkoutConverter.convertEventToZwo({'name': 'Note'}),
        isNull,
      );
    },
  );
}
