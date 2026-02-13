import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../utils/workout/workout_storage.dart';
import '../utils/workout/workout_constants.dart';
import '../utils/workout/workout_parser.dart';

class WorkoutLibrary extends StatefulWidget {
  final bool selectionMode; // true for selection, false for deletion
  final void Function(String name, String content, bool isInProgress)? onWorkoutSelected;
  final void Function(String name, String content)? onWorkoutReset;
  final Function(String name)? onWorkoutDeleted;

  const WorkoutLibrary({
    Key? key,
    required this.selectionMode,
    this.onWorkoutSelected,
    this.onWorkoutReset,
    this.onWorkoutDeleted,
  }) : super(key: key);

  static Future<List<AssetWorkout>> loadAssetWorkouts() async {
    try {
      Iterable<String> assets = const <String>[];
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        assets = manifest.listAssets();
      } catch (_) {
        final manifestContent = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
        assets = manifest.keys;
      }

      final filtered = assets
          .where((key) => key.startsWith('assets/workout_library/'))
          .where((key) => key.toLowerCase().endsWith('.zwo'))
          .toList();

      filtered.sort();
      return filtered
          .map((path) => AssetWorkout(path: path, name: _titleFromPath(path)))
          .toList();
    } catch (_) {
      return <AssetWorkout>[];
    }
  }

  static String _titleFromPath(String path) {
    final fileName = path.split('/').last;
    final name = fileName.replaceAll(RegExp(r'\.zwo$', caseSensitive: false), '');
    return name.replaceAll('_', ' ');
  }

  static Future<void> showAssetWorkoutsDialog(
    BuildContext context, {
    required void Function(String name, String content) onSelected,
  }) async {
    final assets = await loadAssetWorkouts();
    if (assets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bundled workouts found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workout Library'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: assets.length,
            itemBuilder: (context, index) {
              final workout = assets[index];
              return FutureBuilder<String>(
                future: rootBundle.loadString(workout.path),
                builder: (context, contentSnapshot) {
                  final content = contentSnapshot.data;
                  final summary = _buildWorkoutSummaryText(content);
                  return ListTile(
                    leading: _buildWorkoutThumbnail(name: workout.name, content: content),
                    title: Text(workout.name),
                    subtitle: summary,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final workoutContent = content ?? await rootBundle.loadString(workout.path);
                      onSelected(workout.name, workoutContent);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
      ),
    );
  }

  @override
  State<WorkoutLibrary> createState() => _WorkoutLibraryState();
}

class AssetWorkout {
  final String path;
  final String name;

  const AssetWorkout({required this.path, required this.name});
}

Widget _buildWorkoutThumbnail({
  required String name,
  required String? content,
}) {
  if (content == null) {
    return _workoutThumbnailPlaceholder();
  }

  return FutureBuilder<String?>(
    future: WorkoutStorage.getOrGenerateWorkoutThumbnail(
      workoutName: name,
      workoutContent: content,
    ),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return _workoutThumbnailPlaceholder();
      }
      return Image.memory(
        base64Decode(snapshot.data!),
        width: 100,
        height: 60,
        fit: BoxFit.cover,
      );
    },
  );
}

Widget _workoutThumbnailPlaceholder() {
  return Container(
    width: 100,
    height: 60,
    color: Colors.grey[300],
  );
}

Text? _buildWorkoutSummaryText(String? content) {
  if (content == null) {
    return null;
  }

  final summary = WorkoutStorage.buildWorkoutSummary(content);
  if (summary == null) {
    return null;
  }

  return Text(summary);
}

class _WorkoutLibraryState extends State<WorkoutLibrary> {
  Future<List<Map<String, dynamic>>>? _workoutsFuture;
  final Set<String> _selectedWorkouts = {};
  String? _inProgressWorkoutName;

  @override
  void initState() {
    super.initState();
    _workoutsFuture = WorkoutStorage.getSavedWorkouts();
    _loadInProgressWorkoutName();
  }

  Future<void> _loadInProgressWorkoutName() async {
    final savedState = await WorkoutStorage.loadWorkoutState();
    final workoutContent = savedState['workoutContent'] as String?;
    final progressTime = savedState['workoutProgressTime'];
    if (workoutContent == null || progressTime is! num || progressTime <= 0) {
      return;
    }

    try {
      final workoutData = WorkoutParser.parseZwoFile(workoutContent);
      final name = workoutData.name?.trim();
      if (name != null && name.isNotEmpty && mounted) {
        setState(() {
          _inProgressWorkoutName = name;
        });
      }
    } catch (_) {
      // Ignore parse failures; just don't tag.
    }
  }

