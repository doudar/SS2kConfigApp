import 'dart:math' as math;
import 'workout_parser.dart';

/// Normalized-power estimate from one-second samples, including zero watts.
double normalizedPower(Iterable<double> watts) {
  final window = List<double>.filled(30, 0);
  var count = 0, windows = 0;
  var sum = 0.0, fourth = 0.0;
  for (final value in watts) {
    if (!value.isFinite || value < 0) continue;
    final index = count % 30;
    sum += value - window[index];
    window[index] = value;
    count++;
    if (count >= 30) {
      fourth += math.pow(sum / 30, 4);
      windows++;
    }
  }
  if (count == 0) return 0;
  return windows == 0
      ? sum / count
      : math.pow(fourth / windows, .25).toDouble();
}

class WorkoutTrainingLoad {
  const WorkoutTrainingLoad(this.seconds, this.intensity);
  final int seconds;
  final double intensity;
  double get tss => seconds / 36 * intensity * intensity;

  /// Planned relative-to-FTP load, not the load actually achieved on the bike.
  /// Free rides and max efforts have no prescribed power, so remain unknown.
  static WorkoutTrainingLoad? estimate(List<WorkoutSegment> segments) {
    final seconds = segments.fold<int>(0, (sum, s) => sum + s.duration);
    if (seconds <= 0 ||
        seconds > 24 * 3600 ||
        segments.any(
          (s) =>
              s.duration <= 0 ||
              s.type == SegmentType.freeRide ||
              s.type == SegmentType.maxEffort ||
              !s.minPower.isFinite ||
              !s.maxPower.isFinite ||
              s.minPower < 0,
        ))
      return null;
    Iterable<double> power() sync* {
      for (final segment in segments) {
        for (var t = 0; t < segment.duration; t++) {
          yield segment.getPowerAtTime(t);
        }
      }
    }

    final intensity = normalizedPower(power());
    return intensity.isFinite ? WorkoutTrainingLoad(seconds, intensity) : null;
  }

  static String label(double? tss) =>
      tss == null ? 'TSS —' : 'Est. TSS ${tss.round()}';
}

/// Planned library metrics. A timed free ride can have a duration without a load.
class WorkoutPlanMetrics {
  const WorkoutPlanMetrics({this.seconds, this.tss});

  final int? seconds;
  final double? tss;

  factory WorkoutPlanMetrics.fromZwo(String content) {
    try {
      final segments = WorkoutParser.parseZwoFile(content).segments;
      final seconds = segments.fold<int>(0, (sum, s) => sum + s.duration);
      return WorkoutPlanMetrics(
        seconds: seconds > 0 ? seconds : null,
        tss: WorkoutTrainingLoad.estimate(segments)?.tss,
      );
    } catch (_) {
      return const WorkoutPlanMetrics();
    }
  }

  String? get summary {
    final duration = seconds;
    if (duration == null) return null;
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final time = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    return '$time • ${WorkoutTrainingLoad.label(tss)}';
  }
}
