import 'package:flutter/material.dart';
import '../services/intervals_workout_converter.dart';
import '../utils/workout/workout_training_load.dart';
import 'workout_dialog.dart';
import 'workout_sort.dart';

/// A bounded, navigable Intervals.icu folder viewport shared by all entry points.
class IntervalsWorkoutFolderDialog extends StatefulWidget {
  const IntervalsWorkoutFolderDialog({
    super.key,
    required this.folder,
    required this.thumbnailBuilder,
  });
  final Map<String, dynamic> folder;
  final Widget Function(BuildContext, Map<String, dynamic>) thumbnailBuilder;

  @override
  State<IntervalsWorkoutFolderDialog> createState() =>
      _IntervalsWorkoutFolderDialogState();
}

class _IntervalsWorkoutFolderDialogState
    extends State<IntervalsWorkoutFolderDialog> {
  late final _folders = <Map<String, dynamic>>[widget.folder];

  WorkoutSort _sort = WorkoutSort.original;
  final _metrics = Map<Map<String, dynamic>, WorkoutPlanMetrics>.identity();

  WorkoutPlanMetrics _plan(Map<String, dynamic> workout) =>
      _metrics.putIfAbsent(workout, () {
        final seconds = int.tryParse('${workout['moving_time']}');
        final load = double.tryParse('${workout['icu_training_load']}');
        final duration = seconds != null && seconds > 0 ? seconds : null;
        final reported = load != null && load.isFinite && load >= 0
            ? load
            : null;
        if (duration != null && reported != null) {
          return WorkoutPlanMetrics(seconds: duration, tss: reported);
        }
        final content = IntervalsWorkoutConverter.convertEventToZwo(workout);
        final estimated = content == null
            ? const WorkoutPlanMetrics()
            : WorkoutPlanMetrics.fromZwo(content);
        return WorkoutPlanMetrics(
          seconds: duration ?? estimated.seconds,
          tss: reported ?? estimated.tss,
        );
      });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> currentFolder = _folders.last;
    final children = (currentFolder['children'] is List)
        ? (currentFolder['children'] as List).whereType<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    final subfolders = children.where((c) => c['children'] is List).toList();
    final workouts = _sort.apply(
      children
          .where((c) => c['workout_doc'] != null || c['workout_file'] != null)
          .toList(),
      _plan,
    );

    return WorkoutDialog(
      listBody: true,
      icon: Icons.folder_open_rounded,
      title: Row(
        children: [
          if (_folders.length > 1)
            IconButton(
              tooltip: 'Go back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _folders.removeLast()),
            ),
          Expanded(child: Text('${currentFolder['name'] ?? 'Workouts'}')),
          if (workouts.length > 1)
            WorkoutSortButton(
              value: _sort,
              onChanged: (value) => setState(() => _sort = value),
            ),
        ],
      ),
      content: ListView.builder(
        key: ValueKey(currentFolder),
        shrinkWrap: true,
        itemCount: subfolders.isEmpty && workouts.isEmpty
            ? 1
            : subfolders.length + workouts.length,
        itemBuilder: (context, index) {
          if (subfolders.isEmpty && workouts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No workouts in this folder yet.'),
            );
          }
          if (index < subfolders.length) {
            final folder = subfolders[index];
            final name = (folder['name'] ?? 'Folder').toString();
            return WorkoutOptionTile(
              leading: const Icon(Icons.folder),
              title: Text(name),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                setState(() {
                  _folders.add(folder);
                });
              },
            );
          }

          final workout = workouts[index - subfolders.length];
          final name = (workout['name'] ?? 'Workout').toString();
          String formatDuration(int seconds) {
            final h = seconds ~/ 3600;
            final m = (seconds % 3600) ~/ 60;
            final s = seconds % 60;
            String two(int v) => v.toString().padLeft(2, '0');
            if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
            return '${two(m)}:${two(s)}';
          }

          final plan = _plan(workout);
          final movingTime = plan.seconds;
          final load = plan.tss;
          final intensity = (workout['icu_intensity'] is num)
              ? (workout['icu_intensity'] as num).toDouble()
              : double.tryParse('${workout['icu_intensity'] ?? ''}') ?? 0.0;

          final subtitleParts = <String>[];
          if (movingTime != null) subtitleParts.add(formatDuration(movingTime));
          if (load != null) subtitleParts.add('TL ${load.round()}');
          if (intensity > 0)
            subtitleParts.add('IF ${intensity.toStringAsFixed(2)}');
          final subtitle = subtitleParts.isEmpty
              ? null
              : subtitleParts.join(' • ');

          return WorkoutOptionTile(
            leading: widget.thumbnailBuilder(context, workout),
            title: Text(name),
            subtitle: subtitle != null ? Text(subtitle) : null,
            onTap: () => Navigator.of(context).pop(workout),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('BACK'),
        ),
      ],
    );
  }
}
