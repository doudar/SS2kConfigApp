import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/workout/workout_painter.dart';
import '../utils/workout/workout_metrics.dart';
import '../utils/workout/workout_constants.dart';
import '../utils/workout/workout_controller.dart';
import '../utils/workout/workout_storage.dart';
import '../utils/workout/sounds.dart';
import '../utils/workout/gpx_file_exporter.dart';
import '../utils/workout/workout_file_manager.dart';
import '../utils/workout/workout_tts_settings.dart';
// Intervals service & converter now only used inside WorkoutMenu
import '../utils/bledata.dart';
// Workout library dialog now managed inside WorkoutMenu
// Audio coach dialog now managed inside WorkoutMenu
import '../utils/workout/workout_text_event_overlay.dart';
import '../utils/workout/workout_controls.dart';
import '../utils/workout/workout_summary.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/workout_menu.dart';
import '../widgets/power_table_chart.dart';
import '../utils/stream_extensions.dart';

enum OverlayMode { none, overview, powerTable }

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
  bool _ttsInitialized = false;
  // Track whether we've applied the initial (resume) animation state to avoid a stuck fade.
  bool _didApplyInitialAnimation = false;
  // Guard to prevent animation calls during teardown.
  bool _isDisposing = false;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<CharacteristicChangeEvent>? _characteristicChangeSubscription;
  final ScrollController _scrollController = ScrollController();
  double _lastScrollPosition = 0;
  final GlobalKey _workoutGraphKey = GlobalKey();

  late AnimationController _zoomController;
  late Animation<double> _zoomAnimation;
  // Keep a reference to the workout controller listener so we can detach it on dispose.
  late VoidCallback _workoutControllerListener;
  OverlayMode _overlayMode = OverlayMode.none;
  double _overlayTop = 10;
  double _overlayLeft = 10;
  final double _overlayWidth = 300;
  final double _overlayHeight = 180;

  void _toggleOverlay() {
    setState(() {
      switch (_overlayMode) {
        case OverlayMode.none:
          _overlayMode = OverlayMode.overview;
          break;
        case OverlayMode.overview:
          _overlayMode = OverlayMode.powerTable;
          break;
        case OverlayMode.powerTable:
          _overlayMode = OverlayMode.none;
          break;
      }
    });
  }

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

    _workoutControllerListener = () {
      if (!mounted) return;
      if (_isDisposing) return; // Skip any animation updates while disposing

      // Apply an immediate animation state the first time we get a callback after (re)entering.
      // This prevents the summary card from remaining permanently visible when resuming mid-workout.
      if (!_didApplyInitialAnimation) {
        if (_workoutController.isPlaying) {
          _metricsAndSummaryFadeController.value = 1.0; // Summary hidden, metrics visible
          _zoomController.value = 1.0; // Zoomed-in state
          _updateScrollPosition();
        } else {
          _metricsAndSummaryFadeController.value = 0.0; // Summary visible
          _zoomController.value = 0.0; // Preview state
        }
        _didApplyInitialAnimation = true;
      } else {
        // Normal animated transitions after initial state applied.
        if (_workoutController.isPlaying) {
          if (_metricsAndSummaryFadeController.status != AnimationStatus.forward && _metricsAndSummaryFadeController.value != 1.0) {
            _metricsAndSummaryFadeController.forward();
          }
          if (_zoomController.status != AnimationStatus.forward && _zoomController.value != 1.0) {
            _zoomController.forward();
          }
          _updateScrollPosition();
        } else {
          if (_metricsAndSummaryFadeController.status != AnimationStatus.reverse && _metricsAndSummaryFadeController.value != 0.0) {
            _metricsAndSummaryFadeController.reverse();
          }
          if (_zoomController.status != AnimationStatus.reverse && _zoomController.value != 0.0) {
            _zoomController.reverse();
          }
          // Check if workout completed naturally (reached the end)
          if (_workoutController.progressPosition >= 1.0) {
            _workoutController.progressPosition = 0;
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                GpxFileExporter.showExportDialog(context, _workoutController, _currentWorkoutContent);
              }
            });
          }
        }
      }

      setState(() {
        _workoutName = _workoutController.workoutName;
      });
    };
    _workoutController.addListener(_workoutControllerListener);

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

  // Intervals & other menu actions migrated to WorkoutMenu.

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

  // Audio coach dialog logic migrated to WorkoutMenu; method removed.

  // Calibration dialog logic migrated to WorkoutMenu; method removed here to avoid duplication.

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


    _characteristicChangeSubscription = bleData.characteristicChanges
        .debounce(const Duration(milliseconds: 500))
        .listen((event) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    // Remove external listeners FIRST to avoid callbacks firing while controllers are being disposed.
    _workoutController.removeListener(_workoutControllerListener);
    _characteristicChangeSubscription?.cancel();
    _connectionStateSubscription?.cancel();

    // Now safely dispose animation + other resources.
    _metricsAndSummaryFadeController.dispose();
    _zoomController.dispose();
    _scrollController.dispose();
    workoutSoundGenerator.dispose();
    _ttsSettings.dispose();
    WakelockPlus.disable();

    if (_workoutController.progressPosition >= 1.0) {
      WorkoutStorage.clearWorkoutState();
    }
    super.dispose();
  }

  // Workout text settings dialog removed; logic migrated to WorkoutMenu.

  // Workout library dialog removed; logic migrated to WorkoutMenu.

  Widget _buildOverlay() {
    if (MediaQuery.of(context).orientation == Orientation.portrait ||
        _overlayMode == OverlayMode.none) {
      return const SizedBox.shrink();
    }

    return Container(
      width: _overlayWidth,
      height: _overlayHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9),
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRect(
        child: _overlayMode == OverlayMode.overview
            ? Stack(
                children: [
                  CustomPaint(
                    size: Size.infinite,
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
                      powerPointsList:
                          _workoutController.getPowerPointsUpToNow(),
                      showLabels: false,
                    ),
                  ),
                  Positioned(
                    left: _workoutController.progressPosition * _overlayWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: Colors.red,
                    ),
                  ),
                ],
              )
            : PowerTableChart(
                device: widget.device,
                bleData: bleData,
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
          if (MediaQuery.of(context).orientation == Orientation.landscape)
            IconButton(
              icon: Icon(_overlayMode == OverlayMode.none
                  ? Icons.layers_clear
                  : _overlayMode == OverlayMode.overview
                      ? Icons.map
                      : Icons.grid_on),
              onPressed: _toggleOverlay,
              tooltip: 'Toggle Overlay',
            ),
          WorkoutMenu(
            workoutController: _workoutController,
            bleData: bleData,
            ttsSettings: _ttsSettings,
            workoutGraphKey: _workoutGraphKey,
            onWorkoutLoaded: (content, {String? name}) {
              _currentWorkoutContent = content;
              _updatePreviewDuration();
              if (name != null && mounted) {
                setState(() {
                  _workoutName = name;
                });
              }
            },
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              AnimatedBuilder(
                                animation: _zoomAnimation,
                                builder: (context, child) {
                                  return LayoutBuilder(
                                    builder: (context, graphConstraints) {
                                      final minutesWidth =
                                          graphConstraints.maxWidth /
                                              _zoomAnimation.value;
                                      final totalWidth =
                                          _workoutController.totalDuration /
                                              60 *
                                              minutesWidth;

                                      return SingleChildScrollView(
                                        physics: const NeverScrollableScrollPhysics(),
                                        controller: _scrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: RepaintBoundary(
                                          key: _workoutGraphKey,
                                          child: SizedBox(
                                            width: totalWidth,
                                            child: Stack(
                                              children: [
                                                Padding(
                                                  padding: EdgeInsets.all(
                                                      WorkoutPadding.standard),
                                                  child: Column(
                                                    children: [
                                                      Expanded(
                                                        child: CustomPaint(
                                                          painter:
                                                              WorkoutPainter(
                                                            segments:
                                                                _workoutController
                                                                    .segments,
                                                            maxPower:
                                                                _workoutController
                                                                    .maxPower,
                                                            totalDuration:
                                                                _workoutController
                                                                    .totalDuration,
                                                            ftpValue:
                                                                _workoutController
                                                                    .ftpValue,
                                                            currentProgress:
                                                                _workoutController
                                                                    .progressPosition,
                                                            actualPowerPoints:
                                                                _workoutController
                                                                    .actualPowerPoints,
                                                            currentPower: _workoutController
                                                                    .isPlaying
                                                                ? bleData
                                                                    .ftmsData
                                                                    .watts
                                                                    .toDouble()
                                                                : null,
                                                            powerPointsList:
                                                                _workoutController
                                                                    .getPowerPointsUpToNow(),
                                                          ),
                                                          child: Container(),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                          height: WorkoutSpacing
                                                              .medium),
                                                    ],
                                                  ),
                                                ),
                                                if (_workoutController
                                                    .isPlaying)
                                                  Positioned(
                                                    left: _workoutController
                                                                .progressPosition *
                                                            (totalWidth -
                                                                (2 *
                                                                    WorkoutPadding
                                                                        .standard)) +
                                                        WorkoutPadding.standard,
                                                    top: WorkoutPadding
                                                        .standard,
                                                    bottom: WorkoutSpacing
                                                            .medium +
                                                        WorkoutPadding.standard,
                                                    child: Container(
                                                      width: WorkoutSizes
                                                          .progressIndicatorWidth,
                                                      color: const Color
                                                              .fromARGB(
                                                              255, 0, 0, 0)
                                                          .withValues(
                                                              alpha: WorkoutOpacity
                                                                  .segmentBorder),
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
                              Positioned(
                                top: _overlayTop,
                                left: _overlayLeft,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      _overlayTop = (_overlayTop +
                                              details.delta.dy)
                                          .clamp(
                                              0.0,
                                              constraints.maxHeight -
                                                  _overlayHeight);
                                      _overlayLeft = (_overlayLeft +
                                              details.delta.dx)
                                          .clamp(
                                              0.0,
                                              constraints.maxWidth -
                                                  _overlayWidth);
                                    });
                                  },
                                  child: _buildOverlay(),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                left: 0,
                                right: 0,
                                child: WorkoutControls(
                                  workoutController: _workoutController,
                                  onStopWorkout: _showStopWorkoutDialog,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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

