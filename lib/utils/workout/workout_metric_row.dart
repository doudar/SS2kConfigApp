import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:reorderables/reorderables.dart' show ReorderableWrap;
import 'workout_constants.dart';
import 'workout_metric_preferences.dart';

class WorkoutMetricRow extends StatefulWidget {
  final List<WorkoutMetric> metrics;

  const WorkoutMetricRow({
    Key? key,
    required this.metrics,
  }) : super(key: key);

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

  List<WorkoutMetric> _orderMetrics(List<WorkoutMetric> metrics, List<String> order) {
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.of(context).size;
        final isPortrait = screenSize.width < screenSize.height;

        return SizedBox(
          width: constraints.maxWidth,
          height: isPortrait
              ? (WorkoutSizes.metricBoxHeight * 2) + (3 * WorkoutPadding.small)
              : WorkoutSizes.metricBoxHeight + (2 * WorkoutPadding.small),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: isPortrait ? constraints.maxWidth : null,
              child: ReorderableWrap(
                direction: Axis.horizontal,
                spacing: WorkoutPadding.metricHorizontal,
                runSpacing: WorkoutPadding.small,
                onReorder: _handleReorder,
                children: orderedMetrics.asMap().entries.map((entry) {
                  return ReorderableDragStartListener(
                    key: ValueKey(entry.value.label),
                    index: entry.key,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: WorkoutPadding.metricHorizontal,
                      ),
                      child: MetricBox(metric: entry.value),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = orderedMetrics.removeAt(oldIndex);
      orderedMetrics.insert(newIndex, item);
    });
    
    final newOrder = orderedMetrics.map((m) => m.label).toList();
    await WorkoutMetricPreferences.saveMetricOrder(newOrder);
  }
}

class MetricBox extends StatelessWidget {
  final WorkoutMetric metric;

  const MetricBox({
    Key? key,
    required this.metric,
  }) : super(key: key);

  double _calculateFontSize(String text, double boxWidth) {
    double fontSize = WorkoutFontSizes.metricValueBase;
    double estimatedWidth = text.length * (fontSize * 0.6);
    
    if (estimatedWidth > boxWidth - WorkoutPadding.metricBoxContent) {
      fontSize = min(
        WorkoutFontSizes.metricValueBase,
        max(
          WorkoutFontSizes.metricValueMin,
          (boxWidth - WorkoutPadding.metricBoxContent) / (text.length * 0.6)
        )
      );
    }
    
    return fontSize;
  }

  double _calculateBoxWidth(String value) {
    double width = value.length * WorkoutSizes.metricCharacterWidth;
    if (metric.unit != null) {
      width += (metric.unit!.length * WorkoutSizes.metricCharacterWidth) + WorkoutSpacing.metricValueUnit;
    }
    return width.clamp(WorkoutSizes.metricBoxMinWidth, WorkoutSizes.metricBoxMaxWidth);
  }

  @override
  Widget build(BuildContext context) {
    final boxWidth = _calculateBoxWidth(metric.value);
    final valueFontSize = _calculateFontSize(metric.value, boxWidth);

    return Container(
      width: boxWidth,
      height: WorkoutSizes.metricBoxHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(WorkoutSizes.metricBoxBorderRadius),
        boxShadow: [WorkoutShadows.metricBox],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            style: TextStyle(
              fontSize: WorkoutFontSizes.metricLabel,
              fontWeight: WorkoutFontWeights.metricLabel,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          SizedBox(height: WorkoutSpacing.metricLabelValue),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                metric.value,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: WorkoutFontWeights.metricValue,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              if (metric.unit != null) ...[
                SizedBox(width: WorkoutSpacing.metricValueUnit),
                Text(
                  metric.unit!,
                  style: TextStyle(
                    fontSize: WorkoutFontSizes.metricUnit,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class WorkoutMetric {
  final String label;
  final String value;
  final String? unit;

  const WorkoutMetric({
    required this.label,
    required this.value,
    this.unit,
  });

  factory WorkoutMetric.power({required int watts}) {
    return WorkoutMetric(
      label: 'Power',
      value: watts.toString(),
      unit: 'W',
    );
  }

  factory WorkoutMetric.heartRate({required int bpm}) {
    return WorkoutMetric(
      label: 'Heart Rate',
      value: bpm.toString(),
      unit: 'BPM',
    );
  }

  factory WorkoutMetric.cadence({required int rpm}) {
    return WorkoutMetric(
      label: 'Cadence',
      value: rpm.toString(),
      unit: 'RPM',
    );
  }

  factory WorkoutMetric.elapsedTime({required int seconds}) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    
    return WorkoutMetric(
      label: 'Elapsed Time',
      value: '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}',
    );
  }

  factory WorkoutMetric.remainingTime({required int totalSeconds, required int elapsedSeconds, required double workoutProgressSeconds}) {
    final remainingSeconds = totalSeconds - workoutProgressSeconds.round();
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    final seconds = remainingSeconds % 60;
    
    return WorkoutMetric(
      label: 'Remaining Time',
      value: '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
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
