import 'dart:convert';
import 'package:flutter/material.dart';
import 'workout_dialog.dart';
import 'workout_sort.dart';
import '../utils/workout/workout_training_load.dart';
import 'workout_scroll_hint.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../utils/workout/workout_storage.dart';
import '../utils/workout/workout_parser.dart';

class WorkoutLibrary extends StatefulWidget {
  final bool selectionMode; // true for selection, false for deletion
  final void Function(String name, String content, bool isInProgress)?
  onWorkoutSelected;
  final void Function(String name, String content)? onWorkoutReset;
  final Function(String name)? onWorkoutDeleted;
  final List<Widget> headerWidgets;
  final VoidCallback? onClose;

  const WorkoutLibrary({
    Key? key,
    required this.selectionMode,
    this.onWorkoutSelected,
    this.onWorkoutReset,
    this.onWorkoutDeleted,
    this.headerWidgets = const [],
    this.onClose,
  }) : super(key: key);

  static Future<List<AssetWorkout>> loadAssetWorkouts() async {
    try {
      Iterable<String> assets = const <String>[];
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        assets = manifest.listAssets();
      } catch (_) {
        final manifestContent = await rootBundle.loadString(
          'AssetManifest.json',
        );
        final Map<String, dynamic> manifest =
            jsonDecode(manifestContent) as Map<String, dynamic>;
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
    final name = fileName.replaceAll(
      RegExp(r'\.zwo$', caseSensitive: false),
      '',
    );
    return name.replaceAll('_', ' ');
  }

  static Future<void> showAssetWorkoutsDialog(
    BuildContext context, {
    required void Function(String name, String content) onSelected,
  }) async {
    final assets = await loadAssetWorkouts();
    if (!context.mounted) return;
    if (assets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bundled workouts found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final entries = Future.wait(
      assets.map((asset) async {
        final content = await rootBundle.loadString(asset.path);
        return _LibraryWorkout(asset.name, content);
      }),
    );
    var sort = WorkoutSort.original;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, update) => WorkoutDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Workout Library')),
              WorkoutSortButton(
                value: sort,
                onChanged: (value) => update(() => sort = value),
              ),
            ],
          ),
          icon: Icons.folder_open_rounded,
          listBody: true,
          content: FutureBuilder<List<_LibraryWorkout>>(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Could not load the workout library.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final workouts = sort.apply(
                snapshot.data!,
                (entry) => entry.metrics,
              );
              return ListView.builder(
                itemCount: workouts.length,
                itemBuilder: (context, index) {
                  final workout = workouts[index];
                  return WorkoutOptionTile(
                    key: ValueKey(workout.name),
                    leading: _buildWorkoutThumbnail(
                      name: workout.name,
                      content: workout.content,
                    ),
                    title: Text(workout.name),
                    subtitle: workout.summary,
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(workout.name, workout.content);
                    },
                  );
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CLOSE'),
            ),
          ],
        ),
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

Widget _buildWorkoutThumbnail({required String name, required String content}) {
  return FutureBuilder<String?>(
    future: WorkoutStorage.getOrGenerateWorkoutThumbnail(
      workoutName: name,
      workoutContent: content,
    ),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Container(
          width: 100,
          height: 60,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        );
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

class _LibraryWorkout {
  _LibraryWorkout(this.name, this.content);
  final String name;
  final String content;
  late final metrics = WorkoutPlanMetrics.fromZwo(content);

  Text? get summary {
    final label = metrics.summary;
    return label == null ? null : Text(label);
  }
}

class _WorkoutLibraryState extends State<WorkoutLibrary> {
  late Future<List<_LibraryWorkout>> _workoutsFuture;
  WorkoutSort _sort = WorkoutSort.original;

  final Set<String> _selectedWorkouts = {};
  String? _inProgressWorkoutName;

  Future<List<_LibraryWorkout>> _loadWorkouts() async => [
    for (final row in await WorkoutStorage.getSavedWorkouts())
      _LibraryWorkout(
        row['name'] as String? ?? '',
        row['content'] as String? ?? '',
      ),
  ];

  @override
  void initState() {
    super.initState();
    _workoutsFuture = _loadWorkouts();
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
      _workoutsFuture = _loadWorkouts();
      _selectedWorkouts.clear();
    });
  }

  Future<void> _deleteSelected(List<_LibraryWorkout> workouts) async {
    if (_selectedWorkouts.isEmpty) return;

    for (final workout in workouts) {
      final name = workout.name;
      if (_selectedWorkouts.contains(name) &&
          name != WorkoutStorage.defaultWorkoutName) {
        await WorkoutStorage.deleteWorkout(name);
        widget.onWorkoutDeleted?.call(name);
      }
    }

    _refreshWorkouts();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_LibraryWorkout>>(
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

        final workouts = _sort.apply(snapshot.data!, (entry) => entry.metrics);
        final selectableWorkouts = workouts.where((workout) {
          final name = workout.name;
          return name != WorkoutStorage.defaultWorkoutName &&
              name != _inProgressWorkoutName;
        }).toList();
        final totalSelectable = selectableWorkouts.length;
        final selectedCount = _selectedWorkouts.length;
        final allSelected =
            totalSelectable > 0 && selectedCount == totalSelectable;

        return Column(
          children: [
            Expanded(
              child: WorkoutScrollHint(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: widget.headerWidgets.length + 1 + workouts.length,
                  itemBuilder: (context, index) {
                    if (index < widget.headerWidgets.length) {
                      return widget.headerWidgets[index];
                    }

                    if (index == widget.headerWidgets.length) {
                      return Row(
                        children: [
                          const Expanded(child: Text('Imported workouts')),
                          WorkoutSortButton(
                            value: _sort,
                            onChanged: (value) => setState(() => _sort = value),
                          ),
                        ],
                      );
                    }
                    final workoutIndex =
                        index - widget.headerWidgets.length - 1;
                    final workout = workouts[workoutIndex];
                    final name = workout.name;
                    final isInProgress = name == _inProgressWorkoutName;
                    final isSelectable =
                        name != WorkoutStorage.defaultWorkoutName &&
                        !isInProgress;
                    final isSelected = _selectedWorkouts.contains(name);
                    return _WorkoutTile(
                      key: ObjectKey(workout),
                      name: name,
                      content: workout.content,
                      summary: workout.summary,
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
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
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
                                      .map((workout) => workout.name)
                                      .where((name) => name.isNotEmpty),
                                );
                              }
                            });
                          },
                  ),
                  const Text('Select All'),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: selectedCount == 0
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => WorkoutDialog(
                                title: const Text('Delete Workouts'),
                                content: Text(
                                  'Delete $selectedCount selected workouts?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('CANCEL'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
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

                  if (widget.onClose != null)
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('CLOSE'),
                    ),
                ],
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
  final Text? summary;
  final bool selectionMode;
  final void Function(String name, String content, bool isInProgress)?
  onSelected;
  final void Function(String name, String content)? onReset;
  final bool isSelected;
  final bool canSelect;
  final bool isInProgress;
  final ValueChanged<bool> onSelectionChanged;

  const _WorkoutTile({
    super.key,
    required this.name,
    required this.content,
    required this.summary,
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
    return WorkoutOptionTile(
      leading: _buildWorkoutThumbnail(name: name, content: content),
      trailing: canSelect
          ? Checkbox(
              value: isSelected,
              onChanged: (value) => onSelectionChanged(value == true),
            )
          : null,
      title: Text(isInProgress ? '$name (In Progress)' : name),
      subtitle: summary,
      onTap: selectionMode
          ? () => onSelected?.call(name, content, isInProgress)
          : null,
    );
  }
}
