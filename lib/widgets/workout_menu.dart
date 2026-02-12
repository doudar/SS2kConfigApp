import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/intervals_service.dart';
import '../services/intervals_workout_converter.dart';
import '../utils/workout/workout_controller.dart';
import '../utils/workout/workout_constants.dart';
import '../utils/workout/workout_storage.dart';
import '../utils/workout/workout_file_manager.dart';
import '../utils/workout/workout_tts_settings.dart';
import '../utils/workout/workout_text_event_overlay.dart';
import '../utils/workout/workout_parser.dart';
import '../utils/workout/workout_painter.dart';
import '../utils/bledata.dart';
import '../utils/ftmsControlPoint.dart';
import '../utils/workout/workout_connected_accounts.dart';
import 'workout_library.dart';
import 'audio_coach_dialog.dart';
import 'completed_activities.dart';

/// Unified Workout Menu (Refactored)
/// ---------------------------------
/// This widget now encapsulates the implementation of menu actions so the
/// hosting screen (`WorkoutScreen`) only supplies dependencies and reacts
/// to workout load events via a single callback.
class WorkoutMenu extends StatelessWidget {
  static List<Map<String, dynamic>>? _intervalsFoldersCache;

  const WorkoutMenu({
    super.key,
    required this.workoutController,
    required this.bleData,
    required this.ttsSettings,
    required this.workoutGraphKey,
    required this.onWorkoutLoaded,
  });

