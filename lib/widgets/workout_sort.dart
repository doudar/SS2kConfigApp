import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/workout/workout_training_load.dart';

enum WorkoutSort {
  original('Original order'),
  shortest('Shortest first'),
  longest('Longest first'),
  lowestTss('Lowest TSS first'),
  highestTss('Highest TSS first');

  const WorkoutSort(this.label);
  final String label;

  List<T> apply<T>(List<T> items, WorkoutPlanMetrics Function(T) metrics) {
    if (this == original) return items;
    final byDuration = this == shortest || this == longest;
    final descending = this == longest || this == highestTss;
    num? value(T item) {
      final plan = metrics(item);
      return byDuration ? plan.seconds : plan.tss;
    }

    // Stable sorting keeps ties in library order, including unknown values.
    final sorted = items.toList();
    mergeSort(
      sorted,
      compare: (a, b) {
        final left = value(a);
        final right = value(b);
        if (left == null) return right == null ? 0 : 1;
        if (right == null) return -1;
        return descending ? right.compareTo(left) : left.compareTo(right);
      },
    );
    return sorted;
  }
}

class WorkoutSortButton extends StatelessWidget {
  const WorkoutSortButton({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final WorkoutSort value;
  final ValueChanged<WorkoutSort> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<WorkoutSort>(
    tooltip: 'Sort workouts',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final sort in WorkoutSort.values)
        CheckedPopupMenuItem(
          value: sort,
          checked: sort == value,
          child: Text(sort.label),
        ),
    ],
    icon: const Icon(Icons.sort_rounded),
  );
}
