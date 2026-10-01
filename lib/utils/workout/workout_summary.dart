import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'workout_controller.dart';
import 'workout_metric_row.dart';
import 'workout_visuals.dart';

class WorkoutSummary extends StatelessWidget {
  final WorkoutController workoutController;
  final Animation<double> fadeAnimation;

  const WorkoutSummary({
    super.key,
    required this.workoutController,
    required this.fadeAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final ride = workoutController;
    if (ride.segments.isEmpty) return const SizedBox.shrink();
    final totalTime = ride.totalDuration.round();
    double normalizedWork = 0;
    for (final segment in ride.segments) {
      normalizedWork +=
          segment.duration *
          ride.ftpValue *
          (segment.isRamp
              ? (segment.powerLow + segment.powerHigh) / 2
              : segment.powerLow);
    }
    final planned =
        !ride.isUnlimitedFreeRide && totalTime > 0 && ride.ftpValue > 0;
    final intensityFactor = planned
        ? normalizedWork / totalTime / ride.ftpValue
        : null;
    final tss = intensityFactor == null
        ? null
        : totalTime * intensityFactor * intensityFactor / 36;
    final inProgress = ride.workoutProgressSeconds > 0;
    final progress = ride.progressPosition.isFinite
        ? ride.progressPosition.clamp(0.0, 1.0)
        : 0.0;
    final complete = inProgress && !ride.isUnlimitedFreeRide && progress >= 1;
    final status = complete
        ? 'COMPLETE'
        : inProgress
        ? 'PAUSED'
        : 'READY';
    final items = <(WorkoutMetric, Color)>[
      (
        WorkoutMetric(
          label: 'Plan duration',
          value: ride.isUnlimitedFreeRide
              ? 'OPEN'
              : ride.formatDuration(totalTime),
        ),
        Colors.white,
      ),
      (
        WorkoutMetric(
          label: 'Planned TSS',
          value: tss != null && tss.isFinite ? tss.toStringAsFixed(1) : '—',
        ),
        WorkoutVisuals.gold,
      ),
      (
        WorkoutMetric(
          label: 'Planned IF',
          value: intensityFactor != null && intensityFactor.isFinite
              ? intensityFactor.toStringAsFixed(2)
              : '—',
        ),
        WorkoutVisuals.gold,
      ),
      if (inProgress) ...[
        (
          WorkoutMetric(
            label: 'Avg Power',
            value: ride.averagePower?.round().toString() ?? '—',
            unit: 'W',
          ),
          WorkoutVisuals.power,
        ),
        (
          WorkoutMetric(
            label: 'Avg Cadence',
            value: ride.averageCadence?.round().toString() ?? '—',
            unit: 'RPM',
          ),
          WorkoutVisuals.cadence,
        ),
        if (ride.averageHeartRate != null)
          (
            WorkoutMetric(
              label: 'Avg HR',
              value: ride.averageHeartRate!.round().toString(),
              unit: 'BPM',
            ),
            WorkoutVisuals.heartRate,
          ),
      ],
    ];
    final short = MediaQuery.sizeOf(context).height < 650;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return FadeTransition(
      opacity: fadeAnimation,
      child: Container(
        key: const ValueKey('workout-summary-panel'),
        margin: const EdgeInsets.all(8),
        padding: EdgeInsets.all(short ? 10 : 12),
        decoration: BoxDecoration(
          color: WorkoutVisuals.ink,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WorkoutVisuals.mint.withValues(alpha: .22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 3, height: 18, color: WorkoutVisuals.mint),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'WORKOUT SUMMARY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: WorkoutVisuals.mint,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: WorkoutVisuals.mint.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .7,
                      color: WorkoutVisuals.mint,
                    ),
                  ),
                ),
              ],
            ),
            if (inProgress) ...[
              const SizedBox(height: 7),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${ride.formatDuration(ride.elapsedSeconds)} ridden',
                    style: const TextStyle(
                      color: WorkoutVisuals.muted,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    ride.isUnlimitedFreeRide
                        ? 'FREE RIDE'
                        : '${(progress * 100).round()}% complete',
                    style: const TextStyle(
                      color: WorkoutVisuals.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              if (!ride.isUnlimitedFreeRide) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: WorkoutVisuals.mint,
                  backgroundColor: Colors.white10,
                  borderRadius: BorderRadius.circular(3),
                  semanticsLabel: 'Workout completion',
                  semanticsValue: '${(progress * 100).round()}%',
                ),
              ],
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = math.min(
                  items.length,
                  math.max(1, (constraints.maxWidth / 92).floor()),
                );
                final width =
                    (constraints.maxWidth - (columns - 1) * 4) / columns;
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (metric, color) in items)
                      MetricBox(
                        metric: metric,
                        width: width,
                        height: (short ? 56 : 68) * math.min(1.5, textScale),
                        valueColor: color,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
