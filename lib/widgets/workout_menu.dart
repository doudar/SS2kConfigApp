import 'dart:convert';
import 'package:flutter/material.dart';
import 'workout_dialog.dart';
import 'intervals_workout_folder_dialog.dart';
import 'workout_ftp_dialog.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../screens/calibration_screen.dart';
import '../services/intervals_service.dart';
import '../services/intervals_workout_converter.dart';
import '../utils/workout/workout_controller.dart';
import '../utils/workout/workout_constants.dart';
import '../utils/workout/workout_storage.dart';
import '../utils/workout/workout_file_manager.dart';
import '../utils/workout/workout_tts_settings.dart';
import '../utils/workout/workout_text_event_overlay.dart';
import '../utils/workout/workout_parser.dart';
import '../utils/device_data.dart';
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
    required this.deviceData,
    required this.device,
    required this.ttsSettings,
    required this.onWorkoutLoaded,
  });

  final WorkoutController workoutController;
  final DeviceData deviceData;
  final BluetoothDevice device;
  final WorkoutTTSSettings ttsSettings;
  final void Function(String content, {String? name}) onWorkoutLoaded;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Workout Menu',
      child: TextButton.icon(
        icon: const Icon(Icons.menu_rounded),
        label: const Text('Menu'),
        onPressed: () => show(context),
      ),
    );
  }

  Future<void> show(BuildContext context) => _showMenuDialog(context);

  Future<void> _showAssetWorkoutFolder(BuildContext context) async {
    await WorkoutLibrary.showAssetWorkoutsDialog(
      context,
      onSelected: (name, content) async {
        final shouldReplace = await _confirmWorkoutReplacement(context);
        if (!shouldReplace) {
          return;
        }
        workoutController.loadWorkout(content, isResume: false);
        onWorkoutLoaded(content, name: name);
      },
    );
  }

  Future<bool> _confirmWorkoutReplacement(BuildContext context) async {
    if (!workoutController.isPlaying && workoutController.workoutProgressSeconds == 0) return true;
    final shouldReplace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => WorkoutDialog(
        title: const Text('Switch workouts?'),
        icon: Icons.swap_horiz_rounded,
        content: const Text('Your current ride will be replaced. Save it first if you want to keep it.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep current ride')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Switch workouts')),
        ],
      ),
    );

    return shouldReplace ?? false;
  }

  Future<void> _showMenuDialog(BuildContext context, {_MenuAction? initialAction}) async {
    var openedInitialAction = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!openedInitialAction && initialAction != null) {
          openedInitialAction = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (dialogContext.mounted) _handleAction(dialogContext, initialAction);
          });
        }
        return WorkoutDialog(
          title: const Text('Ride menu'),
          icon: Icons.pedal_bike_rounded,
          subtitle: 'Your next ride, your settings, all right here.',
          showClose: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _menuTile(
                dialogContext,
                _MenuAction.selectWorkout,
                Icons.folder_open_rounded,
                'Choose a workout',
                subtitle: 'Browse your library or import a workout file',
              ),
              _menuTile(
                dialogContext,
                _MenuAction.freeRide,
                Icons.all_inclusive_rounded,
                'Just ride',
                subtitle: 'No plan. Pedal at your own pace.',
              ),
              _menuGroup(
                title: 'Ride settings',
                subtitle: 'Voice, messages and trainer',
                icon: Icons.tune_rounded,
                children: [
                  _menuTile(
                    dialogContext,
                    _MenuAction.audioCoach,
                    Icons.record_voice_over_rounded,
                    'Voice coach',
                    subtitle: 'Spoken guidance during your ride',
                  ),
                  _menuTile(
                    dialogContext,
                    _MenuAction.workoutText,
                    Icons.text_fields_rounded,
                    'On-screen messages',
                    subtitle: 'Text size and scrolling speed',
                  ),
                  _menuTile(
                    dialogContext,
                    _MenuAction.ftp,
                    Icons.bolt_rounded,
                    'Power target (FTP)',
                    subtitle: 'Set your workout intensity baseline',
                  ),
                  _menuTile(
                    dialogContext,
                    _MenuAction.calibrate,
                    Icons.build_outlined,
                    'Trainer setup',
                    subtitle: 'Calibrate your trainer when needed',
                  ),
                ],
              ),
              _menuGroup(
                title: 'My training',
                subtitle: 'Past rides and connected apps',
                icon: Icons.history_rounded,
                children: [
                  _menuTile(
                    dialogContext,
                    _MenuAction.completedActivities,
                    Icons.history_rounded,
                    'Past rides',
                    subtitle: 'Review, share or manage saved activities',
                  ),
                  _menuTile(
                    dialogContext,
                    _MenuAction.connectedAccounts,
                    Icons.link_rounded,
                    'Connected apps',
                    subtitle: 'Strava and Intervals.icu',
                  ),
                ],
              ),
            ],
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to ride'),
            ),
          ],
        );
      },
    );
  }

  Widget _menuGroup({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) => Card(
    child: ExpansionTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      tilePadding: const EdgeInsets.all(16),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      shape: const Border(),
      collapsedShape: const Border(),
      children: children,
    ),
  );

  Widget _menuTile(BuildContext context, _MenuAction action, IconData icon, String label, {String? subtitle}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: WorkoutActionTile(
          icon: icon,
          title: label,
          subtitle: subtitle,
          // Keep this hub on the navigator stack. Close, back and cancellation in
          // a child all reveal the same menu, including its expanded groups.
          onTap: () => _handleAction(context, action),
        ),
      );

  void _handleAction(BuildContext context, _MenuAction action) {
    switch (action) {
      case _MenuAction.ftp:
        _showFtpDialog(context);
        break;
      case _MenuAction.freeRide:
        _startFreeRide(context);
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

  Future<void> _showFtpDialog(BuildContext context) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => WorkoutFtpDialog(initialFtp: workoutController.ftpValue),
    );
    if (result != null && context.mounted) await workoutController.updateFTP(result);
  }

  void _runAfterDialogClose(BuildContext dialogContext, VoidCallback action) {
    Navigator.pop(dialogContext);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action();
    });
  }

  // ====== Internal Action Implementations ======
  Future<void> _startFreeRide(BuildContext context) async {
    final shouldReplace = await _confirmWorkoutReplacement(context);
    if (!shouldReplace) return;

    const freeRideZwo =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<workout_file>'
        '  <name>Free Ride</name>'
        '  <description>Open ride - ride at your own pace</description>'
        '  <workout>'
        '    <FreeRide Duration="0"/>'
        '  </workout>'
        '</workout_file>';

    workoutController.loadWorkout(freeRideZwo, isResume: false);
    onWorkoutLoaded(freeRideZwo, name: 'Free Ride');
  }

  Future<void> _importZwo(BuildContext context) async {
    await WorkoutFileManager.pickAndLoadWorkout(
      context: context,
      workoutController: workoutController,
      onBeforeLoad: () => _confirmWorkoutReplacement(context),
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
        const SnackBar(content: Text('Loading today\'s workout from Intervals.icu...'), duration: Duration(seconds: 2)),
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

      final shouldReplace = await _confirmWorkoutReplacement(context);
      if (!shouldReplace) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading today\'s workout: $e'), backgroundColor: Colors.red));
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

          Future<Map<String, dynamic>?> pickWorkoutFromFolder(Map<String, dynamic> folder) {
            return showDialog<Map<String, dynamic>>(
              context: dialogCtx,
              builder: (_) => IntervalsWorkoutFolderDialog(
                folder: folder,
                thumbnailBuilder: _buildIntervalsThumbnail,
              ),
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

              final todayTile = WorkoutOptionTile(
                leading: Image.asset('assets/intervals.png', width: 50, height: 50),
                title: const Text("Today's Intervals.icu Workout"),
                subtitle: const Text('Load planned workout for today'),
                onTap: () => _runAfterDialogClose(dialogCtx, () => _loadTodaysWorkoutFromIntervals(context)),
              );

              Widget buildFoldersList() {
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: folders.length + 1,
                  itemBuilder: (ctx2, index) {
                    if (index == 0) {
                      return Column(mainAxisSize: MainAxisSize.min, children: [todayTile, const Divider(height: 1)]);
                    }

                    final f = folders[index - 1];
                    final name = (f['name'] ?? 'Folder').toString();
                    final count = (f['children'] is List) ? (f['children'] as List).length : 0;
                    return WorkoutOptionTile(
                      leading: const Icon(Icons.folder),
                      title: Text(name),
                      subtitle: Text('$count items'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () async {
                        final rootFolder = {'name': name, 'children': f['children'] ?? []};
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

              return WorkoutDialog(
                listBody: true,
                icon: Icons.folder_open_rounded,
                title: Row(
                  children: [
                    const Expanded(child: Text('Intervals.icu')),
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

        final zwoContent = _convertIntervalsWorkoutToZwo(Map<String, dynamic>.from(selectedWorkout));

        if (zwoContent == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected item has no workout data'), backgroundColor: Colors.red),
          );
          return;
        }

        final shouldReplace = await _confirmWorkoutReplacement(context);
        if (!shouldReplace) {
          return;
        }

        await _saveIntervalsWorkoutToLibrary(Map<String, dynamic>.from(selectedWorkout), zwoContent);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking Intervals.icu workout: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveIntervalsWorkoutToLibrary(Map<String, dynamic> workout, String zwoContent) async {
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
          child: Image.memory(base64Decode(data), width: 120, height: 70, fit: BoxFit.cover),
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
      child: Icon(Icons.fitness_center, color: Theme.of(context).colorScheme.outline, size: 20),
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

  String? _convertIntervalsWorkoutToZwo(Map<String, dynamic> workout) =>
      IntervalsWorkoutConverter.convertEventToZwo(workout);

  Future<String?> _getOrGenerateIntervalsThumb(Map<String, dynamic> workout) async {
    final zwoContent = _convertIntervalsWorkoutToZwo(workout);
    if (zwoContent == null) return null;

    final workoutName = (workout['name'] ?? 'Intervals.icu Workout').toString();
    return WorkoutStorage.getOrGenerateWorkoutThumbnail(workoutName: workoutName, workoutContent: zwoContent);
  }

  /// Reuse the library's existing load/resume flows from the Arcade lobby.
  void showWorkoutLibrary(BuildContext context) => _showMenuDialog(context, initialAction: _MenuAction.selectWorkout);

  void _showWorkoutLibrary(BuildContext context, {required bool selectionMode}) {
    final rootContext = context;
    showDialog(
      context: context,
      builder: (ctx) => WorkoutDialog(
        title: const Text('Choose a workout'),
        icon: Icons.folder_open_rounded,
        subtitle: 'Find your next ride.',
        showClose: true,
        listBody: true,
        showListScrollHint: false,
        content: WorkoutLibrary(
          selectionMode: selectionMode,

          headerWidgets: selectionMode
              ? [
                  WorkoutOptionTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('Import a workout file'),
                    subtitle: const Text('Choose a .zwo file from your device'),
                    onTap: () => _runAfterDialogClose(ctx, () => _importZwo(rootContext)),
                  ),
                  FutureBuilder<bool>(
                    future: IntervalsService.isAuthenticated(),
                    builder: (futureContext, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: LinearProgressIndicator(),
                        );
                      }

                      final isConnected = snapshot.data == true;
                      return WorkoutOptionTile(
                        leading: Image.asset('assets/intervals.png', width: 50, height: 50),
                        title: Text(isConnected ? 'Intervals.icu Library' : 'Connect Intervals.icu for more workouts'),
                        subtitle: isConnected ? const Text('Browse folders & workouts') : null,
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _runAfterDialogClose(ctx, () {
                          if (isConnected) {
                            _pickWorkoutFromIntervals(rootContext);
                          } else {
                            WorkoutConnectedAccounts.showConnectedAccountsDialog(rootContext);
                          }
                        }),
                      );
                    },
                  ),
                  WorkoutOptionTile(
                    leading: Image.asset('assets/ss2kv3.png', width: 50, height: 50),
                    title: const Text('SmartSpin2k Library'),
                    subtitle: const Text('Bundled workouts'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _runAfterDialogClose(ctx, () => _showAssetWorkoutFolder(rootContext)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text('Imported Workouts:', style: Theme.of(context).textTheme.titleSmall),
                    ),
                  ),
                ]
              : const [],
          onWorkoutSelected: (name, content, isInProgress) async {
            if (!isInProgress) {
              final shouldReplace = await _confirmWorkoutReplacement(context);
              if (!shouldReplace) {
                return;
              }
              Navigator.pop(context);
              workoutController.loadWorkout(content, isResume: false);
              onWorkoutLoaded(content, name: workoutController.workoutName);
              return;
            }

            final action = await showDialog<String>(
              context: context,
              builder: (dialogContext) => WorkoutDialog(
                title: Text(name),
                content: const Text('Resume this workout or restart from the beginning?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('CANCEL')),
                  TextButton(onPressed: () => Navigator.pop(dialogContext, 'restart'), child: const Text('RESTART')),
                  TextButton(onPressed: () => Navigator.pop(dialogContext, 'resume'), child: const Text('RESUME')),
                ],
              ),
            );

            if (action == 'resume') {
              final shouldReplace = await _confirmWorkoutReplacement(context);
              if (!shouldReplace) {
                return;
              }
              Navigator.pop(context);
              final restored = await workoutController.restoreSavedWorkoutState();
              if (restored) {
                onWorkoutLoaded(content, name: workoutController.workoutName);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to resume in-progress workout.'), backgroundColor: Colors.red),
                );
              }
              return;
            }

            if (action == 'restart') {
              final shouldReplace = await _confirmWorkoutReplacement(context);
              if (!shouldReplace) {
                return;
              }
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
    );
  }

  void _showAudioCoachDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AudioCoachDialog(ttsSettings: ttsSettings),
    );
  }

  void _showCalibrationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => WorkoutDialog(
        title: const Text('Trainer setup'),
        icon: Icons.tune_rounded,
        subtitle: 'Set up your trainer for a smooth ride.',
        showClose: true,
        listBody: true,
        content: CalibrationScreen(device: device, embedded: true),
      ),
    );
  }

  void _showWorkoutTextSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState) {
            return WorkoutDialog(
              title: const Text('On-screen messages'),
              icon: Icons.text_fields_rounded,
              subtitle: 'Adjust the messages shown during your ride.',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WorkoutSettingSlider(
                    label: 'Font Size',
                    valueLabel: '${WorkoutTextStyle.scrollingText.toInt()}',
                    value: WorkoutTextStyle.scrollingText,
                    min: 24,
                    max: 72,
                    divisions: 12,
                    onChanged: (value) {
                      setState(() => WorkoutTextStyle.scrollingText = value);
                      WorkoutTextEventOverlay.saveTextSettings(value, WorkoutTextStyle.scrollSpeed);
                    },
                  ),
                  const SizedBox(height: 16),
                  WorkoutSettingSlider(
                    label: 'Scroll Speed',
                    valueLabel: '${WorkoutTextStyle.scrollSpeed.toInt()} px/s',
                    value: WorkoutTextStyle.scrollSpeed,
                    min: 50,
                    max: 300,
                    divisions: 25,
                    onChanged: (value) {
                      setState(() => WorkoutTextStyle.scrollSpeed = value);
                      WorkoutTextEventOverlay.saveTextSettings(WorkoutTextStyle.scrollingText, value);
                    },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
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
                                message:
                                    'Text Size ${WorkoutTextStyle.scrollingText.toInt()} , Speed ${WorkoutTextStyle.scrollSpeed.toInt()}',
                              ),
                            ],
                          );
                          return WorkoutDialog(
                            title: const Text('Preview workout text'),
                            icon: Icons.text_fields_rounded,
                            content: SizedBox(
                              width: double.maxFinite,
                              child: WorkoutTextEventOverlay(
                                currentSegment: testSegment,
                                secondsIntoSegment: 0,
                                ttsSettings: ttsSettings,
                                workoutController: workoutController,
                                testText:
                                    'Text Size ${WorkoutTextStyle.scrollingText.toInt()} x Speed ${WorkoutTextStyle.scrollSpeed.toInt()}',
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
          },
        );
      },
    );
  }
}

enum _MenuAction {
  ftp,
  freeRide,
  selectWorkout,
  audioCoach,
  connectedAccounts,
  calibrate,
  completedActivities,
  workoutText,
}
