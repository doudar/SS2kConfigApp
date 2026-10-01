import 'dart:math' as math;
import '../workout_parser.dart';
import 'arcade_session.dart';

/// Shared by the road convoy, distant silhouette and escape audio.
class ArcadeEscape {
  static double? duration(double? seconds, Iterable<WorkoutSegment> segments) {
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    for (final segment in segments) {
      if (segment.duration <= 0) continue;
      final duration = math.min(segment.duration.toDouble(), 23.0);
      if (seconds >= duration || biomeFor(segment) == ArcadeBiome.volcano) {
        return null;
      }
      return duration;
    }
    return null;
  }

  static double roadProgress(double seconds, double duration) =>
      (seconds / math.min(15.0, duration)).clamp(0.0, 1.0);

  static double distance(double progress) => progress * progress;

  static double volume(double seconds, double? duration) {
    if (duration == null || duration <= 0 || !seconds.isFinite || seconds < 0)
      return 0;
    final progress = roadProgress(seconds, duration);
    final remaining = 1 - distance(progress);
    // Ease-in matches the runner's increasing distance; the distant hillside
    // silhouette is inaudible. Fade the initial transient in over 120 ms.
    return .34 * remaining * remaining * (seconds / .12).clamp(0.0, 1.0);
  }
}