  void _refreshWorkouts() {
    setState(() {
      _workoutsFuture = WorkoutStorage.getSavedWorkouts();
      _selectedWorkouts.clear();
    });
  }

  Future<void> _deleteSelected(List<Map<String, dynamic>> workouts) async {
    if (_selectedWorkouts.isEmpty) return;

    for (final workout in workouts) {
      final name = workout['name'] as String?;
      if (name == null) continue;
      if (_selectedWorkouts.contains(name) && name != WorkoutStorage.defaultWorkoutName) {
        await WorkoutStorage.deleteWorkout(name);
        widget.onWorkoutDeleted?.call(name);
      }
    }

    _refreshWorkouts();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _workoutsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'No workouts found',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }

        final workouts = snapshot.data!;
        final selectableWorkouts = workouts
            .where((workout) {
              final name = workout['name'];
              return name != WorkoutStorage.defaultWorkoutName && name != _inProgressWorkoutName;
            })
            .toList();
        final totalSelectable = selectableWorkouts.length;
        final selectedCount = _selectedWorkouts.length;
        final allSelected = totalSelectable > 0 && selectedCount == totalSelectable;

        return Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: totalSelectable == 0
                      ? null
                      : (value) {
                          setState(() {
                            _selectedWorkouts.clear();
                            if (value == true) {
                              _selectedWorkouts.addAll(
                                selectableWorkouts
                                    .map((workout) => workout['name'] as String)
                                    .where((name) => name.isNotEmpty),
                              );
                            }
                          });
                        },
                ),
                const Text('Select All'),
                const Spacer(),
                TextButton.icon(
                  onPressed: selectedCount == 0
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Workouts'),
                              content: Text('Delete $selectedCount selected workouts?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('CANCEL'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('DELETE'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            await _deleteSelected(workouts);
                          }
                        },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('DELETE'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(WorkoutPadding.standard),
                itemCount: workouts.length,
                itemBuilder: (context, index) {
                  final workout = workouts[index];
                  final name = workout['name'] as String? ?? '';
                  final isInProgress = name == _inProgressWorkoutName;
                  final isSelectable =
                      name != WorkoutStorage.defaultWorkoutName && !isInProgress;
                  final isSelected = _selectedWorkouts.contains(name);
                  return _WorkoutTile(
                    name: name,
                    content: workout['content'],
                    selectionMode: widget.selectionMode,
                    isSelected: isSelected,
                    canSelect: isSelectable,
                    isInProgress: isInProgress,
                    onSelected: widget.onWorkoutSelected,
                    onReset: widget.onWorkoutReset,
                    onSelectionChanged: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedWorkouts.add(name);
                        } else {
                          _selectedWorkouts.remove(name);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  final String name;
  final String content;
  final bool selectionMode;
  final void Function(String name, String content, bool isInProgress)? onSelected;
  final void Function(String name, String content)? onReset;
  final bool isSelected;
  final bool canSelect;
  final bool isInProgress;
  final ValueChanged<bool> onSelectionChanged;

  const _WorkoutTile({
    required this.name,
    required this.content,
    required this.selectionMode,
    this.onSelected,
    this.onReset,
    required this.isSelected,
    required this.canSelect,
    required this.isInProgress,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final summary = _buildWorkoutSummaryText(content);

    return Card(
      margin: EdgeInsets.only(bottom: WorkoutPadding.standard),
      child: InkWell(
        onTap: selectionMode ? () => onSelected?.call(name, content, isInProgress) : null,
        child: Padding(
          padding: EdgeInsets.all(WorkoutPadding.standard),
          child: Row(
            children: [
              if (canSelect)
                Checkbox(
                  value: isSelected,
                  onChanged: (value) => onSelectionChanged(value == true),
                ),
              // Thumbnail
              _buildWorkoutThumbnail(name: name, content: content),
              SizedBox(width: WorkoutSpacing.medium),
              // Workout name and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isInProgress)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'In Progress',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: WorkoutSpacing.xsmall),
                    if (summary != null)
                      DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        child: summary,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
