import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_repository.dart';

final now = DateTime(2026, 9, 10, 12);
CoachCandidate candidate(
  String name,
  double power,
  int seconds, {
  String source = 'BUILT-IN',
}) => CoachCandidate.fromChoice(
  WorkoutLobbyChoice(
    source: source,
    content:
        '<workout_file><name>$name</name><workout><SteadyState Duration="$seconds" Power="$power"/></workout></workout_file>',
  ),
)!;
CoachRide ride(
  int days,
  double? tss, {
  String? id,
  bool remote = false,
  int seconds = 3600,
}) => CoachRide(
  id: id ?? '$days',
  start: now.subtract(Duration(days: days)),
  seconds: seconds,
  tss: tss,
  remote: remote,
);
List<CoachRide> baseline() => [
  for (final day in [8, 10, 12, 15, 17, 19, 22, 24, 26, 29, 31, 33])
    ride(day, 50),
];
final choices = [
  candidate('Easy spin', .55, 2400),
  candidate('Endurance', .7, 3600, source: 'YOUR LIBRARY'),
  candidate('Tempo', .85, 2400, source: 'INTERVALS.ICU'),
];

void main() {
  test('steady power estimates and ramp profiles use normalized intensity', () {
    expect(normalizedPower(List.filled(3600, 200)), 200);
    expect(candidate('Threshold', 1, 3600).tss, closeTo(100, .01));
    expect(candidate('Half power', .5, 3600).tss, closeTo(25, .01));
    expect(
      normalizedPower([
        ...List.filled(1800, 100.0),
        ...List.filled(1800, 300.0),
      ]),
      greaterThan(200),
    );
  });

  test('goals change suggestions using the same prior history', () {
    final endurance = WorkoutCoach.recommend(
      history: baseline(),
      candidates: choices,
      now: now,
      goal: CoachGoal.endurance,
    );
    final performance = WorkoutCoach.recommend(
      history: baseline(),
      candidates: choices,
      now: now,
      goal: CoachGoal.performance,
    );
    final returning = WorkoutCoach.recommend(
      history: baseline(),
      candidates: choices,
      now: now,
      goal: CoachGoal.returning,
    );
    expect(endurance.candidate!.choice.name, 'Endurance');
    expect(performance.candidate!.choice.name, 'Tempo');
    expect(returning.candidate!.choice.name, 'Easy spin');
  });

  test('missing or sparse history does not manufacture a fitness baseline', () {
    for (final history in [
      <CoachRide>[],
      [ride(2, 30)],
    ]) {
      final advice = WorkoutCoach.recommend(
        history: history,
        candidates: choices,
        now: now,
        goal: CoachGoal.performance,
      );
      expect(advice.range, isNull);
      expect(advice.candidate!.intensity, lessThanOrEqualTo(.65));
    }
  });

  test('easy suggestions exclude short hard bursts despite low overall load', () {
    final bursts = CoachCandidate.fromChoice(
      WorkoutLobbyChoice(
        source: 'YOUR LIBRARY',
        content:
            '<workout_file><name>Bursts</name><workout>'
            '<SteadyState Duration="1790" Power="0.5"/>'
            '<SteadyState Duration="10" Power="1.3"/></workout></workout_file>',
      ),
    )!;
    expect(bursts.intensity, lessThan(.65));
    final advice = WorkoutCoach.recommend(
      history: [],
      candidates: [bursts],
      now: now,
    );
    expect(advice.candidate, isNull);
  });

  test('no suitable library workout is not reported as a need for rest', () {
    final advice = WorkoutCoach.recommend(
      history: baseline(),
      candidates: [],
      now: now,
      goal: CoachGoal.performance,
    );
    expect(advice.rest, isFalse);
    expect(advice.title, 'Explore a different ride');
    expect(advice.reason, contains('No available workout'));
    expect(advice.candidate, isNull);
  });

  test('high weekly load and a hard last day each suggest rest', () {
    for (final extra in [
      [ride(2, 85), ride(4, 85)],
      [
        CoachRide(
          id: 'hard',
          start: now.subtract(const Duration(hours: 5)),
          seconds: 3600,
          tss: 110,
        ),
      ],
    ]) {
      final advice = WorkoutCoach.recommend(
        history: [...baseline(), ...extra],
        candidates: choices,
        now: now,
        goal: CoachGoal.performance,
      );
      expect(advice.rest, isTrue);
      expect(advice.candidate, isNull);
    }
  });

  test(
    'four consecutive rides are judged by load, not the number of rides',
    () {
      final spin = candidate('15 minute spin', .5, 900);
      expect(spin.tss, closeTo(6.25, .01));
      final easy = WorkoutCoach.recommend(
        history: [
          ...baseline(),
          for (var day = 1; day <= 4; day++)
            ride(day, spin.tss, seconds: spin.seconds),
        ],
        candidates: choices,
        now: now,
        goal: CoachGoal.performance,
      );
      final demanding = WorkoutCoach.recommend(
        history: [
          ...baseline(),
          for (var day = 1; day <= 4; day++) ride(day, 60),
        ],
        candidates: choices,
        now: now,
        goal: CoachGoal.performance,
      );
      expect(easy.rides, 4);
      expect(demanding.rides, 4);
      expect(easy.rest, isFalse);
      expect(easy.candidate, isNotNull);
      expect(demanding.rest, isTrue);
      expect(demanding.reason, contains('training load'));
    },
  );

  test(
    'one short easy spin and one four-hour effort produce different advice',
    () {
      CoachAdvice after(CoachCandidate completed) => WorkoutCoach.recommend(
        history: [
          ...baseline(),
          CoachRide(
            id: 'completed',
            start: now.subtract(const Duration(hours: 5)),
            seconds: completed.seconds,
            tss: completed.tss,
          ),
        ],
        candidates: choices,
        now: now,
        goal: CoachGoal.performance,
      );
      final spin = candidate('15 minute spin', .5, 900);
      final longRide = candidate('Four hour endurance', .75, 14400);
      expect(longRide.tss, closeTo(225, .01));
      expect(after(spin).rides, 1);
      expect(after(longRide).rides, 1);
      expect(after(spin).rest, isFalse);
      expect(after(longRide).rest, isTrue);
    },
  );

  test('unknown ride load is uncertainty, not evidence of overload', () {
    final advice = WorkoutCoach.recommend(
      history: [
        ...baseline(),
        for (var day = 1; day <= 4; day++) ride(day, null, seconds: 14400),
      ],
      candidates: choices,
      now: now,
      goal: CoachGoal.performance,
    );
    expect(advice.unknownRides, 4);
    expect(advice.rest, isFalse);
    expect(advice.candidate!.intensity, lessThanOrEqualTo(.65));
    expect(advice.reason, contains('unavailable'));
  });

  test(
    'recovery after recent intensity and incomplete histories never recommends a hard ride',
    () {
      for (final incomplete in [false, true]) {
        final advice = WorkoutCoach.recommend(
          history: [
            ...baseline(),
            CoachRide(
              id: 'hard',
              start: now.subtract(const Duration(hours: 30)),
              seconds: 2400,
              tss: 55,
            ),
          ],
          candidates: choices,
          now: now,
          goal: CoachGoal.performance,
          incomplete: incomplete,
        );
        expect(advice.candidate!.intensity, lessThanOrEqualTo(.65));
      }
    },
  );

  test(
    'uploaded local ride counted once, preferring remote load, with rolling cutoff',
    () {
      final advice = WorkoutCoach.recommend(
        history: [
          ride(2, 40, id: 'local'),
          ride(2, 45, id: 'remote', remote: true),
          ride(8, 90),
          ride(-1, 100),
        ],
        candidates: choices,
        now: now,
      );
      expect(advice.weekTss, 45);
      expect(advice.rides, 1);
      final unknown = WorkoutCoach.recommend(
        history: [ride(2, null)],
        candidates: choices,
        now: now,
      );
      expect(unknown.unknownRides, 1);
      expect(unknown.candidate!.intensity, lessThanOrEqualTo(.65));
    },
  );

  test(
    'unbounded free rides have no invented load and noncycling history is excluded',
    () {
      expect(
        CoachCandidate.fromChoice(
          WorkoutLobbyChoice(
            source: 'TEST',
            content:
                '<workout_file><workout><FreeRide Duration="0"/></workout></workout_file>',
          ),
        ),
        isNull,
      );
      final history = parseIntervalsCoachRides([
        {
          'id': '1',
          'type': 'Run',
          'start_date_local': now.toIso8601String(),
          'moving_time': 3600,
          'icu_training_load': 80,
        },
        {
          'id': '2',
          'type': 'Ride',
          'start_date_local': now.toIso8601String(),
          'moving_time': 3600,
        },
      ]);
      expect(history.length, 1);
      expect(history.single.tss, isNull);
      final rows = parseIntervalsCoachChoices([
        {
          'children': [
            {
              'type': 'Ride',
              'name': 'Saved tempo',
              'workout_doc': {
                'steps': [
                  {
                    'duration': 1800,
                    'power': {'value': 80, 'units': '%ftp'},
                  },
                ],
              },
            },
          ],
        },
      ]);
      expect(parseCoachCandidates(rows).single.choice.source, 'INTERVALS.ICU');
    },
  );
}
