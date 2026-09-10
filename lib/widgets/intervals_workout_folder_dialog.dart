import 'package:flutter/material.dart';
import 'workout_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> currentFolder = _folders.last;
    final children = (currentFolder['children'] is List)
        ? List<Map<String, dynamic>>.from(
            (currentFolder['children'] as List).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e),
            ),
          )
        : <Map<String, dynamic>>[];

    final subfolders = children.where((c) => c['children'] is List).toList();
    final workouts = children
        .where((c) => c['workout_doc'] != null || c['workout_file'] != null)
        .toList();

    return WorkoutDialog(
      listBody: true,
      icon: Icons.folder_open_rounded,
      title: Text('Workouts • ${currentFolder['name'] ?? 'Folder'}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_folders.length > 1)
              WorkoutOptionTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Go back'),
                onTap: () {
                  setState(() {
                    _folders.removeLast();
                  });
                },
              ),
            if (_folders.length > 1) const Divider(height: 8),
            Expanded(
              child: ListView.builder(
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

                  final movingTime = (workout['moving_time'] is int)
                      ? workout['moving_time'] as int
                      : int.tryParse('${workout['moving_time'] ?? ''}') ?? 0;
                  final load = (workout['icu_training_load'] is num)
                      ? (workout['icu_training_load'] as num).toInt()
                      : int.tryParse('${workout['icu_training_load'] ?? ''}') ??
                            0;
                  final intensity = (workout['icu_intensity'] is num)
                      ? (workout['icu_intensity'] as num).toDouble()
                      : double.tryParse('${workout['icu_intensity'] ?? ''}') ??
                            0.0;

                  final subtitleParts = <String>[];
                  if (movingTime > 0)
                    subtitleParts.add(formatDuration(movingTime));
                  if (load > 0) subtitleParts.add('TL $load');
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
            ),
          ],
        ),
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
