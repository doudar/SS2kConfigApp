import 'dart:math' as math;
import 'workout_lobby_choice.dart';
import 'workout_parser.dart';
import 'workout_coach_recovery.dart';
import 'workout_training_load.dart';
export 'workout_training_load.dart' show normalizedPower;

enum CoachGoal {
  consistent('Stay consistent'),
  endurance('Build endurance'),
  performance('Improve performance'),
  returning('Ease back in');

  const CoachGoal(this.label);
  final String label;
}

class CoachRide {
  const CoachRide({
    required this.id,
    required this.start,
    required this.seconds,
    required this.tss,
    this.estimated = false,
    this.remote = false,
  });
  final String id;
  final DateTime start;
  final int seconds;
  final double? tss;
  final bool estimated, remote;
  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toIso8601String(),
    'seconds': seconds,
    'tss': tss,
    'estimated': estimated,
    'remote': remote,
  };
  factory CoachRide.fromJson(Map<String, dynamic> value) => CoachRide(
    id: value['id'] as String,
    start: DateTime.parse(value['start'] as String),
    seconds: (value['seconds'] as num).toInt(),
    tss: (value['tss'] as num?)?.toDouble(),
    estimated: value['estimated'] == true,
    remote: value['remote'] == true,
  );
}

class CoachRange {
  const CoachRange(this.low, this.high);
  final double low, high;
  bool get valid =>
      low.isFinite && high.isFinite && low >= 0 && high > low && high <= 10000;
}

class CoachCandidate {
  const CoachCandidate(this.choice, this.seconds, this.tss, this.intensity);
  final WorkoutLobbyChoice choice;
  final int seconds;
  final double tss, intensity;
  double get peakIntensity => choice.workout.segments.fold<double>(
    0,
    (peak, segment) => math.max(peak, segment.maxPower),
  );
  static CoachCandidate? fromChoice(WorkoutLobbyChoice choice) {
    final segments = choice.workout.segments;
    final seconds = segments.fold<int>(0, (sum, s) => sum + s.duration);
    // Open-ended or self-paced efforts have no reliable planned TSS.
    if (seconds < 300 ||
        seconds > 4 * 3600 ||
        segments.any(
          (s) =>
              s.duration <= 0 ||
              s.type == SegmentType.freeRide ||
              s.type == SegmentType.maxEffort,
        ))
      return null;
    final load = WorkoutTrainingLoad.estimate(segments);
    if (load == null || load.intensity <= 0 || load.intensity > 2) return null;
    return CoachCandidate(choice, seconds, load.tss, load.intensity);
  }
}

class CoachAdvice {
  const CoachAdvice({
    required this.title,
    required this.reason,
    required this.weekTss,
    required this.rides,
    required this.unknownRides,
    this.range,
    this.candidate,
    this.rest = false,
    this.estimated = false,
    this.manualRange = false,
    this.recoveryNote,
  });
  final String title, reason;
  final String? recoveryNote;
  final double weekTss;
  final int rides, unknownRides;
  final CoachRange? range;
  final CoachCandidate? candidate;
  final bool rest, estimated, manualRange;
}

class WorkoutCoach {
  /// Prefer Intervals' measured load when a saved local ride was also uploaded.
  static List<CoachRide> mergeRides(List<CoachRide> rides) {
    final ordered = [...rides]
      ..sort((a, b) {
        if ((a.tss == null) != (b.tss == null)) return a.tss == null ? 1 : -1;
        return (b.remote ? 1 : 0).compareTo(a.remote ? 1 : 0);
      });
    final result = <CoachRide>[];
    for (final ride in ordered) {
      if (result.any(
        (other) =>
            other.id == ride.id ||
            (!(other.remote && ride.remote) &&
                other.start.difference(ride.start).inSeconds.abs() <= 60 &&
                (other.seconds - ride.seconds).abs() <=
                    math.max(30, ride.seconds * .03)),
      ))
        continue;
      result.add(ride);
    }
    return result;
  }

