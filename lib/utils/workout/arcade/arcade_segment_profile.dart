import '../workout_parser.dart';

/// Match the workout controller's ramp direction, including cooldown reversal.
double arcadeSegmentPower(WorkoutSegment segment, double progress) {
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

String arcadeTargetLabel(
  WorkoutSegment segment,
  double ftp, {
  bool percent = false,
}) {
  if (segment.type == SegmentType.freeRide) return 'FREE RIDE';
  int value(double progress) {
    final ratio = arcadeSegmentPower(segment, progress);
    if (percent) return (ratio * 100).round();
    // The same signed FTMS target range used by the workout control lane.
    return (ratio * (ftp.isFinite ? ftp : 0)).round().clamp(0, 0x7fff);
  }

  final start = value(0), end = value(1);
  return '${segment.isRamp && start != end ? '$start→$end' : '$start'}${percent ? '% FTP' : ' W'}';
}

String arcadeIntervalDuration(num seconds) {
  final value = seconds.isFinite ? seconds.ceil().clamp(0, 1 << 30) : 0;
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}