  final WorkoutController workoutController;
  final BLEData bleData;
  final WorkoutTTSSettings ttsSettings;
  final GlobalKey workoutGraphKey;
  final void Function(String content, {String? name}) onWorkoutLoaded;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Workout Menu',
      onPressed: () => _showMenuDialog(context),
    );
  }

  Future<void> _showAssetWorkoutFolder(BuildContext context) async {
    await WorkoutLibrary.showAssetWorkoutsDialog(
      context,
      onSelected: (name, content) {
        workoutController.loadWorkout(content, isResume: false);
        onWorkoutLoaded(content, name: name);
      },
    );
  }

  Future<void> _showMenuDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SizedBox(
              height: 420,
              child: Column(
                children: [
                  Container(
                    color: Theme.of(context).colorScheme.surfaceDim,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Workout Menu',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      children: [
                        _menuTile(dialogContext, context, _MenuAction.importZwo, Icons.file_upload, 'Import ZWO'),
                        const Divider(),
                        _menuTile(dialogContext, context, _MenuAction.selectWorkout, Icons.folder_open, 'Workout Library'),
                        _menuTile(dialogContext, context, _MenuAction.completedActivities, Icons.history, 'Completed Activities'),
                        const Divider(),
                        _menuTile(dialogContext, context, _MenuAction.connectedAccounts, Icons.link, 'Connected Accounts'),
                        _menuTile(dialogContext, context, _MenuAction.calibrate, Icons.tune, 'Calibrate Trainer'),
                        _menuTile(dialogContext, context, _MenuAction.workoutText, Icons.text_fields, 'Workout Text'),
                        _menuTile(dialogContext, context, _MenuAction.audioCoach, Icons.record_voice_over, 'Audio Coach'),
                      ],
                    ),
                  ),
                  Container(
                    color: Theme.of(context).colorScheme.surfaceDim,
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('CLOSE'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile(
    BuildContext dialogContext,
    BuildContext parentContext,
    _MenuAction action,
    IconData icon,
    String label, {
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: trailing,
      onTap: () {
        Navigator.of(dialogContext).pop();
        _handleAction(parentContext, action);
      },
    );
  }

  void _handleAction(BuildContext context, _MenuAction action) {
    switch (action) {
      case _MenuAction.importZwo:
        _importZwo(context);
        break;
      case _MenuAction.selectWorkout:
        _showWorkoutLibrary(context, selectionMode: true);
        break;
      case _MenuAction.audioCoach:
        _showAudioCoachDialog(context);
        break;
      case _MenuAction.connectedAccounts:
        WorkoutConnectedAccounts.showConnectedAccountsDialog(context);
        break;
      case _MenuAction.calibrate:
        _showCalibrationDialog(context);
        break;
      case _MenuAction.completedActivities:
        CompletedActivities.showCompletedActivitiesDialog(
          context,
          workoutController: workoutController,
          onWorkoutLoaded: onWorkoutLoaded,
        );
        break;
      case _MenuAction.workoutText:
        _showWorkoutTextSettingsDialog(context);
        break;
    }
  }

  void _runAfterDialogClose(BuildContext dialogContext, VoidCallback action) {
    Navigator.pop(dialogContext);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action();
    });
  }


  // ====== Internal Action Implementations ======
  Future<void> _importZwo(BuildContext context) async {
    await WorkoutFileManager.pickAndLoadWorkout(
      context: context,
      workoutController: workoutController,
      workoutGraphKey: workoutGraphKey,
      onWorkoutLoaded: (content) {
        onWorkoutLoaded(content, name: workoutController.workoutName);
      },
    );
  }

  Future<void> _loadTodaysWorkoutFromIntervals(BuildContext context) async {
    try {
      if (!await IntervalsService.isAuthenticated()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please connect to Intervals.icu first in Connected Accounts'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading today\'s workout from Intervals.icu...'),
          duration: Duration(seconds: 2),
        ),
      );

      final todaysWorkout = await IntervalsService.getTodaysWorkout();
      if (todaysWorkout == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No planned workout found for today on Intervals.icu'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final todaysWorkoutMap = Map<String, dynamic>.from(todaysWorkout);

      final workoutContent = _convertIntervalsWorkoutToZwo(todaysWorkoutMap);

      if (workoutContent == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Today\'s workout does not contain structured data'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await _saveIntervalsWorkoutToLibrary(todaysWorkoutMap, workoutContent);

      workoutController.loadWorkout(workoutContent);
      onWorkoutLoaded(workoutContent, name: todaysWorkoutMap['name'] ?? 'Today\'s Workout');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully loaded: ${todaysWorkout['name'] ?? 'Today\'s Workout'}'),
          backgroundColor: const Color(0xFF1B4F72),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading today\'s workout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickWorkoutFromIntervals(BuildContext context) async {
    try {
      if (!await IntervalsService.isAuthenticated()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please connect to Intervals.icu first in Connected Accounts'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogCtx) {
          List<Map<String, dynamic>> folders = _intervalsFoldersCache ?? [];
          bool isLoading = folders.isEmpty;
          String? error;
          bool started = false;

          Future<void> loadFolders(StateSetter setState) async {
            setState(() {
              isLoading = true;
              error = null;
              started = true;
            });
            try {
              final fetched = await IntervalsService.getWorkoutFolders();
              if (fetched.isNotEmpty) {
                _intervalsFoldersCache = fetched;
                folders = fetched;
              } else {
                error = 'No Intervals.icu folders found';
              }
            } catch (e) {
              error = 'Error loading folders: $e';
            } finally {
              if (dialogCtx.mounted) {
                setState(() {
                  isLoading = false;
                });
              }
            }
          }

          Future<Map<String, dynamic>?> pickWorkoutFromFolder(Map<String, dynamic> folder) async {
            return showDialog<Map<String, dynamic>>(
              context: dialogCtx,
              builder: (ctx) {
                final folderStack = <Map<String, dynamic>>[folder];

                return StatefulBuilder(
                  builder: (ctx2, setState) {
                    Map<String, dynamic> currentFolder = folderStack.last;
                    final children = (currentFolder['children'] is List)
                        ? List<Map<String, dynamic>>.from(
                            (currentFolder['children'] as List)
                                .whereType<Map>()
                                .map((e) => Map<String, dynamic>.from(e)),
                          )
                        : <Map<String, dynamic>>[];

                    final subfolders = children.where((c) => c['children'] is List).toList();
                    final workouts = children
                        .where((c) => c['workout_doc'] != null || c['workout_file'] != null)
                        .toList();

                    return AlertDialog(
                      title: Text('Workouts • ${currentFolder['name'] ?? 'Folder'}'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (folderStack.length > 1)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.arrow_back),
                                title: const Text('Go back'),
                                onTap: () {
                                  setState(() {
                                    folderStack.removeLast();
                                  });
                                },
                              ),
                            if (folderStack.length > 1) const Divider(height: 8),
                            Expanded(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: subfolders.length + workouts.length,
                                itemBuilder: (context, index) {
                                  if (index < subfolders.length) {
                                    final folder = subfolders[index];
                                    final name = (folder['name'] ?? 'Folder').toString();
                                    return ListTile(
                                      leading: const Icon(Icons.folder),
                                      title: Text(name),
                                      trailing: const Icon(Icons.chevron_right, size: 18),
                                      onTap: () {
                                        setState(() {
                                          folderStack.add(folder);
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
                                      : int.tryParse('${workout['icu_training_load'] ?? ''}') ?? 0;
                                  final intensity = (workout['icu_intensity'] is num)
                                      ? (workout['icu_intensity'] as num).toDouble()
                                      : double.tryParse('${workout['icu_intensity'] ?? ''}') ?? 0.0;

                                  final subtitleParts = <String>[];
                                  if (movingTime > 0) subtitleParts.add(formatDuration(movingTime));
                                  if (load > 0) subtitleParts.add('TL $load');
                                  if (intensity > 0) subtitleParts.add('IF ${intensity.toStringAsFixed(2)}');
                                  final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join(' • ');

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    minLeadingWidth: 130,
                                    leading: _buildIntervalsThumbnail(context, workout),
                                    title: Text(name),
                                    subtitle: subtitle != null ? Text(subtitle) : null,
                                    onTap: () => Navigator.of(ctx2).pop(workout),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('BACK'))],
                    );
                  },
                );
              },
            );
          }

          return StatefulBuilder(
            builder: (ctx, setState) {
              final hasFolders = folders.isNotEmpty;

              if (!started && folders.isEmpty) {
                started = true;
                // Start loading after first frame to avoid build-cycle setState warning
                WidgetsBinding.instance.addPostFrameCallback((_) => loadFolders(setState));
              }

              final todayTile = ListTile(
                leading: Image.asset(
                  'assets/intervals.png',
                  width: 50,
                  height: 50,
                ),
                title: const Text("Today's Intervals.icu Workout"),
                subtitle: const Text('Load planned workout for today'),
                onTap: () => _runAfterDialogClose(
                  dialogCtx,
                  () => _loadTodaysWorkoutFromIntervals(context),
                ),
              );

              Widget buildFoldersList() {
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length + 1,
                  itemBuilder: (ctx2, index) {
                    if (index == 0) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          todayTile,
                          const Divider(height: 1),
                        ],
                      );
                    }

                    final f = folders[index - 1];
                    final name = (f['name'] ?? 'Folder').toString();
                    final count = (f['children'] is List) ? (f['children'] as List).length : 0;
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(name),
                      subtitle: Text('$count items'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () async {
                        final rootFolder = {
                          'name': name,
                          'children': f['children'] ?? [],
                        };
                        final selectedWorkout = await pickWorkoutFromFolder(rootFolder);
                        if (selectedWorkout != null && dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop(selectedWorkout);
                        }
                      },
                    );
                  },
                );
              }

              Widget buildLoadingList() {
                return ListView(
                  shrinkWrap: true,
                  children: [
                    todayTile,
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                );
              }

              Widget buildEmptyList() {
                return ListView(
                  shrinkWrap: true,
                  children: [
                    todayTile,
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(child: Text(error ?? 'No Intervals.icu folders found')),
                    ),
                  ],
                );
              }

              return AlertDialog(
                title: Row(
                  children: [
                    const Text('Intervals.icu'),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                      onPressed: isLoading ? null : () => loadFolders(setState),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: isLoading && !hasFolders
                      ? buildLoadingList()
                      : hasFolders
                          ? buildFoldersList()
                          : buildEmptyList(),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('CLOSE'))],
              );
            },
          );
        },
      ).then((selectedWorkout) async {
        if (selectedWorkout == null) return;

        final zwoContent = _convertIntervalsWorkoutToZwo(
          Map<String, dynamic>.from(selectedWorkout),
        );

        if (zwoContent == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected item has no workout data'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        await _saveIntervalsWorkoutToLibrary(
          Map<String, dynamic>.from(selectedWorkout),
          zwoContent,
        );
        workoutController.loadWorkout(zwoContent);
        onWorkoutLoaded(zwoContent, name: (selectedWorkout['name'] ?? 'Intervals.icu Workout').toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded: ${(selectedWorkout['name'] ?? 'Intervals.icu Workout').toString()}'),
            backgroundColor: const Color(0xFF1B4F72),
          ),
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking Intervals.icu workout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveIntervalsWorkoutToLibrary(
    Map<String, dynamic> workout,
    String zwoContent,
  ) async {
    final workoutName = (workout['name'] ?? 'Intervals.icu Workout').toString();
    final thumb = await _getOrGenerateIntervalsThumb(workout);
    final thumbnailData = thumb ?? base64Encode(utf8.encode('placeholder'));
    await WorkoutStorage.saveOrUpdateWorkoutToLibrary(
      workoutContent: zwoContent,
      workoutName: workoutName,
      thumbnailData: thumbnailData,
    );
  }

  Widget _buildIntervalsThumbnail(BuildContext context, Map<String, dynamic> workout) {
    return FutureBuilder<String?>(
      future: _getOrGenerateIntervalsThumb(workout),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _intervalsThumbnailPlaceholder(context, isLoading: true);
        }
        final data = snapshot.data;
        if (data == null) {
          return _intervalsThumbnailPlaceholder(context);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(data),
            width: 120,
            height: 70,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  Widget _intervalsThumbnailPlaceholder(BuildContext context, {bool isLoading = false}) {
    final base = Container(
      width: 120,
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.fitness_center,
        color: Theme.of(context).colorScheme.outline,
        size: 20,
      ),
    );

    if (!isLoading) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: base);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.linear,
        builder: (context, value, child) {
          final shimmerColors = [
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ];

          return ShaderMask(
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment(-1 - value, 0),
                end: Alignment(1 + value, 0),
                colors: shimmerColors,
                stops: const [0.1, 0.5, 0.9],
              ).createShader(rect);
            },
            blendMode: BlendMode.srcATop,
            child: base,
          );
        },
        onEnd: () {},
      ),
    );
  }

  String? _convertIntervalsWorkoutToZwo(Map<String, dynamic> workout) {
    final workoutDoc = workout['workout_doc'];
    final workoutFile = workout['workout_file'];

    if (workoutDoc == null && workoutFile == null) {
      return null;
    }

    try {
      Map<String, dynamic> docToConvert;
      if (workoutDoc is Map) {
        docToConvert = Map<String, dynamic>.from(workoutDoc);
      } else {
        docToConvert = {
          'workout_file': workoutFile,
          'steps': workoutDoc is Map ? workoutDoc['steps'] : null,
        };
      }

      docToConvert['name'] ??= workout['name'];
      docToConvert['description'] ??= workout['description'];

      return IntervalsWorkoutConverter.convertToZwo(docToConvert);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getOrGenerateIntervalsThumb(Map<String, dynamic> workout) async {
    final zwoContent = _convertIntervalsWorkoutToZwo(workout);
    if (zwoContent == null) return null;

    final workoutName = (workout['name'] ?? 'Intervals.icu Workout').toString();
    return WorkoutStorage.getOrGenerateWorkoutThumbnail(
      workoutName: workoutName,
      workoutContent: zwoContent,
    );
  }

  void _showWorkoutLibrary(BuildContext context, {required bool selectionMode}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(WorkoutPadding.standard),
          child: Column(
            children: [
              Text(
                'Workout Library',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: WorkoutSpacing.medium),
              if (selectionMode)
                FutureBuilder<bool>(
                  future: IntervalsService.isAuthenticated(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: LinearProgressIndicator(),
                      );
                    }

                    final isConnected = snapshot.data == true;
                    if (!isConnected) {
                      return Card(
                        child: ListTile(
                          leading: Image.asset(
                            'assets/intervals.png',
                            width: 50,
                            height: 50,
                          ),
                          title: const Text('Connect Intervals.icu for more workouts'),
                          onTap: () => _runAfterDialogClose(
                            ctx,
                            () => WorkoutConnectedAccounts.showConnectedAccountsDialog(context),
                          ),
                        ),
                      );
                    }

                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: Image.asset(
                              'assets/intervals.png',
                              width: 50,
                              height: 50,
                            ),
                            title: const Text("Today's Intervals.icu Workout"),
                            subtitle: const Text('Load planned workout for today'),
                            onTap: () => _runAfterDialogClose(
                              ctx,
                              () => _loadTodaysWorkoutFromIntervals(context),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Image.asset(
                              'assets/intervals.png',
                              width: 50,
                              height: 50,
                            ),
                            title: const Text('Intervals.icu Library'),
                            subtitle: const Text('Browse folders & workouts'),
                            onTap: () => _runAfterDialogClose(
                              ctx,
                              () => _pickWorkoutFromIntervals(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (selectionMode)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Text(
                      'SmartSpin2k Library',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              if (selectionMode)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder),
                    title: const Text('SS2k Library'),
                    subtitle: const Text('Bundled workouts'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _runAfterDialogClose(
                      ctx,
                      () => _showAssetWorkoutFolder(context),
                    ),
                  ),
                ),
              Expanded(
                child: WorkoutLibrary(
                  selectionMode: selectionMode,
                  onWorkoutSelected: (name, content, isInProgress) async {
                    if (!isInProgress) {
                      Navigator.pop(context);
                      workoutController.loadWorkout(content, isResume: false);
                      onWorkoutLoaded(content, name: workoutController.workoutName);
                      return;
                    }

                    final action = await showDialog<String>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(name),
                        content: const Text('Resume this workout or restart from the beginning?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, 'restart'),
                            child: const Text('RESTART'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, 'resume'),
                            child: const Text('RESUME'),
                          ),
                        ],
                      ),
                    );

                    if (action == 'resume') {
                      Navigator.pop(context);
                      final restored = await workoutController.restoreSavedWorkoutState();
                      if (restored) {
                        onWorkoutLoaded(content, name: workoutController.workoutName);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Unable to resume in-progress workout.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }

                    if (action == 'restart') {
                      Navigator.pop(context);
                      await workoutController.clearInProgressFile();
                      await WorkoutStorage.clearWorkoutState();
                      workoutController.loadWorkout(content, isResume: false);
                      onWorkoutLoaded(content, name: workoutController.workoutName);
                    }
                  },
                  onWorkoutDeleted: (name) async {
                    await WorkoutStorage.deleteWorkout(name);
                  },
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
            ],
          ),
        ),
      ),
    );
  }

  void _showAudioCoachDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AudioCoachDialog(ttsSettings: ttsSettings),
    );
  }

  void _showCalibrationDialog(BuildContext context) {
    bool isCalibrating = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setState) {
          return AlertDialog(
            title: const Text('Calibration'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isCalibrating)
                  const Text('Start pedaling until the SmartSpin2k knob starts to turn.\n\nPress Start when ready.'),
                if (isCalibrating)
                  const Text('Stop pedaling and wait for the calibration to complete.\n\nThis may take a few moments...'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('CANCEL')),
              if (!isCalibrating)
                TextButton(
                  onPressed: () async {
                    setState(() => isCalibrating = true);
                    try {
                      final ftmsControlPointChar = bleData.ftmsControlPointCharacteristic;
                      if (ftmsControlPointChar != null) {
                        await FTMSControlPoint.spinDownControl(ftmsControlPointChar, true);
                        await Future.delayed(const Duration(seconds: 30));
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Calibration completed'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        throw Exception('FTMS Control Point characteristic not found');
                      }
                    } catch (e) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Calibration failed: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text('START'),
                ),
            ],
          );
        });
      },
    );
  }

  void _showWorkoutTextSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setState) {
          return AlertDialog(
            title: const Text('Workout Text Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Font Size: ${WorkoutTextStyle.scrollingText.toInt()}'),
                Slider(
                  value: WorkoutTextStyle.scrollingText,
                  min: 24,
                  max: 72,
                  divisions: 12,
                  label: WorkoutTextStyle.scrollingText.toInt().toString(),
                  onChanged: (value) {
                    setState(() => WorkoutTextStyle.scrollingText = value);
                    WorkoutTextEventOverlay.saveTextSettings(value, WorkoutTextStyle.scrollSpeed);
                  },
                ),
                const SizedBox(height: 16),
                Text('Scroll Speed: ${WorkoutTextStyle.scrollSpeed.toInt()} px/s'),
                Slider(
                  value: WorkoutTextStyle.scrollSpeed,
                  min: 50,
                  max: 300,
                  divisions: 25,
                  label: WorkoutTextStyle.scrollSpeed.toInt().toString(),
                  onChanged: (value) {
                    setState(() => WorkoutTextStyle.scrollSpeed = value);
                    WorkoutTextEventOverlay.saveTextSettings(WorkoutTextStyle.scrollingText, value);
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx3) {
                        final testSegment = WorkoutSegment(
                          type: SegmentType.steadyState,
                          duration: 60,
                          powerLow: 100,
                          powerHigh: 150,
                          textEvents: [
                            TextEvent(
                              timeOffset: 0,
                              message: 'Text Size ${WorkoutTextStyle.scrollingText.toInt()} , Speed ${WorkoutTextStyle.scrollSpeed.toInt()}',
                            ),
                          ],
                        );
                        return AlertDialog(
                          content: SizedBox(
                            width: double.maxFinite,
                            child: WorkoutTextEventOverlay(
                              currentSegment: testSegment,
                              secondsIntoSegment: 0,
                              ttsSettings: ttsSettings,
                              workoutController: workoutController,
                              testText: 'Text Size ${WorkoutTextStyle.scrollingText.toInt()} x Speed ${WorkoutTextStyle.scrollSpeed.toInt()}',
                            ),
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx3), child: const Text('CLOSE'))],
                        );
                      },
                    );
                  },
                  child: const Text('TEST SETTINGS'),
                ),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
          );
        });
      },
    );
  }
}

enum _MenuAction {
  importZwo,
  selectWorkout,
  audioCoach,
  connectedAccounts,
  calibrate,
  completedActivities,
  workoutText,
}