  static CoachAdvice recommend({
    required List<CoachRide> history,
    required List<CoachCandidate> candidates,
    required DateTime now,
    CoachGoal goal = CoachGoal.consistent,
    CoachRange? target,
    bool incomplete = false,
    List<CoachWellness>? wellness,
  }) {
    final recovery = wellness == null
        ? null
        : CoachRecovery.assess(
            wellness,
            now,
            formEaseThreshold: switch (goal) {
              CoachGoal.returning => -.1,
              CoachGoal.consistent => -.2,
              CoachGoal.endurance => -.25,
              CoachGoal.performance => -.3,
            },
          );
    final rides = mergeRides(history)
        .where(
          (r) =>
              !r.start.isAfter(now) &&
              r.start.isAfter(now.subtract(const Duration(days: 35))),
        )
        .toList();
    final week = rides
        .where((r) => r.start.isAfter(now.subtract(const Duration(days: 7))))
        .toList();
    final total = week.fold<double>(0, (sum, r) => sum + (r.tss ?? 0));
    final unknown = week.where((r) => r.tss == null).length;
    final manual = target?.valid ?? false;
    // Current CTL/ATL already model accumulated load. A simple weekly average
    // is a fallback, not another ceiling that can veto that model.
    final useFitnessModel = !manual && (recovery?.fitness ?? 0) > 0;
    if (!manual) {
      target = null;
      final prior = rides
          .where((r) => !r.start.isAfter(now.subtract(const Duration(days: 7))))
          .toList();
      // Avoid inventing a training baseline from one or two saved rides.
      if (!incomplete &&
          prior.length >= 6 &&
          prior.every((r) => r.tss != null) &&
          prior.any(
            (r) => r.start.isBefore(now.subtract(const Duration(days: 21))),
          )) {
        final weeks = List<double>.filled(4, 0);
        for (final ride in prior) {
          final bucket =
              (now.difference(ride.start).inSeconds / (7 * 86400)).floor() - 1;
          if (bucket >= 0 && bucket < 4) weeks[bucket] += ride.tss!;
        }
        final average = weeks.reduce((a, b) => a + b) / 4;
        final factors = switch (goal) {
          CoachGoal.returning => (.65, .85),
          CoachGoal.consistent => (.85, 1.0),
          CoachGoal.endurance => (.9, 1.08),
          CoachGoal.performance => (.9, 1.1),
        };
        if (average > 0)
          target = CoachRange(average * factors.$1, average * factors.$2);
      }
    }
    final lastDay = week
        .where((r) => r.start.isAfter(now.subtract(const Duration(hours: 24))))
        .fold<double>(0, (sum, r) => sum + (r.tss ?? 0));
    final atCeiling =
        !useFitnessModel && target != null && total >= target.high;
    final recentHard =
        lastDay >= (target == null ? 100 : math.max(50, target.high * .35));
    final hardRecently = week
        .where(
          (r) =>
              r.start.isAfter(now.subtract(const Duration(hours: 48))) &&
              r.tss != null &&
              r.seconds >= 1200 &&
              math.sqrt(r.tss! * 36 / r.seconds) >= .85,
        )
        .isNotEmpty;
    // Frequency alone says nothing about load: four short recovery spins can
    // be easier than one long ride. Rest requires load or recovery evidence.
    final rest = atCeiling || recentHard || recovery?.rest == true;
    // Missing individual summaries do not erase today's established CTL/ATL.
    // Keep unknown TSS unknown, and use the aggregate model when available.
    final uncertain = !useFitnessModel && (incomplete || unknown > 0);
    final easy =
        rest ||
        recovery?.easeOff == true ||
        uncertain ||
        (!useFitnessModel && (target == null || total >= target.low)) ||
        goal == CoachGoal.returning ||
        hardRecently;
    final usualSessions = rides.where((r) => r.tss != null).toList();
    final usualLoad = usualSessions.isEmpty
        ? (useFitnessModel ? recovery!.fitness! : 30.0)
        : usualSessions.fold<double>(0, (sum, r) => sum + r.tss!) /
              usualSessions.length;
    final sessionLimit = (usualLoad * 1.15).clamp(25.0, 80.0);
    final desired = easy
        ? 20.0
        : math.min(
            sessionLimit,
            useFitnessModel
                ? usualLoad.clamp(20.0, 65.0)
                : ((target!.low - total) / 2).clamp(20.0, 65.0),
          );
    final remaining = useFitnessModel || target == null
        ? double.infinity
        : math.max(0, target.high - total);
    final preferredIntensity = easy
        ? .55
        : goal == CoachGoal.performance
        ? .85
        : .7;
    double score(CoachCandidate candidate) =>
        (candidate.tss - desired).abs() / desired +
        (candidate.intensity - preferredIntensity).abs() * 3;
    final eligible =
        candidates
            .where(
              (c) =>
                  c.intensity <=
                      (easy
                          ? .65
                          : goal == CoachGoal.performance
                          ? 1.0
                          : .8) &&
                  c.tss <= (easy ? 35 : sessionLimit) &&
                  // A low overall intensity can still hide short hard bursts.
                  (!easy || c.peakIntensity <= .8) &&
                  c.seconds <= (easy ? 2700 : 5400) &&
                  (rest || c.tss <= remaining),
            )
            .toList()
          ..sort((a, b) => score(a).compareTo(score(b)));
    // A library mismatch is not evidence that the rider needs a rest day.
    final noMatch = !rest && eligible.isEmpty;
    return CoachAdvice(
      title: rest
          ? 'Take a rest day'
          : noMatch
          ? 'Explore a different ride'
          : easy
          ? 'Keep it comfortable'
          : goal == CoachGoal.performance
          ? 'A little more challenge'
          : 'Build a steady week',
      reason: recovery?.rest == true
          ? recovery!.reason!
          : atCeiling
          ? 'Your recent training load is high compared with your usual weeks. Take today to recover.'
          : recentHard
          ? 'You have accumulated substantial training load in the last 24 hours. Favor recovery today.'
          : noMatch
          ? 'No available workout fits today’s suggested effort. Browse for a shorter or gentler ride.'
          : recovery?.easeOff == true
          ? recovery!.reason!
          : uncertain
          ? 'Some recent ride data is unavailable. An easy session is a better starting point for now.'
          : goal == CoachGoal.returning
          ? 'Keep the effort gentle as you ease back into a routine.'
          : hardRecently
          ? 'You have done a harder ride recently. Keep this session easy.'
          : !useFitnessModel && target == null
          ? 'We are still learning your routine. Start comfortably while you build up a few weeks of ride history.'
          : !useFitnessModel && total >= target!.low
          ? 'You are keeping up with your usual routine. An easy ride leaves room for recovery.'
          : useFitnessModel
          ? 'Your current fitness and fatigue leave room for ${goal == CoachGoal.performance ? 'a little more challenge' : 'a steady session'}, with the workout sized to ${usualSessions.isEmpty ? 'your current training load' : 'your recent rides'}.'
          : goal == CoachGoal.performance
          ? 'Your recent rides leave room for a little more challenge, within the effort you are used to.'
          : 'Your recent rides leave room for a steady session to support your goal.',
      weekTss: total,
      rides: week.length,
      unknownRides: unknown,
      range: target,
      candidate: rest ? null : eligible.firstOrNull,
      rest: rest,
      estimated: week.any((r) => r.estimated),
      manualRange: manual,
      recoveryNote: recovery?.note,
    );
  }
}
