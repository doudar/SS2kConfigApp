import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/workout/fit_file_reader.dart';
import '../utils/workout/workout_controller.dart';
import '../utils/workout/workout_storage.dart';
import '../services/strava_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class CompletedActivities extends StatefulWidget {
  const CompletedActivities({
    Key? key,
    required this.workoutController,
    required this.onWorkoutLoaded,
  }) : super(key: key);

  final WorkoutController workoutController;
  final void Function(String content, {String? name}) onWorkoutLoaded;

  static void showCompletedActivitiesDialog(
    BuildContext context, {
    required WorkoutController workoutController,
    required void Function(String content, {String? name}) onWorkoutLoaded,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: CompletedActivities(
            workoutController: workoutController,
            onWorkoutLoaded: onWorkoutLoaded,
          ),
        ),
      ),
    );
  }

  @override
  State<CompletedActivities> createState() => _CompletedActivitiesState();
}

class _CompletedActivitiesState extends State<CompletedActivities> {
  static const int _initialPageSize = 4;
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<ActivitySummary> _activities = [];
  final Set<String> _selectedActivityPaths = {};
  int _fitOffset = 0;
  bool _hasMore = true;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialActivities();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMoreActivities();
    }
  }

  Future<void> _loadInitialActivities() async {
    setState(() {
      _isLoadingInitial = true;
      _isLoadingMore = false;
      _hasMore = true;
      _fitOffset = 0;
      _activities.clear();
      _selectedActivityPaths.clear();
      _loadError = null;
    });

    try {
      final page = await FitFileReader.getCompletedActivitiesPage(
        offset: 0,
        limit: _initialPageSize,
      );
      if (!mounted) return;
      setState(() {
        _activities.addAll(page.activities);
        _fitOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _isLoadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingInitial = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _loadMoreActivities() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final page = await FitFileReader.getCompletedActivitiesPage(
        offset: _fitOffset,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _activities.addAll(page.activities);
        _fitOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _refreshActivities() {
    _loadInitialActivities();
  }

  Future<void> _showActivityOptions(
    BuildContext context,
    ActivitySummary activity,
  ) async {
    if (activity.isInProgress) {
      await _promptResumeInProgress(context, activity);
      return;
    }

    final isStravaConnected = await StravaService.isAuthenticated();

    final String? exportChoice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(activity.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Date: ${DateFormat('MMM d, y HH:mm').format(activity.timestamp)}',
              ),
              Text(
                'Duration: ${activity.duration.toString().split('.').first}',
              ),
              Text('Average Power: ${activity.averagePower}W'),
              Text('Average Cadence: ${activity.averageCadence}rpm'),
              Text(
                activity.averageHeartRate != null
                    ? 'Average Heart Rate: ${activity.averageHeartRate}bpm'
                    : 'Average Heart Rate: N/A',
              ),
              const SizedBox(height: 16),
              const Text('Export Options:'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('CANCEL'),
              onPressed: () => Navigator.of(context).pop('cancel'),
            ),
            if (isStravaConnected)
              TextButton(
                child: const Text('UPLOAD TO STRAVA'),
                onPressed: () => Navigator.of(context).pop('strava'),
              ),
            TextButton(
              child: const Text('SHARE'),
              onPressed: () => Navigator.of(context).pop('share'),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;

    if (exportChoice == 'share') {
      try {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(activity.filePath)]),
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to share file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (exportChoice == 'strava') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uploading to Strava...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final success = await StravaService.uploadActivity(
        activity.filePath,
        activity.name,
        'Workout completed using SmartSpin2k',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Successfully uploaded to Strava'
                  : 'Failed to upload to Strava',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _promptResumeInProgress(
    BuildContext context,
    ActivitySummary activity,
  ) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activity.name),
        content: const Text('Resume this in-progress workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESUME'),
          ),
        ],
      ),
    );

    if (choice != true || !context.mounted) {
      return;
    }

    final savedInProgressPath = await WorkoutStorage.loadInProgressFilePath();
    if (savedInProgressPath == null ||
        savedInProgressPath != activity.filePath) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching in-progress workout state found.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final savedState = await WorkoutStorage.loadWorkoutState();
    final workoutContent = savedState['workoutContent'] as String?;
    if (workoutContent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load workout content for resume.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final restored = await widget.workoutController.restoreSavedWorkoutState();
    if (!restored) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to restore workout state.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      Navigator.pop(context);
    }
    widget.onWorkoutLoaded(
      workoutContent,
      name: widget.workoutController.workoutName,
    );
  }

  Future<void> _deleteSelectedActivities(
    List<ActivitySummary> activities,
  ) async {
    final toDelete = activities
        .where((activity) => _selectedActivityPaths.contains(activity.filePath))
        .toList();

    if (toDelete.isEmpty) {
      return;
    }

    for (final activity in toDelete) {
      final file = File(activity.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      await FitFileReader.deleteActivityMetadata(activity.filePath);
      await FitFileReader.deleteWorkoutThumbnail(activity.filePath);
      if (activity.isInProgress) {
        final inProgressPath = await WorkoutStorage.loadInProgressFilePath();
        if (inProgressPath == activity.filePath) {
          await WorkoutStorage.clearWorkoutState();
        }
      }
    }

    _refreshActivities();
  }

  Widget _buildThumbnail(ActivitySummary activity) {
    if (activity.isInProgress) {
      return _thumbnailPlaceholder();
    }

    return FutureBuilder<File?>(
      future: FitFileReader.getOrGenerateWorkoutThumbnail(activity.filePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _thumbnailPlaceholder(isLoading: true);
        }

        final file = snapshot.data;
        if (file == null) {
          return _thumbnailPlaceholder();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 120, height: 70, fit: BoxFit.cover),
        );
      },
    );
  }

  Widget _thumbnailPlaceholder({bool isLoading = false}) {
    return Container(
      width: 120,
      height: 70,
      decoration: BoxDecoration(
        color: isLoading ? Colors.grey.shade300 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.fitness_center, color: Colors.grey.shade600, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Completed Activities',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoadingInitial
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Center(child: Text('Error: $_loadError'))
              : _activities.isEmpty
              ? const Center(child: Text('No completed activities found'))
              : Builder(
                  builder: (context) {
                    final activities = _activities;
                    final totalSelectable = activities.length;
                    final selectedCount = _selectedActivityPaths.length;
                    final allSelected =
                        totalSelectable > 0 && selectedCount == totalSelectable;

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
                                        _selectedActivityPaths.clear();
                                        if (value == true) {
                                          _selectedActivityPaths.addAll(
                                            activities.map(
                                              (activity) => activity.filePath,
                                            ),
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
                                        await _deleteSelectedActivities(
                                          activities,
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.delete, color: Colors.red),
                              label: const Text('DELETE'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount:
                                activities.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= activities.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final activity = activities[index];
                              final isSelected = _selectedActivityPaths
                                  .contains(activity.filePath);

                              return ListTile(
                                leading: Checkbox(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedActivityPaths.add(
                                          activity.filePath,
                                        );
                                      } else {
                                        _selectedActivityPaths.remove(
                                          activity.filePath,
                                        );
                                      }
                                    });
                                  },
                                ),
                                title: Row(
                                  children: [
                                    _buildThumbnail(activity),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        activity.isInProgress
                                            ? '${activity.name} (In Progress)'
                                            : activity.name,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat(
                                        'MMM d, y HH:mm',
                                      ).format(activity.timestamp),
                                    ),
                                    if (activity.isInProgress)
                                      const Text('Status: In Progress'),
                                    Text(
                                      'Duration: ${activity.duration.toString().split('.').first} • '
                                      'Power: ${activity.averagePower}W • '
                                      'Cadence: ${activity.averageCadence}rpm'
                                      '${activity.averageHeartRate != null ? ' • HR: ${activity.averageHeartRate}bpm' : ''}',
                                    ),
                                  ],
                                ),
                                onTap: () =>
                                    _showActivityOptions(context, activity),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}
