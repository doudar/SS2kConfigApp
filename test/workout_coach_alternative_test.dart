import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_card.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_repository.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'workout_coach_test.dart' as fixtures;

void main() {
  test(
    'alternatives retain load and eligibility limits across daily picks',
    () {
      final choices = [
        fixtures.candidate('Easy A', .6, 1800),
        fixtures.candidate('Easy B', .6, 1920),
        fixtures.candidate('Easy C', .6, 2040),
        fixtures.candidate('Too long', .6, 2700),
        fixtures.candidate('Too intense', .7, 1400),
      ];
      for (var day = 0; day < 7; day++) {
        final advice = WorkoutCoach.recommend(
          history: [],
          candidates: [...choices, choices.first],
          now: fixtures.now.add(Duration(days: day)),
        );
        final original = advice.candidate!;
        expect(advice.alternatives, isNotEmpty);
        final contents = {original.choice.content};
        for (final alternative in advice.alternatives) {
          expect(
            alternative.tss,
            inInclusiveRange(original.tss * .9, original.tss * 1.1),
          );
          expect(alternative.session, original.session);
          expect(alternative.intensity, lessThanOrEqualTo(.65));
          expect(alternative.choice.name, isNot('Too long'));
          expect(contents.add(alternative.choice.content), isTrue);
        }
      }
      final rest = WorkoutCoach.recommend(
        history: [fixtures.ride(0, 150)],
        candidates: choices,
        now: fixtures.now,
      );
      expect(rest.rest, isTrue);
      expect(rest.alternatives, isEmpty);
    },
  );

  testWidgets(
    'switch cycles previews without loading and revalidates on refresh',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var choices = [
        fixtures.candidate('An easy workout with a long name A', .6, 2000),
        fixtures.candidate('An easy workout with a long name B', .6, 2000),
        fixtures.candidate('An easy workout with a long name C', .6, 2000),
      ];
      WorkoutLobbyChoice? loaded;
      var loads = 0;
      Widget app(double ftp) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: WorkoutCoachCard(
                ftp: ftp,
                isConnected: () async => false,
                onSelect: (choice) {
                  loaded = choice;
                  loads++;
                },
                onBrowse: () {},
                load: (_, {bool refreshRemote = false}) async =>
                    CoachData(history: [], candidates: choices),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(200));
      await tester.pumpAndSettle();
      String displayed() => choices
          .singleWhere((c) => find.text(c.choice.name).evaluate().isNotEmpty)
          .choice
          .name;
      final original = displayed();
      final seen = {original};
      final switcher = find.byKey(const ValueKey('workout-coach-alternative'));
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(switcher);
        await tester.tap(switcher);
        await tester.pumpAndSettle();
        seen.add(displayed());
        expect(loads, 0);
      }
      expect(seen.length, 3);
      expect(displayed(), original);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      final switched = displayed();
      expect(switched, isNot(original));
      await tester.ensureVisible(find.text('Load suggested ride'));
      await tester.tap(find.text('Load suggested ride'));
      expect(loaded!.name, switched);
      expect(loads, 1);
      choices = [fixtures.candidate('Replacement', .6, 2000)];
      await tester.pumpWidget(app(210));
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.text(switched), findsNothing);
      expect(tester.widget<IconButton>(switcher).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scheduled rides do not offer recommendation switching', (
    tester,
  ) async {
    final planned = fixtures.candidate('Scheduled', .6, 2000);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkoutCoachCard(
              ftp: 200,
              onSelect: (_) {},
              onBrowse: () {},
              isConnected: () async => true,
              loadToday: () async => {'workout_file': planned.choice.content},
              load: (_, {bool refreshRemote = false}) async => CoachData(
                history: [],
                candidates: [
                  fixtures.candidate('Easy A', .6, 2000),
                  fixtures.candidate('Easy B', .6, 2000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scheduled'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workout-coach-alternative')),
      findsNothing,
    );
  });
}
