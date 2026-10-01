import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'package:ss2kconfigapp/widgets/workout_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled workout recommendations offer variety at a stable load',
    () async {
      final candidates = <CoachCandidate>[];
      for (final asset in await WorkoutLibrary.loadAssetWorkouts()) {
        final candidate = CoachCandidate.fromChoice(
          WorkoutLobbyChoice(
            content: await rootBundle.loadString(asset.path),
            source: 'BUILT-IN',
          ),
        );
        if (candidate != null) candidates.add(candidate);
      }
      expect(candidates.length, greaterThan(20));
      final performancePicks = <String>{};
      final performanceSessions = <CoachSession>{};
      final consistentPicks = <String>{};
      final consistentSessions = <CoachSession>{};
      for (var offset = 0; offset < 14; offset++) {
        final now = DateTime(2026, 9, 10 + offset, 12);
        final history = [
          for (final days in [8, 10, 12, 15, 17, 19, 22, 24, 26, 29, 31, 33])
            CoachRide(
              id: '$days',
              start: now.subtract(Duration(days: days)),
              seconds: 3600,
              tss: 50,
            ),
        ];
        final performance = WorkoutCoach.recommend(
          history: history,
          candidates: candidates,
          now: now,
          goal: CoachGoal.performance,
        );
        final consistent = WorkoutCoach.recommend(
          history: history,
          candidates: candidates,
          now: now,
          goal: CoachGoal.consistent,
        );
        expect(performance.rest, isFalse);
        expect(consistent.rest, isFalse);
        performancePicks.add(performance.candidate!.choice.name);
        performanceSessions.add(performance.candidate!.session);
        consistentPicks.add(consistent.candidate!.choice.name);
        consistentSessions.add(consistent.candidate!.session);
      }
      expect(performancePicks.length, greaterThanOrEqualTo(5));
      expect(
        performanceSessions,
        containsAll([CoachSession.shortHiit, CoachSession.longIntervals]),
      );
      expect(consistentPicks.length, greaterThanOrEqualTo(2));
      expect(
        consistentSessions,
        containsAll([CoachSession.steady, CoachSession.longIntervals]),
      );
    },
  );
}
