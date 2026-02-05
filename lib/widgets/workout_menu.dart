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
    return PopupMenuButton<_MenuAction>(
      onSelected: (value) => _handleAction(context, value),
      itemBuilder: (context) => [
        _item(_MenuAction.importZwo, Icons.file_upload, 'Import ZWO'),
        _item(
          _MenuAction.intervals,
          Icons.hub,
          'Intervals.icu',
          trailing: const Icon(Icons.chevron_right, size: 18),
        ),
        const PopupMenuDivider(),
        _item(_MenuAction.selectWorkout, Icons.folder_open, 'Select Workout'),
        _item(_MenuAction.deleteWorkout, Icons.delete, 'Delete Workout'),
        const PopupMenuDivider(),
        _item(_MenuAction.audioCoach, Icons.record_voice_over, 'Audio Coach'),
        _item(_MenuAction.connectedAccounts, Icons.link, 'Connected Accounts'),
        _item(_MenuAction.calibrate, Icons.tune, 'Calibrate Trainer'),
        _item(_MenuAction.completedActivities, Icons.history, 'Completed Activities'),
        _item(_MenuAction.workoutText, Icons.text_fields, 'Workout Text'),
      ],
    );
  }

  PopupMenuItem<_MenuAction> _item(_MenuAction action, IconData icon, String label, {Widget? trailing}) {
    return PopupMenuItem<_MenuAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon),
            const SizedBox(width: 8),
          Expanded(child: Text(label)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, _MenuAction action) {
    switch (action) {
      case _MenuAction.importZwo:
        _importZwo(context);
        break;
      case _MenuAction.intervals:
        _showIntervalsSubDialog(context);
        break;
      case _MenuAction.selectWorkout:
        _showWorkoutLibrary(context, selectionMode: true);
        break;
      case _MenuAction.deleteWorkout:
        _showWorkoutLibrary(context, selectionMode: false);
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
        CompletedActivities.showCompletedActivitiesDialog(context);
        break;
      case _MenuAction.workoutText:
        _showWorkoutTextSettingsDialog(context);
        break;
    }
  }

  void _showIntervalsSubDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Intervals.icu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text("Today's Workout"),
              subtitle: const Text('Load planned workout for today'),
              onTap: () {
                Navigator.of(ctx).pop();
                _loadTodaysWorkoutFromIntervals(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Pick Workout'),
              subtitle: const Text('Browse folders & workouts'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickWorkoutFromIntervals(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
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

      final workoutDoc = todaysWorkout['workout_doc'];
      if (workoutDoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Today\'s workout does not contain structured data'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final Map<String, dynamic> docToConvert = (workoutDoc is Map)
          ? Map<String, dynamic>.from(workoutDoc)
          : <String, dynamic>{};
      docToConvert['name'] ??= todaysWorkout['name'];

      final workoutContent = IntervalsWorkoutConverter.convertToZwo(docToConvert);
      workoutController.loadWorkout(workoutContent);
      onWorkoutLoaded(workoutContent, name: todaysWorkout['name'] ?? 'Today\'s Workout');

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

      final folders = await IntervalsService.getWorkoutFolders();
      if (folders.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Intervals.icu folders found'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Folder picker
      final selectedFolder = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Intervals.icu Folders'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: folders.length,
              itemBuilder: (ctx2, index) {
                final f = folders[index];
                final name = (f['name'] ?? 'Folder').toString();
                final count = (f['children'] is List) ? (f['children'] as List).length : 0;
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(name),
                  subtitle: Text('$count items'),
                  onTap: () => Navigator.of(ctx).pop(f),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL'))],
        ),
      );
      if (selectedFolder == null) return;

      Future<Map<String, dynamic>?> pickWorkoutFromFolder(Map<String, dynamic> folder) async {
        final children = (folder['children'] is List)
            ? List<Map<String, dynamic>>.from(
                (folder['children'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e)),
              )
            : <Map<String, dynamic>>[];
        final workouts = children.where((c) => c['workout_doc'] != null || c['workout_file'] != null).toList();
        if (workouts.isEmpty) return null;
        return showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Workouts • ${folder['name'] ?? 'Folder'}'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: workouts.length,
                itemBuilder: (ctx2, index) {
                  final w = workouts[index];
                  final name = (w['name'] ?? 'Workout').toString();
                  String formatDuration(int seconds) {
                    final h = seconds ~/ 3600;
                    final m = (seconds % 3600) ~/ 60;
                    final s = seconds % 60;
                    String two(int v) => v.toString().padLeft(2, '0');
                    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
                    return '${two(m)}:${two(s)}';
                  }
                  final movingTime = (w['moving_time'] is int)
                      ? w['moving_time'] as int
                      : int.tryParse('${w['moving_time'] ?? ''}') ?? 0;
                  final load = (w['icu_training_load'] is num)
                      ? (w['icu_training_load'] as num).toInt()
                      : int.tryParse('${w['icu_training_load'] ?? ''}') ?? 0;
                  final intensity = (w['icu_intensity'] is num)
                      ? (w['icu_intensity'] as num).toDouble()
                      : double.tryParse('${w['icu_intensity'] ?? ''}') ?? 0.0;
                  final subtitleParts = <String>[];
                  if (movingTime > 0) subtitleParts.add(formatDuration(movingTime));
                  if (load > 0) subtitleParts.add('TL $load');
                  if (intensity > 0) subtitleParts.add('IF ${intensity.toStringAsFixed(2)}');
                  final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join(' • ');
                  return ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: Text(name),
                    subtitle: subtitle != null ? Text(subtitle) : null,
                    onTap: () => Navigator.of(ctx).pop(w),
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
          ),
        );
      }

      final selectedWorkout = await pickWorkoutFromFolder(selectedFolder);
      if (selectedWorkout == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No workouts in that folder'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final workoutDoc = selectedWorkout['workout_doc'];
      final workoutFile = selectedWorkout['workout_file'];
      if (workoutDoc == null && workoutFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected item has no workout data'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Map<String, dynamic> docToConvert;
      if (workoutDoc is Map) {
        docToConvert = Map<String, dynamic>.from(workoutDoc);
        docToConvert['name'] ??= selectedWorkout['name'];
      } else {
        docToConvert = {
          'workout_file': workoutFile,
          'name': selectedWorkout['name'],
          'description': selectedWorkout['description'],
          'steps':
              (workoutDoc is Map) ? workoutDoc['steps'] : null,
        };
      }

      final zwo = IntervalsWorkoutConverter.convertToZwo(docToConvert);
      workoutController.loadWorkout(zwo);
      onWorkoutLoaded(zwo, name: (selectedWorkout['name'] ?? 'Intervals.icu Workout').toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded: ${(selectedWorkout['name'] ?? 'Intervals.icu Workout').toString()}'),
          backgroundColor: const Color(0xFF1B4F72),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking Intervals.icu workout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                selectionMode ? 'Select Workout' : 'Delete Workout',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: WorkoutSpacing.medium),
              Expanded(
                child: WorkoutLibrary(
                  selectionMode: selectionMode,
                  onWorkoutSelected: (content) async {
                    Navigator.pop(context);
                    workoutController.loadWorkout(content, isResume: false);
                    onWorkoutLoaded(content, name: workoutController.workoutName);
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
  intervals,
  selectWorkout,
  deleteWorkout,
  audioCoach,
  connectedAccounts,
  calibrate,
  completedActivities,
  workoutText,
}
