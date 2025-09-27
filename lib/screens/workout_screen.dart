import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/workout/workout_parser.dart';
import '../utils/workout/workout_painter.dart';
import '../utils/workout/workout_metrics.dart';
import '../utils/workout/workout_constants.dart';
import '../utils/workout/workout_controller.dart';
import '../utils/workout/workout_storage.dart';
import '../utils/workout/sounds.dart';
import '../utils/workout/gpx_file_exporter.dart';
import '../utils/workout/workout_file_manager.dart';
import '../utils/workout/workout_tts_settings.dart';
import '../utils/workout/workout_connected_accounts.dart';
import '../services/intervals_service.dart';
import '../services/intervals_workout_converter.dart';
import '../utils/bledata.dart';
import '../widgets/workout_library.dart';
import '../widgets/audio_coach_dialog.dart';
import '../utils/workout/workout_text_event_overlay.dart';
import '../utils/workout/workout_controls.dart';
import '../utils/workout/workout_summary.dart';
import '../utils/ftmsControlPoint.dart';
import '../widgets/completed_activities.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/intervals_menu.dart';

class WorkoutScreen extends StatefulWidget {
  final BluetoothDevice device;
  const WorkoutScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with TickerProviderStateMixin {
  String? _workoutName;
  String? _currentWorkoutContent;
  late AnimationController _metricsAndSummaryFadeController;
  late Animation<double> _metricsAndSummaryFadeAnimation;
  late BLEData bleData;
  late WorkoutController _workoutController;
  late WorkoutTTSSettings _ttsSettings;
  bool _refreshBlocker = false;
  bool _ttsInitialized = false;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  final ScrollController _scrollController = ScrollController();
  double _lastScrollPosition = 0;
  final GlobalKey _workoutGraphKey = GlobalKey();

  late AnimationController _zoomController;
  late Animation<double> _zoomAnimation;

  void _initializeAnimationControllers() {
    _metricsAndSummaryFadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _metricsAndSummaryFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_metricsAndSummaryFadeController);

    _zoomController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _zoomAnimation = Tween<double>(
      begin: WorkoutDurations.previewMinutes,
      end: WorkoutDurations.playingMinutes,
    ).animate(CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    bleData = BLEDataManager.forDevice(widget.device);
    _workoutController = WorkoutController(bleData, widget.device);
    _initTTSSettings();
    _initializeAnimationControllers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      rwSubscription();
      if (_workoutController.segments.isEmpty) {
        _loadDefaultWorkout();
      } else if (_workoutController.isPlaying && mounted) {
        // If workout is already playing, forward the animations
        _metricsAndSummaryFadeController.forward();
        _zoomController.forward();
      } else {
        _metricsAndSummaryFadeController.animateBack(0);
        _zoomController.animateBack(0);
      }
    });

