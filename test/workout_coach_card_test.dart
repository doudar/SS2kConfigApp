import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_card.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_repository.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_recovery.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'workout_coach_test.dart' as fixtures;

void main() {
  testWidgets(
    'offers reconnect only after a connected account lacks fitness data',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final remote = Completer<CoachData>();
      final auth = Completer<void>();
      var logins = 0;
      var restored = false;
      final now = DateTime.now();
      final missing = CoachData(
        account: 'athlete',
        history: [],
        candidates: fixtures.choices,
        wellness: [],
        needsReconnect: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkoutCoachCard(
                ftp: 200,
                onSelect: (_) {},
                onBrowse: () {},
                saveGoal: (_) async {},
                reconnect: (_) async {
                  logins++;
                  await auth.future;
                  restored = true;
                },
                load: (_, {bool refreshRemote = false}) async {
                  if (restored)
                    return CoachData(
                      account: 'athlete',
                      history: [],
                      candidates: fixtures.choices,
                      wellness: [
                        CoachWellness(
                          day: DateTime(now.year, now.month, now.day),
                          fitness: 45,
                          fatigueLoad: 49,
                        ),
                      ],
                    );
                  return refreshRemote ? remote.future : missing;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reconnect Intervals.icu'), findsNothing);
      remote.complete(missing);
      await tester.pumpAndSettle();
      expect(find.text('Connect your fitness data'), findsOneWidget);
      expect(find.textContaining('wellness access'), findsOneWidget);
      expect(find.textContaining('recovery days'), findsOneWidget);
      await tester.ensureVisible(find.text('Reconnect Intervals.icu'));
      await tester.tap(find.text('Reconnect Intervals.icu'));
      await tester.pump();
      expect(logins, 1);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Connecting…'),
      );
      expect(button.onPressed, isNull);
      auth.complete();
      await tester.pumpAndSettle();
      expect(find.text('Connect your fitness data'), findsNothing);
      expect(find.text('45'), findsOneWidget);
    },
  );

  testWidgets(
    'missing current metrics offer a permissions review even without a 403',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkoutCoachCard(
                ftp: 200,
                onSelect: (_) {},
                onBrowse: () {},
                saveGoal: (_) async {},
                load: (_, {bool refreshRemote = false}) async => CoachData(
                  account: 'athlete',
                  history: [],
                  candidates: fixtures.choices,
                  wellness: [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reconnect Intervals.icu'), findsOneWidget);
      expect(
        find.textContaining('check that your data has synced'),
        findsOneWidget,
      );
    },
  );
  if (const bool.fromEnvironment('WORKOUT_COACH_SCREENSHOTS')) {
    testWidgets('coach visual previews', (tester) async {
      tester.view.physicalSize = const Size(1200, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Roboto')..addFont(
              File(
                'C:/Windows/Fonts/segoeui.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      });
      final key = GlobalKey();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      List<CoachWellness> wellness(double fatigue) => [
        for (var day = 28; day > 0; day--)
          CoachWellness(
            day: DateTime(today.year, today.month, today.day - day),
            fitness: 46 - day * .2,
            fatigueLoad: 46 - day * .2 + 10 * math.sin(day / 2),
          ),
        CoachWellness(day: today, fitness: 46, fatigueLoad: fatigue),
      ];
      final history = [
        for (final ride in fixtures.baseline())
          CoachRide(
            id: ride.id,
            start: now.subtract(fixtures.now.difference(ride.start)),
            seconds: ride.seconds,
            tss: ride.tss,
          ),
      ];
      final scenarios = [
        CoachData(
          history: history,
          candidates: fixtures.choices,
          goal: CoachGoal.performance,
          wellness: wellness(56),
        ),
        CoachData(
          history: history,
          candidates: fixtures.choices,
          wellness: wellness(56),
        ),
        CoachData(
          history: history,
          candidates: fixtures.choices,
          goal: CoachGoal.endurance,
          wellness: wellness(80),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            backgroundColor: const Color(0xff080c18),
            body: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xff080c18),
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final data in scenarios)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SingleChildScrollView(
                            child: WorkoutCoachCard(
                              ftp: 200,
                              onSelect: (_) {},
                              onBrowse: () {},
                              saveGoal: (_) async {},
                              load: (_, {bool refreshRemote = false}) async =>
                                  data,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/workout-coach-preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
  final easy = CoachCandidate.fromChoice(
    WorkoutLobbyChoice(
      source: 'BUILT-IN',
      content:
          '<workout_file><name>Easy ride</name><workout><SteadyState Duration="1800" Power="0.55"/></workout></workout_file>',
    ),
  )!;
  testWidgets(
    'connected fitness data avoids the missing-ride fallback message',
    (tester) async {
      final now = DateTime.now();
      final data = CoachData(
        goal: CoachGoal.performance,
        history: [
          for (var day = 1; day <= 5; day++)
            CoachRide(
              id: '$day',
              start: now.subtract(Duration(days: day)),
              seconds: 3600,
              tss: null,
            ),
        ],
        candidates: fixtures.choices,
        wellness: [
          CoachWellness(
            day: DateTime(now.year, now.month, now.day),
            fitness: 45,
            fatigueLoad: 49,
          ),
        ],
        note: 'Intervals.icu + saved rides',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkoutCoachCard(
                ftp: 224,
                onSelect: (_) {},
                onBrowse: () {},
                saveGoal: (_) async {},
                load: (_, {bool refreshRemote = false}) async => data,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A little more challenge'), findsOneWidget);
      expect(find.text('Tempo'), findsOneWidget);
      expect(find.text('5 completed rides in the last 7 days'), findsOneWidget);
      expect(find.textContaining('data is unavailable'), findsNothing);
      expect(find.textContaining('still learning'), findsNothing);
      expect(find.textContaining('Est. TSS 48'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('49'), findsOneWidget);
      expect(find.text('-4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'local suggestion is usable while remote hangs; goal and selection do not start rides',
    (tester) async {
      final remote = Completer<CoachData>();
      var loads = 0, selects = 0;
      CoachGoal? goal;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkoutCoachCard(
                ftp: 200,
                onSelect: (_) => selects++,
                onBrowse: () {},
                saveGoal: (value) async => goal = value,
                load: (_, {bool refreshRemote = false}) async {
                  loads++;
                  return refreshRemote
                      ? remote.future
                      : CoachData(history: [], candidates: [easy]);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Easy ride'), findsOneWidget);
      expect(selects, 0);
      expect(find.textContaining('Est. TSS 15'), findsOneWidget);
      expect(find.textContaining('weekly range'), findsNothing);
      await tester.ensureVisible(find.text('Load suggested ride'));
      await tester.tap(find.text('Load suggested ride'));
      expect(selects, 1);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<CoachGoal>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<CoachGoal>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build endurance').last);
      await tester.pumpAndSettle();
      expect(goal, CoachGoal.endurance);
      expect(loads, 2);
      remote.complete(CoachData(history: [], candidates: [easy]));
      await tester.pumpAndSettle();
      expect(selects, 1);
    },
  );

  testWidgets(
    'rest day has no load action and stays readable on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: WorkoutCoachCard(
                  ftp: 200,
                  onSelect: (_) => fail('Rest is not a ride'),
                  onBrowse: () {},
                  saveGoal: (_) async {},
                  load: (_, {bool refreshRemote = false}) async => CoachData(
                    candidates: [easy],
                    history: [
                      CoachRide(
                        id: 'hard',
                        start: DateTime.now().subtract(
                          const Duration(hours: 5),
                        ),
                        seconds: 3600,
                        tss: 110,
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
      expect(find.text('Take a rest day'), findsOneWidget);
      expect(find.text('Load suggested ride'), findsNothing);
      expect(find.textContaining('TSS'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
