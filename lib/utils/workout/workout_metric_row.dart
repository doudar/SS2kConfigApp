import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:reorderables/reorderables.dart' show ReorderableWrap;
import 'workout_visuals.dart';
import 'workout_metric_preferences.dart';

class WorkoutMetricRow extends StatefulWidget {
  final List<WorkoutMetric> metrics;

  const WorkoutMetricRow({Key? key, required this.metrics}) : super(key: key);

  @override
  State<WorkoutMetricRow> createState() => _WorkoutMetricRowState();
}

class _WorkoutMetricRowState extends State<WorkoutMetricRow> {
  List<WorkoutMetric> orderedMetrics = [];

  @override
  void initState() {
    super.initState();
    orderedMetrics = List.from(widget.metrics);
    _loadMetricOrder();
  }

  @override
  void didUpdateWidget(WorkoutMetricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.metrics, oldWidget.metrics)) {
      _updateOrderedMetrics();
    }
  }

  Future<void> _loadMetricOrder() async {
    try {
      final order = await WorkoutMetricPreferences.getMetricOrder();
      if (mounted) {
        setState(() {
          orderedMetrics = _orderMetrics(widget.metrics, order);
        });
      }
    } catch (e) {
      print('Error loading metric order: $e');
    }
  }

  void _updateOrderedMetrics() {
    final currentLabels = orderedMetrics.map((m) => m.label).toList();
    setState(() {
      orderedMetrics = _orderMetrics(widget.metrics, currentLabels);
    });
  }

  List<WorkoutMetric> _orderMetrics(
    List<WorkoutMetric> metrics,
    List<String> order,
  ) {
    final metricMap = {for (var m in metrics) m.label: m};
    final orderedList = <WorkoutMetric>[];

    for (var label in order) {
      if (metricMap.containsKey(label)) {
        orderedList.add(metricMap[label]!);
        metricMap.remove(label);
      }
    }

    orderedList.addAll(metricMap.values);
    return orderedList;
  }

  @override
  Widget build(BuildContext context) {
    if (orderedMetrics.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = MediaQuery.sizeOf(context).height < 500;
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final minimumWidth = (short ? 86.0 : 104.0) * min(1.1, scale);
        final count = orderedMetrics.length;
        final capacity = max(1, (constraints.maxWidth / minimumWidth).floor());
        final rows = short ? 1 : (count / capacity).ceil();
        final columns = (count / rows).ceil();
        final width = short
            ? max(constraints.maxWidth, columns * minimumWidth)
            : constraints.maxWidth;
        const gap = 4.0;
        final tileWidth = (width - (columns - 1) * gap) / columns;
        final tileHeight = (short ? 54.0 : 68.0) * min(1.6, scale);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: ReorderableWrap(
              spacing: gap,
              runSpacing: gap,
              alignment: WrapAlignment.center,
              onReorder: _handleReorder,
              children: [
                for (final metric in orderedMetrics)
                  MetricBox(
                    key: ValueKey(metric.label),
                    metric: metric,
                    width: tileWidth,
                    height: tileHeight,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleReorder(int oldIndex, int newIndex) async {
    setState(() {
      // ReorderableWrap supplies the final slot, unlike ReorderableListView.
      final item = orderedMetrics.removeAt(oldIndex);
      orderedMetrics.insert(newIndex, item);
    });

    final newOrder = orderedMetrics.map((m) => m.label).toList();
    await WorkoutMetricPreferences.saveMetricOrder(newOrder);
  }
}

class MetricBox extends StatelessWidget {
  final WorkoutMetric metric;
  final double width;
  final double height;
  final Color? valueColor;

  const MetricBox({
    super.key,
    required this.metric,
    this.width = 120,
    this.height = 68,
    this.valueColor,
  });

  Color get _accent => switch (metric.label) {
    'Power' => WorkoutVisuals.power,
    'Target' => WorkoutVisuals.gold,
    'Cadence' => WorkoutVisuals.cadence,
    'Heart Rate' => WorkoutVisuals.heartRate,
    _ => Colors.white,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${metric.label}: ${metric.value} ${metric.unit ?? ''}',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: WorkoutVisuals.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                metric.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1,
                  color: WorkoutVisuals.muted,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metric.value,
                    key: ValueKey('metric-value-${metric.label}'),
                    style: TextStyle(
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: valueColor ?? _accent,
                    ),
                  ),
                ),
              ),
            ),
            // Units get their own fixed row so they never shift the number.
            Text(
              metric.unit ?? '',
              style: const TextStyle(
                fontSize: 9,
                height: 1.2,
                color: WorkoutVisuals.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutMetric {
  final String label;
  final String value;
  final String? unit;

  const WorkoutMetric({required this.label, required this.value, this.unit});

  factory WorkoutMetric.power({required int watts}) {
    return WorkoutMetric(label: 'Power', value: watts.toString(), unit: 'W');
  }

  factory WorkoutMetric.heartRate({required int bpm}) {
    return WorkoutMetric(
      label: 'Heart Rate',
      value: bpm.toString(),
      unit: 'BPM',
    );
  }

  factory WorkoutMetric.cadence({required int rpm}) {
    return WorkoutMetric(label: 'Cadence', value: rpm.toString(), unit: 'RPM');
  }

  factory WorkoutMetric.elapsedTime({required int seconds}) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    return WorkoutMetric(
      label: 'Elapsed Time',
      value:
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}',
    );
  }

  factory WorkoutMetric.remainingTime({
    required int totalSeconds,
    required int elapsedSeconds,
    required double workoutProgressSeconds,
    bool isUnlimited = false,
  }) {
    if (isUnlimited) {
      return const WorkoutMetric(label: 'Remaining Time', value: '--:--:--');
    }
    final remainingSeconds = totalSeconds - workoutProgressSeconds.round();
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    final seconds = remainingSeconds % 60;

    return WorkoutMetric(
      label: 'Remaining Time',
      value:
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
    );
  }

  factory WorkoutMetric.speed({required double mph}) {
    return WorkoutMetric(
      label: 'Speed',
      value: mph.toStringAsFixed(1),
      unit: 'MPH',
    );
  }

  factory WorkoutMetric.distance({required double miles}) {
    return WorkoutMetric(
      label: 'Distance',
      value: miles.toStringAsFixed(2),
      unit: 'MI',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutMetric &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          value == other.value &&
          unit == other.unit;

  @override
  int get hashCode => label.hashCode ^ value.hashCode ^ unit.hashCode;
}
