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

  /// Classify the prescribed work, not its average intensity: recovery between
  /// hard repetitions can make a HIIT session look like an endurance ride.
  CoachSession get session {
    var shortHard = 0;
    var longHard = 0;
    var sustained = 0;
    for (final segment in choice.workout.segments) {
      final power = segment.minPower;
      if (power >= 1.05) {
        if (segment.duration <= 120) {
          shortHard += segment.duration;
        } else {
          longHard += segment.duration;
        }
      } else if (power >= .85 && segment.duration >= 180) {
        sustained += segment.duration;
      }
    }
    if (shortHard >= 180) return CoachSession.shortHiit;
    if (longHard >= 480 || sustained >= 600) {
      return CoachSession.longIntervals;
    }
    return CoachSession.steady;
  }

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

enum CoachSession { steady, longIntervals, shortHiit }

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
        lastDay >=
        (target == null ? 100 : (target.high * .55).clamp(90.0, 150.0));
    final recentLoad =
        lastDay >= (target == null ? 50 : (target.high * .3).clamp(45.0, 80.0));
    bool isHardRide(CoachRide ride) {
      if (ride.tss == null || ride.seconds < 1200 || ride.tss! < 40) {
        return false;
      }
      final intensity = math.sqrt(ride.tss! * 36 / ride.seconds);
      // Short interval sessions can have modest average load because of the
      // recovery steps. Longer rides need stronger evidence of intensity.
      return intensity >= .85 || (ride.seconds <= 3000 && intensity >= .75);
    }

    final hardRecently = week
        .where(
          (r) =>
              r.start.isAfter(now.subtract(const Duration(hours: 48))) &&
              isHardRide(r),
        )
        .isNotEmpty;
    // Frequency alone says nothing about load: four short recovery spins can
    // be easier than one long ride. Rest requires load or recovery evidence.
    // A full rolling week calls for an easy day, not repeated full rest days
    // until the oldest ride falls out of the seven-day window.
    final rest = recentHard || recovery?.rest == true;
    // Missing individual summaries do not erase today's established CTL/ATL.
    // Keep unknown TSS unknown, and use the aggregate model when available.
    final uncertain = !useFitnessModel && (incomplete || unknown > 0);
    final easy =
        rest ||
        recovery?.easeOff == true ||
        atCeiling ||
        recentLoad ||
        uncertain ||
        (!useFitnessModel && (target == null || total >= target.low)) ||
        goal == CoachGoal.returning ||
        hardRecently;
    final usualSessions = rides.where((r) => r.tss != null).toList();
    final usualLoad = usualSessions.isEmpty
        ? (useFitnessModel ? recovery!.fitness! : 30.0)
        : usualSessions.fold<double>(0, (sum, r) => sum + r.tss!) /
              usualSessions.length;
    // Planned TSS is an estimate. A 15% per-session cap excluded most of the
    // bundled library, making one workout win on almost every fresh day.
    final sessionLimit = math
        .max(usualLoad * 1.3, usualLoad + 20)
        .clamp(30.0, 90.0);
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
    final qualityWeek = week.where((ride) {
      if (isHardRide(ride)) return true;
      if (ride.tss == null || ride.seconds < 1200 || ride.tss! < 65) {
        return false;
      }
      return math.sqrt(ride.tss! * 36 / ride.seconds) >= .75;
    }).length;
    final day =
        DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final canDoIntervals =
        !easy &&
        (goal == CoachGoal.performance || goal == CoachGoal.endurance) &&
        qualityWeek < (goal == CoachGoal.performance ? 2 : 1);
    final canDoSustained =
        !easy && goal == CoachGoal.consistent && qualityWeek == 0;
    final preferredSession = canDoIntervals
        ? goal == CoachGoal.performance && (day + qualityWeek).isEven
              ? CoachSession.shortHiit
              : CoachSession.longIntervals
        : CoachSession.steady;
    double score(CoachCandidate c) =>
        (c.tss - desired).abs() / desired +
        (c.intensity - preferredIntensity).abs() * 2;
    CoachCandidate? pick(List<CoachCandidate> options) {
      if (options.isEmpty) return null;
      final best = score(options.first);
      final close = options.where((c) => score(c) <= best + .2).toList()
        ..sort((a, b) => a.choice.name.compareTo(b.choice.name));
      // Performance alternates the session type each day. Rotate within each
      // type's own sequence so the same parity does not always pick one name.
      final rotation = canDoIntervals && goal == CoachGoal.performance
          ? day ~/ 2
          : day;
      return close[rotation % close.length];
    }

    final eligible =
        candidates
            .where(
              (c) =>
                  c.intensity <=
                      (easy
                          ? .65
                          : goal == CoachGoal.performance
                          ? 1.0
                          : goal == CoachGoal.endurance
                          ? .9
                          : .8) &&
                  c.tss <= (easy ? 35 : sessionLimit) &&
                  // A low overall intensity can still hide short hard bursts.
                  (canDoIntervals ||
                      (canDoSustained && c.peakIntensity <= .95) ||
                      c.peakIntensity <= .8) &&
                  c.seconds <=
                      (easy
                          ? 2700
                          : goal == CoachGoal.endurance
                          ? 7200
                          : 5400) &&
                  (easy || c.tss <= remaining) &&
                  (canDoIntervals ||
                      c.session == CoachSession.steady ||
                      (canDoSustained &&
                          c.session == CoachSession.longIntervals &&
                          c.peakIntensity <= .95)),
            )
            .toList()
          ..sort((a, b) => score(a).compareTo(score(b)));
    // Pick the planned stimulus among reasonably sized sessions. If the
    // library lacks it, use the closest safe workout instead.
    final matching = eligible
        .where(
          (c) =>
              (c.session == preferredSession ||
                  (canDoSustained &&
                      c.session == CoachSession.longIntervals &&
                      c.peakIntensity <= .95)) &&
              c.tss >= desired * .65 &&
              c.tss <= desired * 1.35,
        )
        .toList();
    // A library mismatch is not evidence that the rider needs a rest day.
    final noMatch = !rest && eligible.isEmpty;
    final selected = rest ? null : (pick(matching) ?? pick(eligible));
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
          : recentHard
          ? 'You have accumulated substantial training load in the last 24 hours. Favor recovery today.'
          : noMatch
          ? 'No available workout fits today’s suggested effort. Browse for a shorter or gentler ride.'
          : recovery?.easeOff == true
          ? recovery!.reason!
          : atCeiling
          ? 'You have reached your usual weekly training load. Keep today easy and let that work settle.'
          : recentLoad
          ? 'You have already put in a solid ride in the last 24 hours. Keep the next session easy.'
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
          : matching.isNotEmpty && preferredSession == CoachSession.shortHiit
          ? 'Short, hard intervals support your performance goal. Keep harder sessions spaced out with easier riding.'
          : matching.isNotEmpty &&
                preferredSession == CoachSession.longIntervals
          ? 'Longer intervals build sustained power for your goal. Keep harder sessions spaced out with easier riding.'
          : goal == CoachGoal.consistent &&
                selected?.session == CoachSession.longIntervals
          ? 'A controlled sustained session adds variety while keeping the week manageable.'
          : useFitnessModel
          ? 'Your current fitness and fatigue leave room for ${goal == CoachGoal.performance ? 'a little more challenge' : 'a steady session'}, with the workout sized to ${usualSessions.isEmpty ? 'your current training load' : 'your recent rides'}.'
          : goal == CoachGoal.performance
          ? 'Your recent rides leave room for a little more challenge, within the effort you are used to.'
          : 'Your recent rides leave room for a steady session to support your goal.',
      weekTss: total,
      rides: week.length,
      unknownRides: unknown,
      range: target,
      candidate: selected,
      rest: rest,
      estimated: week.any((r) => r.estimated),
      manualRange: manual,
      recoveryNote: recovery?.note,
    );
  }
}