    _workoutController.addListener(() {
      if (!mounted) return; // Skip animation updates if not mounted

      if (_workoutController.isPlaying) {
        _metricsAndSummaryFadeController.forward();
        _zoomController.forward();
        _updateScrollPosition();
      } else {
        _metricsAndSummaryFadeController.reverse();
        _zoomController.reverse();
        // Check if workout completed naturally (reached the end)
        if (_workoutController.progressPosition >= 1.0) {
          //reset progress position
          _workoutController.progressPosition = 0;
          // Add a small delay to ensure the workout end sound plays first
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              GpxFileExporter.showExportDialog(context, _workoutController, _currentWorkoutContent);
            }
          });
        }
      }
      if (mounted) {
        setState(() {
          _workoutName = _workoutController.workoutName;
        });
      }
    });

    Timer.periodic(const Duration(seconds: 15), (refreshTimer) {
      if (bleData.isUserDisconnect) {
        refreshTimer.cancel();
        return;
      }
      if (!widget.device.isConnected) {
        try {
          widget.device.connect();
        } catch (e) {
          print("failed to reconnect.");
        }
      } else {
        if (!mounted) {
          refreshTimer.cancel();
        return;
        }
      }
    });
  }

  Future<void> _initTTSSettings() async {
    _ttsSettings = await WorkoutTTSSettings.create();
    if (mounted) {
      setState(() {
        _ttsInitialized = true;
      });
    }
  }

  /// Rebuilds the zoom animation tween using the current preview + playing minutes.
  void _rebuildZoomAnimation() {
    _zoomAnimation = Tween<double>(
      begin: WorkoutDurations.previewMinutes,
      end: WorkoutDurations.playingMinutes,
    ).animate(CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeInOut,
    ));
  }

  /// Update the preview (zoomed-out) minutes to match the currently loaded workout's
  /// total duration (in minutes) and rebuild the zoom animation so the graph width
  /// represents the whole workout. Ensures the preview window is never smaller than
  /// the playing window.
  void _updatePreviewDuration() {
    double minutes = _workoutController.totalDuration / 60.0;
    // Ensure preview is at least as large as the playing window to avoid inverted animation.
    if (minutes < WorkoutDurations.playingMinutes) {
      minutes = WorkoutDurations.playingMinutes;
    }
    WorkoutDurations.previewMinutes = minutes;

    // Preserve whether we were zoomed-in/playing; typically after a load we're not playing yet.
    final bool wasPlaying = _workoutController.isPlaying;
    // Reset controller to start position for a new workout preview.
    _zoomController.stop();
    _zoomController.value = wasPlaying ? 1.0 : 0.0; // if already playing keep zoomed-in state
    _rebuildZoomAnimation();
    if (!wasPlaying) {
      // Ensure we start at preview (value 0) visually.
      _zoomController.value = 0.0;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDefaultWorkout() async {
    try {
      final content = await rootBundle.loadString('assets/Anthonys_Mix.zwo');
      _workoutController.loadWorkout(content, isResume: false);
      _currentWorkoutContent = content;
      _updatePreviewDuration();
      // Wait for the graph to be rendered
      await Future.delayed(const Duration(milliseconds: 100));

      // Generate and save thumbnail for default workout
      final thumbnail = await WorkoutFileManager.captureWorkoutThumbnail(_workoutGraphKey);
      if (thumbnail != null) {
        await WorkoutStorage.updateWorkoutThumbnail(WorkoutStorage.defaultWorkoutName, thumbnail);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading default workout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadTodaysWorkoutFromIntervals() async {
    try {
      // Check if Intervals.icu is connected
      if (!await IntervalsService.isAuthenticated()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please connect to Intervals.icu first in Connected Accounts'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading today\'s workout from Intervals.icu...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Fetch today's workout
      final todaysWorkout = await IntervalsService.getTodaysWorkout();
      
      if (todaysWorkout == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No planned workout found for today on Intervals.icu'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Extract the workout XML content
      final workoutDoc = todaysWorkout['workout_doc'];
      if (workoutDoc == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Today\'s workout does not contain structured data'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Convert Intervals.icu workout to ZWO format
      final workoutContent = IntervalsWorkoutConverter.convertToZwo(workoutDoc);
      
      // Load the workout
      _workoutController.loadWorkout(workoutContent);
      _currentWorkoutContent = workoutContent;
  _updatePreviewDuration();
      
      // Update workout name
      final workoutName = todaysWorkout['name'] ?? 'Today\'s Workout';
      setState(() {
        _workoutName = workoutName;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully loaded: $workoutName'),
            backgroundColor: const Color(0xFF1B4F72),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading today\'s workout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickWorkoutFromIntervals() async {
    try {
      if (!await IntervalsService.isAuthenticated()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please connect to Intervals.icu first in Connected Accounts'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Fetch top-level folders
      final folders = await IntervalsService.getWorkoutFolders();
      if (folders.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No Intervals.icu folders found'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      // Helper to present a folder's child workouts (non-folder children with workout_doc/file)
      Future<Map<String, dynamic>?> pickWorkoutFromFolder(Map<String, dynamic> folder) async {
        final children = (folder['children'] is List) ? List<Map<String, dynamic>>.from(
          (folder['children'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)),
        ) : <Map<String, dynamic>>[];

        // Filter workouts (items with workout_doc or workout_file)
        final workouts = children.where((c) => c['workout_doc'] != null || c['workout_file'] != null).toList();
        if (workouts.isEmpty) {
          return null;
        }
        return showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Workouts • ${folder['name'] ?? 'Folder'}'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: workouts.length,
                itemBuilder: (context, index) {
                  final w = workouts[index];
                  final name = (w['name'] ?? 'Workout').toString();
                  // Build subtitle from moving_time (seconds) -> hh:mm:ss, training load and intensity
                  String formatDuration(int seconds) {
                    final h = seconds ~/ 3600;
                    final m = (seconds % 3600) ~/ 60;
                    final s = seconds % 60;
                    String two(int v) => v.toString().padLeft(2, '0');
                    if (h > 0) {
                      return '${two(h)}:${two(m)}:${two(s)}';
                    }
                    return '${two(m)}:${two(s)}';
                  }
                  final movingTime = (w['moving_time'] is int) ? w['moving_time'] as int : int.tryParse('${w['moving_time'] ?? ''}') ?? 0;
                  final load = (w['icu_training_load'] is num) ? (w['icu_training_load'] as num).toInt() : int.tryParse('${w['icu_training_load'] ?? ''}') ?? 0;
                  final intensity = (w['icu_intensity'] is num) ? (w['icu_intensity'] as num).toDouble() : double.tryParse('${w['icu_intensity'] ?? ''}') ?? 0.0;
                  final subtitleParts = <String>[];
                  if (movingTime > 0) subtitleParts.add(formatDuration(movingTime));
                  if (load > 0) subtitleParts.add('TL $load');
                  if (intensity > 0) subtitleParts.add('IF ${intensity.toStringAsFixed(2)}');
                  final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join(' • ');
                  return ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: Text(name),
                    subtitle: subtitle != null ? Text(subtitle) : null,
                    onTap: () => Navigator.of(context).pop(w),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        );
      }

      // Show top-level folders for selection
      final selectedFolder = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Intervals.icu Folders'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final f = folders[index];
                  final name = (f['name'] ?? 'Folder').toString();
                  final count = (f['children'] is List) ? (f['children'] as List).length : 0;
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(name),
                    subtitle: Text('$count items'),
                    onTap: () => Navigator.of(context).pop(f),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
            ],
          ),
      );

      if (selectedFolder == null) return;

      final selectedWorkout = await pickWorkoutFromFolder(selectedFolder);
      if (selectedWorkout == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No workouts in that folder'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final workoutDoc = selectedWorkout['workout_doc'];
      final workoutFile = selectedWorkout['workout_file'];
      if (workoutDoc == null && workoutFile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected item has no workout data'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Convert to ZWO (converter will handle if already XML)
      final zwo = IntervalsWorkoutConverter.convertToZwo(
        workoutDoc is Map<String, dynamic> ? workoutDoc : {
          'workout_file': workoutFile,
          'name': selectedWorkout['name'],
          'description': selectedWorkout['description'],
          'steps': (workoutDoc is Map<String, dynamic>) ? workoutDoc['steps'] : null,
        },
      );

      _workoutController.loadWorkout(zwo);
      _currentWorkoutContent = zwo;
      _updatePreviewDuration();
      setState(() {
        _workoutName = (selectedWorkout['name'] ?? 'Intervals.icu Workout').toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded: ${_workoutName ?? 'Intervals.icu Workout'}'),
            backgroundColor: const Color(0xFF1B4F72),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking Intervals.icu workout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showStopWorkoutDialog() async {
    final bool? shouldStop = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Workout?'),
          content: const Text('Do you want to end your workout?'),
          actions: <Widget>[
            TextButton(
              child: const Text('NO'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('YES'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (shouldStop == true) {
      await _workoutController.stopWorkout();
      GpxFileExporter.showExportDialog(context, _workoutController, _currentWorkoutContent);
    }
  }

  void _showAudioCoachDialog() {
    showDialog(
      context: context,
      builder: (context) => AudioCoachDialog(ttsSettings: _ttsSettings),
    );
  }

  Future<void> _showCalibrationDialog() async {
    bool isCalibrating = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Calibration'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isCalibrating)
                    const Text('Start pedaling until the SmartSpin2k knob starts to turn.\n\nPress Start when ready.'),
                  if (isCalibrating)
                    const Text(
                        'Stop pedaling and wait for the calibration to complete.\n\nThis may take a few moments...'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('CANCEL'),
                ),
                if (!isCalibrating)
                  TextButton(
                    onPressed: () async {
                      setState(() {
                        isCalibrating = true;
                      });

                      try {
                        // Get the FTMS Control Point characteristic from bleData
                        final ftmsControlPointChar = bleData.ftmsControlPointCharacteristic;
                        if (ftmsControlPointChar != null) {
                          // Start the spin down procedure
                          await FTMSControlPoint.spinDownControl(ftmsControlPointChar, true);

                          // Wait for a response or timeout after 30 seconds
                          await Future.delayed(const Duration(seconds: 30));

                          if (mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Calibration completed'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          throw Exception('FTMS Control Point characteristic not found');
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Calibration failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('START'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateScrollPosition() {
    if (!mounted || !_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_workoutController.isPlaying && _scrollController.hasClients) {
        final viewportWidth = _scrollController.position.viewportDimension;
        final totalWidth = _scrollController.position.maxScrollExtent + viewportWidth;
        final progressWidth = _workoutController.progressPosition * (totalWidth - (2 * WorkoutPadding.standard));
        final targetScroll = progressWidth - (viewportWidth / 2);

        if ((targetScroll - _lastScrollPosition).abs() > 1.0) {
          _scrollController.animateTo(
            targetScroll.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
          _lastScrollPosition = targetScroll;
        }
      }
    });
  }

  Future<void> rwSubscription() async {
    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      bleData.isReadingOrWriting.addListener(_rwListener);
    });
  }

  void _rwListener() async {
    if (_refreshBlocker) return;
    _refreshBlocker = true;
    await Future.delayed(const Duration(microseconds: 500));

    if (mounted) {
      setState(() {});
    }
    _refreshBlocker = false;
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _metricsAndSummaryFadeController.dispose();
    _zoomController.dispose();
    _connectionStateSubscription?.cancel();
    bleData.isReadingOrWriting.removeListener(_rwListener);
    _scrollController.dispose();
    workoutSoundGenerator.dispose();
    _ttsSettings.dispose();
    if (_workoutController.progressPosition >= 1.0) {
      WorkoutStorage.clearWorkoutState();
    }
    super.dispose();
  }

  void _showWorkoutTextSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                      setState(() {
                        WorkoutTextStyle.scrollingText = value;
                      });
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
                      setState(() {
                        WorkoutTextStyle.scrollSpeed = value;
                      });
                      WorkoutTextEventOverlay.saveTextSettings(WorkoutTextStyle.scrollingText, value);
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          final testSegment = WorkoutSegment(
                            type: SegmentType.steadyState,
                            duration: 60,
                            powerLow: 100,
                            powerHigh: 150,
                            textEvents: [
                              TextEvent(
                                timeOffset: 0,
                                message: 'Text Size ${WorkoutTextStyle.scrollingText.toInt()} '
                                    ', Speed ${WorkoutTextStyle.scrollSpeed.toInt()}',
                              ),
                            ],
                          );
                          
                          return AlertDialog(
                            content: SizedBox(
                              width: double.maxFinite,
                              child: WorkoutTextEventOverlay(
                                currentSegment: testSegment,
                                secondsIntoSegment: 0,
                                ttsSettings: _ttsSettings,
                                workoutController: _workoutController,
                                testText: 'Text Size ${WorkoutTextStyle.scrollingText.toInt()} '
                                    'x Speed ${WorkoutTextStyle.scrollSpeed.toInt()}',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('CLOSE'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: const Text('TEST SETTINGS'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showWorkoutLibrary({required bool selectionMode}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                  onWorkoutSelected: (content) {
                    Navigator.pop(context);
                    _workoutController.loadWorkout(content, isResume: false);
                    _currentWorkoutContent = content;
                  },
                  onWorkoutDeleted: (name) async {
                    await WorkoutStorage.deleteWorkout(name);
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ttsInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: SS2KAppBar(
        device: widget.device,
        title: _workoutName ?? '',
        actions: [
          IntervalsMenu(
            onImportZwo: () => WorkoutFileManager.pickAndLoadWorkout(
              context: context,
              workoutController: _workoutController,
              workoutGraphKey: _workoutGraphKey,
              onWorkoutLoaded: (content) {
                _currentWorkoutContent = content;
              },
            ),
            onIntervalsToday: _loadTodaysWorkoutFromIntervals,
            onIntervalsPick: _pickWorkoutFromIntervals,
            onSelectWorkout: () => _showWorkoutLibrary(selectionMode: true),
            onDeleteWorkout: () => _showWorkoutLibrary(selectionMode: false),
            onAudioCoach: _showAudioCoachDialog,
            onConnectedAccounts: () => WorkoutConnectedAccounts.showConnectedAccountsDialog(context),
            onCalibrate: _showCalibrationDialog,
            onCompletedActivities: () => CompletedActivities.showCompletedActivitiesDialog(context),
            onWorkoutTextSettings: _showWorkoutTextSettingsDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Stack(
                children: [
                  WorkoutSummary(
                    workoutController: _workoutController,
                    fadeAnimation: _metricsAndSummaryFadeAnimation,
                  ),
                  WorkoutMetrics(
                    bleData: bleData,
                    fadeAnimation: _metricsAndSummaryFadeAnimation,
                    elapsedTime: _workoutController.elapsedSeconds,
                    timeToNextSegment: _workoutController.currentSegmentTimeRemaining,
                    totalDuration: _workoutController.totalDuration,
                    speedMph: _workoutController.speedMph,
                    totalDistance: _workoutController.totalDistance,
                    workoutProgressSeconds: _workoutController.workoutProgressSeconds,
                  ),
                ],
              ),
              Expanded(
                child: _workoutController.segments.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : AnimatedBuilder(
                        animation: _zoomAnimation,
                        builder: (context, child) {
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final minutesWidth = constraints.maxWidth / _zoomAnimation.value;
                              final totalWidth = _workoutController.totalDuration / 60 * minutesWidth;

                              return SingleChildScrollView(
                                controller: _scrollController,
                                scrollDirection: Axis.horizontal,
                                child: RepaintBoundary(
                                  key: _workoutGraphKey,
                                  child: SizedBox(
                                    width: totalWidth,
                                    child: Stack(
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.all(WorkoutPadding.standard),
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: CustomPaint(
                                                  painter: WorkoutPainter(
                                                    segments: _workoutController.segments,
                                                    maxPower: _workoutController.maxPower,
                                                    totalDuration: _workoutController.totalDuration,
                                                    ftpValue: _workoutController.ftpValue,
                                                    currentProgress: _workoutController.progressPosition,
                                                    actualPowerPoints: _workoutController.actualPowerPoints,
                                                    currentPower: _workoutController.isPlaying
                                                        ? bleData.ftmsData.watts.toDouble()
                                                        : null,
                                                    powerPointsList: _workoutController.getPowerPointsUpToNow(),
                                                  ),
                                                  child: Container(),
                                                ),
                                              ),
                                              SizedBox(height: WorkoutSpacing.medium),
                                            ],
                                          ),
                                        ),
                                        if (_workoutController.isPlaying)
                                          Positioned(
                                            left: _workoutController.progressPosition *
                                                    (totalWidth - (2 * WorkoutPadding.standard)) +
                                                WorkoutPadding.standard,
                                            top: WorkoutPadding.standard,
                                            bottom: WorkoutSpacing.medium + WorkoutPadding.standard,
                                            child: Container(
                                              width: WorkoutSizes.progressIndicatorWidth,
                                              color: const Color.fromARGB(255, 0, 0, 0)
                                                  .withOpacity(WorkoutOpacity.segmentBorder),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              WorkoutControls(
                workoutController: _workoutController,
                onStopWorkout: _showStopWorkoutDialog,
              ),
            ],
          ),
          Positioned.fill(
            child: _workoutController.isPlaying
                ? WorkoutTextEventOverlay(
                    currentSegment: _workoutController.currentSegment,
                    secondsIntoSegment: _workoutController.currentSegmentElapsedSeconds,
                    ttsSettings: _ttsSettings,
                    workoutController: _workoutController,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
