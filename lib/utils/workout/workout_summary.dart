import 'package:flutter/material.dart';
import 'workout_constants.dart';
import 'workout_controller.dart';

class WorkoutSummary extends StatelessWidget {
  final WorkoutController workoutController;
  final Animation<double> fadeAnimation;

  const WorkoutSummary({
    Key? key,
    required this.workoutController,
    required this.fadeAnimation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (workoutController.segments.isEmpty) return const SizedBox.shrink();

    int totalTime = workoutController.totalDuration.round();
    double normalizedWork = 0;

    for (var segment in workoutController.segments) {
      if (segment.isRamp) {
        normalizedWork += segment.duration * ((segment.powerLow + segment.powerHigh) / 2) * workoutController.ftpValue;
      } else {
        normalizedWork += segment.duration * segment.powerLow * workoutController.ftpValue;
      }
    }

    final intensityFactor = (normalizedWork / totalTime) / workoutController.ftpValue;
    final tss = (totalTime * intensityFactor * intensityFactor) / 36;
    final bool isPausedInProgress = !workoutController.isPlaying && workoutController.progressPosition > 0;
    final avgPower = workoutController.averagePower;
    final avgCadence = workoutController.averageCadence;
    final avgHeartRate = workoutController.averageHeartRate;

    return FadeTransition(
      opacity: fadeAnimation,
      child: Card(
        margin: EdgeInsets.all(WorkoutPadding.small),
        child: Padding(
          padding: EdgeInsets.all(WorkoutPadding.standard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workout Summary',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: WorkoutSpacing.xsmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SummaryItem(
                    label: 'Duration',
                    value: workoutController.formatDuration(totalTime),
                    icon: Icons.timer,
                  ),
                  _SummaryItem(
                    label: 'TSS',
                    value: tss.toStringAsFixed(1),
                    icon: Icons.fitness_center,
                  ),
                  _SummaryItem(
                    label: 'IF',
                    value: intensityFactor.toStringAsFixed(2),
                    icon: Icons.show_chart,
                  ),
                ],
              ),
              if (isPausedInProgress) ...[
                SizedBox(height: WorkoutSpacing.small),
                Text(
                  'In-Progress Snapshot',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: WorkoutSpacing.xsmall),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SummaryItem(
                      label: 'Elapsed',
                      value: workoutController.formatDuration(workoutController.elapsedSeconds),
                      icon: Icons.timer_outlined,
                    ),
                    _SummaryItem(
                      label: 'Complete',
                      value: '${(workoutController.progressPosition * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      icon: Icons.timelapse,
                    ),
                    _SummaryItem(
                      label: 'Avg Power',
                      value: avgPower != null ? '${avgPower.round()}W' : '--',
                      icon: Icons.bolt,
                    ),
                    _SummaryItem(
                      label: 'Avg Cadence',
                      value: avgCadence != null ? '${avgCadence.round()}rpm' : '--',
                      icon: Icons.speed,
                    ),
                    if (avgHeartRate != null)
                      _SummaryItem(
                        label: 'Avg HR',
                        value: '${avgHeartRate.round()}bpm',
                        icon: Icons.favorite,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24),
        SizedBox(height: WorkoutSpacing.xxsmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
