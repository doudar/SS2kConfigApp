import 'package:flutter/material.dart';
import '../device_data.dart';
import 'workout_constants.dart';
import 'workout_metric_row.dart';

class WorkoutMetrics extends StatelessWidget {
  final DeviceData deviceData;
  final Animation<double> fadeAnimation;
  final int elapsedTime;
  final int timeToNextSegment;
  final double totalDuration;
  final double? speedMph;
  final double? totalDistance;
  final double workoutProgressSeconds;
  final bool isUnlimitedFreeRide;

  const WorkoutMetrics({
    Key? key,
    required this.deviceData,
    required this.fadeAnimation,
    required this.elapsedTime,
    required this.timeToNextSegment,
    required this.totalDuration,
    required this.workoutProgressSeconds,
    this.speedMph,
    this.totalDistance,
    this.isUnlimitedFreeRide = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final metrics = [
      WorkoutMetric.elapsedTime(seconds: elapsedTime),
      WorkoutMetric.power(watts: deviceData.ftmsData.watts),
      WorkoutMetric(
        label: 'Target',
        value: deviceData.ftmsData.targetERG.toString(),
        unit: 'W',
      ),
      WorkoutMetric.cadence(rpm: deviceData.ftmsData.cadence),
      if (deviceData.ftmsData.heartRate != 0)
        WorkoutMetric.heartRate(bpm: deviceData.ftmsData.heartRate),
      WorkoutMetric.speed(mph: speedMph ?? 0.0),
      WorkoutMetric.distance(miles: (totalDistance ?? 0.0) / 1609.34),
      WorkoutMetric(
        label: 'Next Block',
        value: isUnlimitedFreeRide ? '--:--:--' : _formatDuration(timeToNextSegment),
      ),
      WorkoutMetric.remainingTime(
        totalSeconds: totalDuration.round(),
        elapsedSeconds: elapsedTime,
        workoutProgressSeconds: workoutProgressSeconds,
        isUnlimited: isUnlimitedFreeRide,
      ),
    ];

    return Center(
      child: FadeTransition(
        opacity: ReverseAnimation(fadeAnimation),
        child: Card(
          margin: EdgeInsets.symmetric(
            horizontal: WorkoutPadding.small,
            vertical: WorkoutSpacing.small,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: WorkoutPadding.standard,
              vertical: WorkoutPadding.small,
            ),
            child: SizedBox(
              width: double.infinity,
              child: WorkoutMetricRow(metrics: metrics),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
