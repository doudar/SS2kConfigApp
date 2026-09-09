import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_recovery.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_repository.dart';
import 'workout_coach_test.dart' as fixtures;

void main() {
  final now = fixtures.now;
  final today = DateTime(now.year, now.month, now.day);
  final prior = [
    for (var i = 1; i <= 14; i++)
      CoachWellness(
        day: today.subtract(Duration(days: i)),
        sleepSecs: 28800,
        restingHR: 50,
        hrv: 60,
      ),
  ];
  CoachAdvice advice(
    List<CoachWellness> wellness, {
    CoachGoal goal = CoachGoal.performance,
    List<CoachRide>? history,
  }) => WorkoutCoach.recommend(
    history: history ?? fixtures.baseline(),
    candidates: fixtures.choices,
    now: now,
    goal: goal,
    wellness: wellness,
  );

  test(
    'fitness and modeled fatigue remain distinct from subjective fatigue',
    () {
      final rows = parseIntervalsCoachWellness([
        {
          'id': '2026-09-10',
          'ctl': 46,
          'atl': 56,
          'fatigue': 1,
          'ctlLoad': 150,
          'atlLoad': 150,
        },
      ]);
      expect(rows.single.form, -10);
      expect(rows.single.fatigue, 1);
      expect(advice(rows).rest, isFalse);
      expect(advice(rows).candidate!.choice.name, 'Tempo');
      expect(
        advice(rows, goal: CoachGoal.consistent).candidate!.choice.name,
        'Easy spin',
      );
      expect(CoachWellness.fromJson(rows.single.toJson())!.form, -10);
    },
  );

  test('substantial modeled fatigue suggests rest for every goal', () {
    for (final goal in CoachGoal.values) {
      final result = advice([
        CoachWellness(day: today, fitness: 46, fatigueLoad: 76),
      ], goal: goal);
      expect(result.rest, isTrue);
      expect(result.candidate, isNull);
      expect(result.reason, contains('fatigue compared with your fitness'));
    }
    // A positive form reading cannot override a large recent completed ride.
    final result = advice(
      [CoachWellness(day: today, fitness: 46, fatigueLoad: 20)],
      history: [
        ...fixtures.baseline(),
        CoachRide(
          id: 'hard',
          start: now.subtract(const Duration(hours: 5)),
          seconds: 3600,
          tss: 110,
        ),
      ],
    );
    expect(result.rest, isTrue);
  });

  test('45/49/-4 uses current fitness instead of a hard weekly-average cap', () {
    final current = CoachWellness(day: today, fitness: 45, fatigueLoad: 49);
    for (final load in [50.0, 60.0]) {
      // Prior average is 150/week; current week is either near or above its cap.
      final history = [
        ...fixtures.baseline(),
        for (final day in [2, 4, 6]) fixtures.ride(day, load),
      ];
      final result = advice([current], history: history);
      expect(result.rest, isFalse);
      expect(result.candidate!.choice.name, 'Tempo');
      expect(result.reason, contains('current fitness and fatigue'));
      expect(result.reason, isNot(contains('already done plenty')));
    }
    // Current CTL supplies an established baseline even with a short local history.
    final sparse = advice([current], history: [fixtures.ride(2, 50)]);
    expect(sparse.rest, isFalse);
    expect(sparse.candidate!.choice.name, 'Tempo');
  });

  test(
    'weekly fallback and other recovery rules still apply when appropriate',
    () {
      final busy = [
        ...fixtures.baseline(),
        for (final day in [2, 4, 6]) fixtures.ride(day, 60),
      ];
      for (final rows in [
        <CoachWellness>[],
        [
          CoachWellness(
            day: today.subtract(const Duration(days: 1)),
            fitness: 45,
            fatigueLoad: 49,
          ),
        ],
        [CoachWellness(day: today, fitness: 45)],
      ]) {
        expect(advice(rows, history: busy).rest, isTrue);
      }
      expect(
        advice([
          CoachWellness(day: today, fitness: 45, fatigueLoad: 49, fatigue: 4),
        ], history: busy).rest,
        isTrue,
      );
      expect(
        advice([
          CoachWellness(day: today, fitness: 45, fatigueLoad: 80),
        ], history: busy).rest,
        isTrue,
      );
      final incomplete = WorkoutCoach.recommend(
        history: busy,
        candidates: fixtures.choices,
        now: now,
        goal: CoachGoal.performance,
        incomplete: true,
        wellness: [CoachWellness(day: today, fitness: 45, fatigueLoad: 49)],
      );
      expect(incomplete.rest, isFalse);
      expect(incomplete.candidate!.choice.name, 'Tempo');
    },
  );

  test(
    'current Intervals baseline remains usable with missing ride summaries',
    () {
      final wellness = [
        CoachWellness(day: today, fitness: 45, fatigueLoad: 49),
      ];
      for (final history in [
        [...fixtures.baseline(), fixtures.ride(2, null)],
        [for (var day = 1; day <= 5; day++) fixtures.ride(day, null)],
        <CoachRide>[],
      ]) {
        for (final incomplete in [false, true]) {
          final result = WorkoutCoach.recommend(
            history: history,
            candidates: fixtures.choices,
            now: now,
            goal: CoachGoal.performance,
            incomplete: incomplete,
            wellness: wellness,
          );
          expect(result.rest, isFalse);
          expect(result.candidate!.choice.name, 'Tempo');
          expect(result.reason, contains('current fitness and fatigue'));
          expect(result.reason, isNot(contains('unavailable')));
          expect(result.reason, isNot(contains('still learning')));
          expect(
            result.unknownRides,
            history.where((r) => r.tss == null).length,
          );
        }
      }
    },
  );

  test(
    'missing ride summaries do not suppress known load or recovery warnings',
    () {
      final unknown = [fixtures.ride(3, null)];
      final hard = CoachRide(
        id: 'race',
        start: now.subtract(const Duration(hours: 5)),
        seconds: 14400,
        tss: 225,
      );
      final result = advice(
        [CoachWellness(day: today, fitness: 45, fatigueLoad: 49)],
        history: [...unknown, hard],
      );
      expect(result.rest, isTrue);
      expect(result.reason, contains('last 24 hours'));
      expect(
        advice([
          CoachWellness(day: today, fitness: 45, fatigueLoad: 80),
        ], history: unknown).rest,
        isTrue,
      );
      expect(
        advice([
          CoachWellness(day: today, fitness: 45, fatigueLoad: 49, fatigue: 4),
        ], history: unknown).rest,
        isTrue,
      );
      // Without a current model, unknown per-ride load still requires a fallback.
      for (final wellness in [
        <CoachWellness>[],
        [
          CoachWellness(
            day: today.subtract(const Duration(days: 1)),
            fitness: 45,
            fatigueLoad: 49,
          ),
        ],
        [CoachWellness(day: today, fitness: 45)],
      ]) {
        final fallback = advice(wellness, history: unknown);
        expect(fallback.candidate!.choice.name, 'Easy spin');
        expect(fallback.reason, contains('unavailable'));
      }
    },
  );

  test(
    'one personal recovery deviation eases off; corroborating signals suggest rest',
    () {
      final easy = advice([
        ...prior,
        CoachWellness(day: today, sleepSecs: 18000),
      ]);
      expect(easy.rest, isFalse);
      expect(easy.candidate!.choice.name, 'Easy spin');
      expect(easy.reason, contains('less sleep than usual'));
      final rest = advice([
        ...prior,
        CoachWellness(day: today, restingHR: 60, hrv: 40),
      ]);
      expect(rest.rest, isTrue);
      expect(rest.candidate, isNull);
      expect(rest.reason, contains('resting heart rate'));
      expect(advice([CoachWellness(day: today, fatigue: 4)]).rest, isTrue);
    },
  );

  test(
    'old, future and incomplete wellness never manufacture current readiness',
    () {
      final yesterday = CoachWellness(
        day: today.subtract(const Duration(days: 1)),
        fatigue: 4,
        fitness: 46,
        fatigueLoad: 100,
      );
      final tomorrow = CoachWellness(
        day: today.add(const Duration(days: 1)),
        fatigue: 4,
        fitness: 46,
        fatigueLoad: 100,
      );
      for (final rows in [
        <CoachWellness>[],
        [yesterday, tomorrow],
        [CoachWellness(day: today, restingHR: 60, hrv: 40)],
      ]) {
        final result = advice(rows);
        expect(result.rest, isFalse);
        expect(result.candidate!.choice.name, 'Tempo');
      }
      expect(
        advice([CoachWellness(day: today, restingHR: 60)]).recoveryNote,
        contains('Learning your recovery baseline'),
      );
      // Seven distinct historical days are needed, not repeated same-day rows.
      final duplicates = List.filled(10, prior.first);
      expect(
        advice([...duplicates, CoachWellness(day: today, restingHR: 80)]).rest,
        isFalse,
      );
    },
  );

  test(
    'invalid ratings, carried-forward resting HR and unrelated fields are ignored',
    () {
      final rows = parseIntervalsCoachWellness([
        {'id': 'bad', 'fatigue': 4},
        {
          'id': '2026-09-10',
          'sleepSecs': -1,
          'restingHR': 60,
          'tempRestingHR': true,
          'hrv': 0,
          'fatigue': 0,
          'soreness': 7,
          'readiness': 1,
          'sleepScore': 1,
        },
      ]);
      expect(rows, isEmpty);
      final missingLoad = CoachWellness.fromJson({
        'id': '2026-09-10',
        'ctl': 46,
      });
      expect(missingLoad!.form, isNull);
    },
  );
}
