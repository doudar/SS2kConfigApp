import 'package:flutter/material.dart';

import 'arcade/arcade_segment_profile.dart';
import 'workout_controller.dart';
import 'workout_painter.dart';
import 'workout_visuals.dart';

/// The system manages PiP gestures. Expanding the window restores ride controls.
class WorkoutPipView extends StatelessWidget {
  const WorkoutPipView({
    super.key,
    required this.controller,
    required this.finished,
  });

  final WorkoutController controller;
  final bool finished;

  @override
  Widget build(BuildContext context) => Material(
    color: WorkoutVisuals.ink,
    child: FittedBox(
      child: SizedBox(
        width: 240,
        height: 120,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (finished) {
                return const Center(
                  child: Text(
                    'Workout complete',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                );
              }
              final metrics = controller.deviceData.ftmsData;
              final segment = controller.currentSegment;
              final index = segment == null
                  ? 0
                  : controller.segments.indexOf(segment);
              final ahead = controller.segments.skip(index).take(5).toList();
              final duration = ahead.fold<int>(
                0,
                (sum, step) => sum + step.duration,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        _MetricReading(
                          label: 'Power',
                          value: metrics.watts,
                          unit: 'W',
                          color: WorkoutVisuals.power,
                        ),
                        _MetricReading(
                          label: 'Target',
                          value: metrics.targetERG,
                          unit: 'W',
                          color: WorkoutVisuals.gold,
                        ),
                        _MetricReading(
                          label: 'Cadence',
                          value: metrics.cadence,
                          unit: 'RPM',
                          color: WorkoutVisuals.cadence,
                        ),
                      ],
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${arcadeIntervalDuration(controller.currentSegmentTimeRemaining)} left in interval',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Semantics(
                      label: 'Current interval and upcoming workout profile',
                      image: true,
                      child: CustomPaint(
                        painter: WorkoutPainter.preview(
                          ahead,
                          progress: duration > 0
                              ? controller.currentSegmentElapsedSeconds /
                                    duration
                              : 0,
                          highlightCurrent: true,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _MetricReading extends StatelessWidget {
  const _MetricReading({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });
  final String label;
  final int value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text.rich(
            TextSpan(
              text: '$value',
              children: [
                TextSpan(text: ' $unit', style: const TextStyle(fontSize: 12)),
              ],
            ),
            style: TextStyle(
              color: color,
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}
