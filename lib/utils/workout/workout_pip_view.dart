import 'package:flutter/material.dart';

import 'arcade/arcade_segment_profile.dart';
import 'workout_controller.dart';
import 'workout_painter.dart';
import 'workout_visuals.dart';

// A figure space occupies one digit position without displaying a leading zero.
String _digits(int value) => value.toString().padLeft(3, '\u2007');
const _numberStyle = TextStyle(fontFamily: 'monospace');

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
    // Android supplies the outer PiP shape, including square windows on Fire OS.
    color: WorkoutVisuals.panel,
    shape: const Border.fromBorderSide(BorderSide(color: Color(0xff43516a))),
    child: FittedBox(
      child: SizedBox(
        width: 240,
        height: 120,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
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
              final timeLeft = arcadeIntervalDuration(
                controller.currentSegmentTimeRemaining,
              );
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
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: timeLeft, style: _numberStyle),
                                const TextSpan(text: ' left'),
                              ],
                            ),
                            semanticsLabel: '$timeLeft left in interval',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      if (metrics.heartRate > 0) ...[
                        const SizedBox(width: 4),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.favorite,
                                  size: 12,
                                  color: WorkoutVisuals.heartRate,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${_digits(metrics.heartRate)} BPM',
                                  semanticsLabel:
                                      'Heart rate, ${metrics.heartRate} beats per minute',
                                  style: _numberStyle.copyWith(
                                    color: WorkoutVisuals.heartRate,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Expanded(
                    child: Semantics(
                      label: 'Current interval and upcoming workout profile',
                      image: true,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: ColoredBox(
                          color: WorkoutVisuals.ink,
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
              text: _digits(value),
              children: [
                TextSpan(text: ' $unit', style: const TextStyle(fontSize: 12)),
              ],
            ),
            style: _numberStyle.copyWith(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}
