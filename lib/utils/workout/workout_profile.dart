import 'package:flutter/material.dart';
import 'workout_parser.dart';
import 'workout_constants.dart';

/// One source for profile, zone breakdown, and arcade road colors and cutoffs.
enum WorkoutPowerZone {
  recovery('Recovery', WorkoutZones.recovery, Color(0xff65ddd2)),
  endurance('Endurance', WorkoutZones.endurance, Color(0xff65b6f4)),
  tempo('Tempo', WorkoutZones.tempo, Color(0xff83cc83)),
  sweetSpot('Sweet spot', WorkoutZones.sweetSpot, Color(0xffedcf69)),
  threshold('Threshold', WorkoutZones.threshold, Color(0xffefa55d)),
  vo2max('VO₂ max', WorkoutZones.vo2max, Color(0xffef7766)),
  anaerobic('Anaerobic', double.infinity, Color(0xffc985d9)),
  selfPaced('Self-paced', double.infinity, Color(0xffa4b5cc));

  const WorkoutPowerZone(this.label, this.upper, this.color);
  final String label;
  final double upper;
  final Color color;

  static WorkoutPowerZone forPower(double power) {
    if (!power.isFinite || power < 0) return selfPaced;
    return values.firstWhere((zone) => power <= zone.upper);
  }

  static WorkoutPowerZone forSegment(
    WorkoutSegment segment, [
    double progress = .5,
  ]) {
    if (segment.type == SegmentType.freeRide ||
        segment.type == SegmentType.maxEffort) {
      return selfPaced;
    }
    return forPower(workoutSegmentPower(segment, progress));
  }
}

/// Split ramps at zone crossings, rather than coloring the whole ramp by its mean.
List<double> workoutZoneStops(WorkoutSegment segment) {
  final stops = <double>[0, 1];
  if (!segment.isRamp ||
      WorkoutPowerZone.forSegment(segment) == WorkoutPowerZone.selfPaced)
    return stops;
  final start = workoutSegmentPower(segment, 0);
  final delta = workoutSegmentPower(segment, 1) - start;
  if (delta == 0) return stops;
  for (final zone in WorkoutPowerZone.values) {
    final t = (zone.upper - start) / delta;
    if (t > 0 && t < 1) stops.add(t);
  }
  return stops..sort();
}

/// Broad gameplay bands determine encounters and scenery, independently of
/// the more detailed power-zone colors on the road and workout profile.
enum WorkoutEffort {
  easy(Color(0xff53d9b0)),
  steady(Color(0xff60cdff)),
  hard(Color(0xffb391ff)),
  intense(Color(0xffff8068));

  const WorkoutEffort(this.color);
  final Color color;
}

WorkoutEffort workoutEffort(WorkoutSegment segment) {
  if (segment.type == SegmentType.freeRide) return WorkoutEffort.steady;
  final power = segment.isRamp
      ? (segment.powerLow + segment.powerHigh) / 2
      : segment.powerLow;
  if (power >= 1.05) return WorkoutEffort.intense;
  if (power >= .85) return WorkoutEffort.hard;
  if (power >= .60) return WorkoutEffort.steady;
  return WorkoutEffort.easy;
}

/// Controller-compatible ramp direction, including descending cooldowns.
double workoutSegmentPower(WorkoutSegment segment, double progress) {
  final t = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
  final start = segment.type == SegmentType.cooldown
      ? segment.powerHigh
      : segment.powerLow;
  final end = segment.type == SegmentType.cooldown
      ? segment.powerLow
      : segment.powerHigh;
  final power = segment.isRamp ? start + (end - start) * t : segment.powerLow;
  return power.isFinite ? power : 0;
}
