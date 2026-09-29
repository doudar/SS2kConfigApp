import 'package:flutter/material.dart';

import '../utils/calibration_monitor.dart';

/// Live firmware evidence, not a percentage or a countdown inferred from the
/// resistance value (which moves backwards while the map is being measured).
class FtmsCalibrationProgress extends StatelessWidget {
  const FtmsCalibrationProgress({
    super.key,
    required this.stage,
    required this.samples,
    required this.elapsed,
    this.reading,
  });

  final FtmsCalibrationStage stage;
  final int samples;
  final Duration elapsed;
  final HomingGaugeReading? reading;

  @override
  Widget build(BuildContext context) {
    final title = switch (stage) {
      FtmsCalibrationStage.lowBoundary => 'Measuring the low boundary',
      FtmsCalibrationStage.highBoundary => 'Measuring the high boundary',
      FtmsCalibrationStage.mapping => 'Building the resistance map',
      FtmsCalibrationStage.saving => 'Saving the resistance map',
    };
    final detail = switch (stage) {
      FtmsCalibrationStage.lowBoundary =>
        'Checking transitions near resistance 10 and 2 to estimate zero without reaching a physical stop.',
      FtmsCalibrationStage.highBoundary =>
        'Checking transitions near resistance 90 and 98 to estimate the upper limit. Mapping follows this step.',
      FtmsCalibrationStage.mapping =>
        'Sampling near resistance 67, 50 and 33. The middle point needs extra checks so SmartSpin2k can find home again. $samples of 3 samples confirmed.',
      FtmsCalibrationStage.saving =>
        'Measurements collected. Waiting for SmartSpin2k to confirm the calibration was saved.',
    };
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final value = reading;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(detail),
          if (value != null && stage != FtmsCalibrationStage.saving) ...[
            const SizedBox(height: 8),
            Text(
              'Resistance ${value.current.toStringAsFixed(0)} · Target ${value.target.toStringAsFixed(0)}',
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Elapsed $minutes:$seconds · Allow several minutes (roughly 3–5).',
          ),
          const SizedBox(height: 4),
          Text(
            'Timing varies with resistance updates and repeated checks. Pauses and small reversals are normal; keep Grupetto connected with BLE TX on.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
