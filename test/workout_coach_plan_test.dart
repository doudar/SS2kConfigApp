import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/services/intervals_service.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_card.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_repository.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'workout_coach_test.dart' as fixtures;

Map<String, dynamic> plan(String name, {bool freeRide = false}) => {
  'workout_file':
      '<workout_file><name>$name</name><workout>'
      '${freeRide ? '<FreeRide Duration="900"/>' : '<SteadyState Duration="600" Power="0.7"/>'}'
      '</workout></workout_file>',
};

Widget app({
  required Future<Map<String, dynamic>?> Function() loadToday,
  Future<bool> Function()? isConnected,
  Future<void> Function(BuildContext)? reconnect,
  Future<CoachData> Function(double, {bool refreshRemote})? load,
  ValueChanged<WorkoutLobbyChoice>? onSelect,
  CoachData? data,
  double ftp = 200,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: WorkoutCoachCard(
        ftp: ftp,
        onSelect: onSelect ?? (_) {},
        onBrowse: () {},
        isConnected: isConnected ?? () async => true,
        reconnect: reconnect ?? (_) async {},
        loadToday: loadToday,
        load:
            load ??
            (_, {bool refreshRemote = false}) async =>
                data ?? CoachData(history: [], candidates: fixtures.choices),
        saveGoal: (_) async {},
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'manual refresh reloads plan and coach data without the cooldown',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'intervals_access_token': 'test-token',
        'intervals_athlete_id': 'athlete',
        'workout_coach_remote_athlete': jsonEncode({
          'attemptAt': DateTime.now().toIso8601String(),
        }),
      });
      final pending = Completer<Map<String, dynamic>?>();
      var plans = 0, remoteLoads = 0;
      await tester.pumpWidget(
        app(
          loadToday: () async =>
              ++plans == 1 ? plan('Original') : pending.future,
          load: (_, {bool refreshRemote = false}) async {
            if (refreshRemote) remoteLoads++;
            return CoachData(history: [], candidates: fixtures.choices);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(remoteLoads, 1);
      expect(find.text('Connect to Intervals.icu'), findsNothing);
      await tester.ensureVisible(find.text('Refresh Intervals.icu'));
      await tester.tap(find.text('Refresh Intervals.icu'));
      await tester.pumpAndSettle();
      expect(plans, 2);
      expect(remoteLoads, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('workout_coach_remote_athlete')!),
        isNot(contains('attemptAt')),
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Refreshing Intervals.icu…'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(plan('Updated'));
      await tester.pumpAndSettle();
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('Refresh Intervals.icu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connect authenticates, loads the plan, and tracks logout', (
    tester,
  ) async {
    var connected = false;
    var logins = 0, plans = 0;
    final auth = Completer<void>();
    await tester.pumpWidget(
      app(
        isConnected: () async => connected,
        reconnect: (_) async {
          logins++;
          await auth.future;
          connected = true;
        },
        loadToday: () async {
          plans++;
          return plan('Connected plan');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(plans, 0);
    await tester.ensureVisible(find.text('Connect to Intervals.icu'));
    await tester.tap(find.text('Connect to Intervals.icu'));
    await tester.pump();
    expect(logins, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Connecting to Intervals.icu…'),
          )
          .onPressed,
      isNull,
    );
    auth.complete();
    await tester.pumpAndSettle();
    expect(plans, 1);
    expect(find.text('Connected plan'), findsOneWidget);
    expect(find.text('Refresh Intervals.icu'), findsOneWidget);
    connected = false;
    IntervalsService.connectionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Connect to Intervals.icu'), findsOneWidget);
    expect(find.text('Connected plan'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'connect remains usable after ${fails ? 'failure' : 'cancel'}',
      (tester) async {
        await tester.pumpWidget(
          app(
            isConnected: () async => false,
            reconnect: (_) async {
              if (fails) throw Exception('Connection failed');
            },
            loadToday: () async => throw StateError('Not connected'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Connect to Intervals.icu'));
        await tester.tap(find.text('Connect to Intervals.icu'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Connect to Intervals.icu'),
              )
              .onPressed,
          isNotNull,
        );
        expect(find.text('Load suggested ride'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('today overrides the suggestion and loads only when selected', (
    tester,
  ) async {
    var loads = 0;
    WorkoutLobbyChoice? selected;
    Future<Map<String, dynamic>?> loadToday() async {
      loads++;
      return plan('Planned tempo');
    }

    await tester.pumpWidget(
      app(loadToday: loadToday, onSelect: (choice) => selected = choice),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workout-coach-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('intervals-today-card')), findsNothing);
    expect(find.text('Planned tempo'), findsOneWidget);
    expect(
      find.textContaining('TODAY · INTERVALS.ICU · 10 min'),
      findsOneWidget,
    );
    expect(find.text('Load suggested ride'), findsNothing);
    expect(selected, isNull);
    await tester.ensureVisible(find.text('Load today’s ride'));
    await tester.tap(find.text('Load today’s ride'));
    expect(selected!.name, 'Planned tempo');
    expect(selected!.workout.segments.single.powerLow, .7);
    await tester.pumpWidget(app(loadToday: loadToday, ftp: 250));
    await tester.pumpAndSettle();
    expect(loads, 1);
  });

  testWidgets(
    'a planned free ride takes precedence over a rest recommendation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          loadToday: () async => plan('Planned free ride', freeRide: true),
          data: CoachData(
            candidates: fixtures.choices,
            history: [
              CoachRide(
                id: 'hard',
                start: DateTime.now().subtract(const Duration(hours: 5)),
                seconds: 3600,
                tss: 110,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Take a rest day'), findsNothing);
      expect(find.text('Planned free ride'), findsOneWidget);
      expect(find.text('Load today’s ride'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in ['missing', 'failed', 'invalid', 'disconnected']) {
    testWidgets('$scenario plan falls back to the app recommendation', (
      tester,
    ) async {
      var loads = 0;
      await tester.pumpWidget(
        app(
          isConnected: () async => scenario != 'disconnected',
          loadToday: () async {
            loads++;
            if (scenario == 'failed') throw Exception('Offline');
            if (scenario == 'invalid') return {'name': 'No workout data'};
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Load suggested ride'), findsOneWidget);
      expect(find.text('Load today’s ride'), findsNothing);
      expect(loads, scenario == 'disconnected' ? 0 : 1);
    });
  }

  testWidgets('refreshes on resume and clears the plan on account changes', (
    tester,
  ) async {
    var connected = true;
    var name = 'First plan';
    final pending = Completer<Map<String, dynamic>?>();
    var delayed = false;
    await tester.pumpWidget(
      app(
        isConnected: () async => connected,
        loadToday: () async => delayed ? pending.future : plan(name),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First plan'), findsOneWidget);
    name = 'Updated plan';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('First plan'), findsNothing);
    expect(find.text('Updated plan'), findsOneWidget);
    delayed = true;
    IntervalsService.connectionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Updated plan'), findsNothing);
    expect(find.text('Load suggested ride'), findsOneWidget);
    connected = false;
    IntervalsService.connectionChanges.value++;
    await tester.pumpAndSettle();
    pending.complete(plan('Stale plan'));
    await tester.pumpAndSettle();
    expect(find.text('Stale plan'), findsNothing);
    expect(find.text('Load today’s ride'), findsNothing);
    expect(find.text('Load suggested ride'), findsOneWidget);
    connected = true;
    delayed = false;
    IntervalsService.connectionChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('Updated plan'), findsOneWidget);
  });
}
