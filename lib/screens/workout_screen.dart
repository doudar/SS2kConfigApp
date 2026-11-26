import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/workout/workout_painter.dart';
import '../utils/workout/workout_pip_view.dart';
import '../utils/workout/workout_metrics.dart';
import '../utils/workout/classic_workout_preview.dart';
import '../utils/workout/workout_visuals.dart';
import '../utils/workout/workout_constants.dart';
import '../utils/workout/workout_controller.dart';
import '../utils/workout/workout_storage.dart';
import '../utils/workout/sounds.dart';
import '../utils/workout/gpx_file_exporter.dart';
import '../utils/workout/workout_export_dialog.dart';
import '../utils/workout/workout_tts_settings.dart';
import '../utils/workout/workout_lobby.dart';
import '../utils/workout/workout_lobby_choice.dart';
// Intervals service & converter now only used inside WorkoutMenu
import '../utils/device_data.dart';
// Workout library dialog now managed inside WorkoutMenu
// Audio coach dialog now managed inside WorkoutMenu
import '../utils/workout/workout_text_event_overlay.dart';
import '../utils/workout/workout_controls.dart';
import '../utils/workout/workout_summary.dart';
import '../widgets/ss2k_app_bar.dart';
import '../widgets/workout_header_action.dart';
import '../widgets/workout_menu.dart';
import '../utils/stream_extensions.dart';
import '../utils/workout/arcade/arcade_session.dart';
import '../utils/workout/arcade/arcade_workout_view.dart';
import '../utils/workout/arcade/arcade_finale.dart';
import '../utils/workout/arcade/arcade_workout_frame.dart';
import '../utils/workout/arcade/arcade_preferences.dart';

class WorkoutScreen extends StatefulWidget {
  final BluetoothDevice device;
  const WorkoutScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with TickerProviderStateMixin {
  String? _workoutName;
  bool _arcadeMode = false;
  bool _arcadeFullscreen = false;
  late bool _structuredRidePlaying;
  bool get _canOpenPip => _pipSupported && _structuredRidePlaying;
  bool _arcadePreferencesLoaded = false;
  bool _completionPending = false;
  static const _pipChannel = MethodChannel('com.smartspin2k.app/workout_pip');
  bool _pipSupported = false;
  MediaQueryData? _mediaBeforePip;
  bool _finishedInPip = false;
  bool _startingWorkout = false;
  final ArcadeSession _arcadeSession = ArcadeSession();
  late AnimationController _metricsAndSummaryFadeController;
  late Animation<double> _metricsAndSummaryFadeAnimation;
  late DeviceData deviceData;
  late WorkoutController _workoutController;
  late WorkoutTTSSettings _ttsSettings;
  bool _ttsInitialized = false;
  // Track whether we've applied the initial (resume) animation state to avoid a stuck fade.
  bool _didApplyInitialAnimation = false;
  // Guard to prevent animation calls during teardown.
  bool _isDisposing = false;
  final ScrollController _scrollController = ScrollController();
  double _lastScrollPosition = 0;

  late AnimationController _zoomController;
  late Animation<double> _zoomAnimation;
  late AnimationController _pulseController;

  // Keep a reference to the workout controller listener so we can detach it on dispose.
  late VoidCallback _workoutControllerListener;
  void _initializeAnimationControllers() {
    _metricsAndSummaryFadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _metricsAndSummaryFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_metricsAndSummaryFadeController);

    _zoomController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _zoomAnimation =
        Tween<double>(
          begin: WorkoutDurations.previewMinutes,
          end: WorkoutDurations.playingMinutes,
        ).animate(
          CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut),
        );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _syncClassicPulse();
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    deviceData = DeviceDataManager.forDevice(widget.device);
    unawaited(deviceData.ensureFtmsNotifications(widget.device));
    _workoutController = WorkoutController(deviceData, widget.device);
    _structuredRidePlaying = _workoutController.isPlaying && !_workoutController.isFreeRide;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _pipChannel.setMethodCallHandler(_handlePipChange);
      unawaited(_checkPipSupport());
    }
    _initTTSSettings();
    _initializeAnimationControllers();
    unawaited(_loadArcadePreferences());

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      _syncClassicPulse();
      final fullscreen = _arcadeMode && _workoutController.isPlaying;
      final structuredRide = _workoutController.isPlaying && !_workoutController.isFreeRide;
      if (_arcadeFullscreen != fullscreen || _structuredRidePlaying != structuredRide) {
        setState(() {
          _arcadeFullscreen = fullscreen;
          _structuredRidePlaying = structuredRide;
        });
      }

      final lastUpdate = deviceData.lastFtmsUpdate;
      _arcadeSession.update(
        segments: _workoutController.segments,
        seconds: _workoutController.workoutProgressSeconds,
        playing: _workoutController.isPlaying,
        watts: deviceData.ftmsData.watts.toDouble(),
        target: deviceData.ftmsData.targetERG.toDouble(),
        ftp: _workoutController.ftpValue,
        endless: _workoutController.isUnlimitedFreeRide,
        riddenSeconds: _workoutController.elapsedSeconds.toDouble(),
        freshSignal:
            lastUpdate != null &&
            DateTime.now().difference(lastUpdate) < const Duration(seconds: 3),
      );

      // Apply an immediate animation state the first time we get a callback after (re)entering.
      // This prevents the summary card from remaining permanently visible when resuming mid-workout.
      if (!_didApplyInitialAnimation) {
        if (_workoutController.isPlaying) {
          _metricsAndSummaryFadeController.value =
              1.0; // Summary hidden, metrics visible
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
          if (_metricsAndSummaryFadeController.status !=
                  AnimationStatus.forward &&
              _metricsAndSummaryFadeController.value != 1.0) {
            _metricsAndSummaryFadeController.forward();
          }
          if (_zoomController.status != AnimationStatus.forward &&
              _zoomController.value != 1.0) {
            _zoomController.forward();
          }
          _updateScrollPosition();
        } else {
          if (_metricsAndSummaryFadeController.status !=
                  AnimationStatus.reverse &&
              _metricsAndSummaryFadeController.value != 0.0) {
            _metricsAndSummaryFadeController.reverse();
          }
          if (_zoomController.status != AnimationStatus.reverse &&
              _zoomController.value != 0.0) {
            _zoomController.reverse();
          }
          // Check if workout completed naturally (reached the end)
          // Skip for unlimited free rides since they extend dynamically
          if (_workoutController.progressPosition >= 1.0 &&
              !_workoutController.isUnlimitedFreeRide) {
            _workoutController.progressPosition = 0;
            if (_mediaBeforePip != null) {
              setState(() => _finishedInPip = true);
            } else {
              unawaited(_showFinishAndExport(celebrate: _arcadeMode));
            }
          }
        }
      }

      final String? newName = _workoutController.workoutName;
      if (newName != _workoutName) {
        setState(() {
          _workoutName = newName;
        });
      }
    };
    _workoutController.addListener(_workoutControllerListener);

    // Reconnection is handled centrally by DeviceData.startConnectionMonitor.
    // No per-screen reconnect timer needed.
  }

  Future<void> _loadArcadePreferences() async {
    final preferences = await ArcadePreferences.load();
    if (!mounted || _isDisposing) return;
    _arcadeSession.musicEnabled = preferences.musicEnabled;
    _arcadeSession.effectsEnabled = preferences.effectsEnabled;
    _arcadeSession.rider = preferences.rider;
    _arcadeSession.restoreStoryPreference(preferences.lastStoryVariant);
    _setArcadeMode(preferences.arcadeMode, persist: false);
    setState(() => _arcadePreferencesLoaded = true);
  }

  Future<void> _checkPipSupport() async {
    try {
      final supported = await _pipChannel.invokeMethod<bool>('isSupported');
      if (mounted && supported == true) setState(() => _pipSupported = true);
    } on MissingPluginException {
      // Hosts without the Android activity cannot offer the overlay.
    }
  }

  Future<void> _handlePipChange(MethodCall call) async {
    if (call.method == 'modeChanged' && call.arguments == false) _leavePip();
  }

  void _leavePip() {
    if (!mounted || _mediaBeforePip == null) return;
    final showFinish = _finishedInPip;
    setState(() {
      _mediaBeforePip = null;
      _finishedInPip = false;
    });
    _syncClassicPulse();
    if (showFinish) unawaited(_showFinishAndExport(celebrate: _arcadeMode));
  }

  Future<void> _openPip() async {
    if (!mounted || !_canOpenPip || _mediaBeforePip != null)
      return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _mediaBeforePip = MediaQuery.of(context));
    _syncClassicPulse();
    // Draw the compact view before Android starts shrinking the activity.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      if (await _pipChannel.invokeMethod<bool>('enter') == true) return;
    } on PlatformException {
      // Android can deny entry even on a device that advertises PiP.
    }
    if (!mounted) return;
    _leavePip();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the overlay. Check picture-in-picture access for SmartSpin2k in Android settings.',
        ),
      ),
    );
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
    _zoomAnimation =
        Tween<double>(
          begin: WorkoutDurations.previewMinutes,
          end: WorkoutDurations.playingMinutes,
        ).animate(
          CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut),
        );
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
    _zoomController.value = wasPlaying
        ? 1.0
        : 0.0; // if already playing keep zoomed-in state
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
      _updatePreviewDuration();
      await WorkoutStorage.getOrGenerateWorkoutThumbnail(
        workoutName: WorkoutStorage.defaultWorkoutName,
        workoutContent: content,
      );
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

  Future<void> _showFinishAndExport({bool celebrate = false}) async {
    if (_completionPending || !mounted) return;
    _completionPending = true;
    final story = _arcadeSession.story;
    try {
      // Leave the controller notification stack before opening a route.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted ||
          _workoutController.isPlaying ||
          !identical(story, _arcadeSession.story))
        return;
      if (celebrate) await ArcadeFinale.show(context, _arcadeSession);
      if (!mounted ||
          _workoutController.isPlaying ||
          !identical(story, _arcadeSession.story))
        return;
      await GpxFileExporter.showExportDialog(context, _workoutController);
    } finally {
      _completionPending = false;
    }
  }

  Future<void> _showStopWorkoutDialog() async {
    if (_completionPending) return;
    final bool? shouldStop = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => WorkoutEndDialog(
        workoutName: _workoutController.workoutName ?? 'Indoor ride',
        duration: _workoutController.formatDuration(
          _workoutController.elapsedSeconds,
        ),
        remaining: _workoutController.isUnlimitedFreeRide
            ? null
            : _workoutController.formatDuration(
                (_workoutController.totalDuration -
                        _workoutController.workoutProgressSeconds)
                    .clamp(0, double.infinity)
                    .ceil(),
              ),
        playing: _workoutController.isPlaying,
      ),
    );

    if (shouldStop == true) {
      await _workoutController.stopWorkout();
      if (mounted) await _showFinishAndExport();
    }
  }

  // Audio coach dialog logic migrated to WorkoutMenu; method removed.

  // Calibration dialog logic migrated to WorkoutMenu; method removed here to avoid duplication.

  void _setArcadeMode(bool enabled, {bool persist = true}) {
    if (_arcadeMode == enabled) return;
    setState(() {
      _arcadeMode = enabled;
      _arcadeFullscreen = enabled && _workoutController.isPlaying;
    });
    if (persist) unawaited(ArcadePreferences.saveMode(enabled));
    // Keep the graph painted for thumbnail capture without animating it behind
    // either pre-ride lobby or Arcade.
    _syncClassicPulse();
    if (enabled) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.offset);
      }
    } else {
      _updateScrollPosition();
    }
  }

  void _syncClassicPulse() {
    if (_arcadeMode || _showWorkoutLobby || _mediaBeforePip != null) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _updateScrollPosition() {
    if (!mounted || _arcadeMode || !_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposing || _arcadeMode) return;
      if (_workoutController.isPlaying && _scrollController.hasClients) {
        final viewportWidth = _scrollController.position.viewportDimension;
        final totalWidth =
            _scrollController.position.maxScrollExtent + viewportWidth;
        final progressWidth =
            _workoutController.progressPosition *
            (totalWidth - (2 * WorkoutPadding.standard));
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

  @override
  void dispose() {
    _isDisposing = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _pipChannel.setMethodCallHandler(null);
    }
    _workoutController.removeListener(_workoutControllerListener);

    // Now safely dispose animation + other resources.
    _metricsAndSummaryFadeController.dispose();
    _zoomController.dispose();
    _pulseController.dispose();
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

  void _onWorkoutLoaded() {
    _updatePreviewDuration();
    if (mounted) setState(() => _workoutName = _workoutController.workoutName);
  }

  WorkoutMenu _workoutMenu() => WorkoutMenu(
    workoutController: _workoutController,
    deviceData: deviceData,
    device: widget.device,
    ttsSettings: _ttsSettings,
    onWorkoutLoaded: (content, {String? name}) {
      _updatePreviewDuration();
      if (name != null && mounted) setState(() => _workoutName = name);
    },
  );

  bool get _showWorkoutLobby =>
      !_arcadeMode &&
      !_workoutController.isPlaying &&
      _workoutController.workoutProgressSeconds == 0;

  Future<void> _startWorkoutFromLobby() async {
    if (!_showWorkoutLobby ||
        _startingWorkout ||
        _workoutController.segments.isEmpty)
      return;
    setState(() => _startingWorkout = true);
    try {
      workoutSoundGenerator.playButtonSound();
      await _workoutController.togglePlayPause();
    } finally {
      if (mounted) setState(() => _startingWorkout = false);
    }
  }

  void _selectLobbyWorkout(WorkoutLobbyChoice choice) {
    if (!_showWorkoutLobby || _startingWorkout) return;
    try {
      _workoutController.loadWorkout(choice.content, isResume: false);
      _onWorkoutLoaded();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This workout could not be loaded. Choose another ride.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ttsInitialized || !_arcadePreferencesLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final media = _mediaBeforePip;
    // Keep the device header (reconnection) and text events (voice coach)
    // mounted at ride size while Android resizes the activity.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: media == null ? 0 : null,
          bottom: media == null ? 0 : null,
          width: media?.size.width,
          height: media?.size.height,
          child: Offstage(
            offstage: media != null,
            child: TickerMode(
              enabled: media == null,
              child: MediaQuery(
                data: media ?? MediaQuery.of(context),
                child: Builder(builder: _buildRide),
              ),
            ),
          ),
        ),
        if (media != null)
          WorkoutPipView(
            controller: _workoutController,
            finished: _finishedInPip,
          ),
      ],
    );
  }

  Widget _buildRide(BuildContext context) {
    return ArcadeWorkoutFrame(
      expanded: _arcadeFullscreen,
      arcade: _arcadeMode
          ? ArcadeWorkoutView(
              hasDeviceHeader: true,
              controller: _workoutController,
              deviceData: deviceData,
              session: _arcadeSession,
              onStop: _showStopWorkoutDialog,
              onExit: () => _setArcadeMode(false),
              onBrowseWorkouts: () =>
                  _workoutMenu().showWorkoutLibrary(context),
              onWorkoutLoaded: _onWorkoutLoaded,
              onOpenPip: _canOpenPip ? _openPip : null,
              onOpenMenu: () => _workoutMenu().show(context),
            )
          : null,
      overlay: AnimatedBuilder(
        animation: _workoutController,
        builder: (context, _) {
          if (!_workoutController.isPlaying) return const SizedBox.shrink();
          return WorkoutTextEventOverlay(
            currentSegment: _workoutController.currentSegment,
            secondsIntoSegment: _workoutController.currentSegmentElapsedSeconds,
            ttsSettings: _ttsSettings,
            workoutController: _workoutController,
          );
        },
      ),
      header: SS2KAppBar(
        device: widget.device,
        title: _workoutName?.isNotEmpty == true ? _workoutName! : 'Workout',
        firmwareOnlyDeviceHeader: true,
        mobileActionRow: true,
        actions: [
          WorkoutHeaderAction(
            label: _arcadeMode ? 'Classic mode' : 'Arcade mode',
            badge: _arcadeMode ? null : 'BETA',
            icon: _arcadeMode ? Icons.show_chart : Icons.sports_esports,
            tooltip: _arcadeMode
                ? 'Classic workout mode'
                : 'Arcade workout mode (beta)',
            onPressed: () => _setArcadeMode(!_arcadeMode),
          ),
          if (!_arcadeMode && _canOpenPip)
            WorkoutHeaderAction.pictureInPicture(onPressed: _openPip),
          WorkoutHeaderAction(
            label: 'Ride menu',
            icon: Icons.menu_rounded,
            tooltip: 'Workouts and ride settings',
            onPressed: () => _workoutMenu().show(context),
          ),
        ],
      ),
      body: _mediaBeforePip != null ? const SizedBox.shrink() : AnimatedBuilder(
        animation: _workoutController,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            // Paint Classic behind Arcade so imports can still capture graph
            // thumbnails. Preserve its scroll position and control state.
            ExcludeFocus(
              excluding: _arcadeMode || _showWorkoutLobby,
              child: ExcludeSemantics(
                excluding: _arcadeMode || _showWorkoutLobby,
                child: IgnorePointer(
                  ignoring: _arcadeMode || _showWorkoutLobby,
                  child: ClassicWorkoutSurface(
                    child: Column(
                      children: [
                        SizedBox(
                          child: !_workoutController.isPlaying
                              ? WorkoutSummary(
                                  workoutController: _workoutController,
                                  fadeAnimation:
                                      _metricsAndSummaryFadeAnimation,
                                )
                              : StreamBuilder<CharacteristicChangeEvent>(
                                  stream: deviceData.characteristicChanges
                                      .where((event) => event.type == 'ftms')
                                      .debounce(
                                        const Duration(milliseconds: 100),
                                      ),
                                  builder: (context, snapshot) =>
                                      WorkoutMetrics(
                                        deviceData: deviceData,
                                        fadeAnimation:
                                            _metricsAndSummaryFadeAnimation,
                                        elapsedTime:
                                            _workoutController.elapsedSeconds,
                                        timeToNextSegment: _workoutController
                                            .currentSegmentTimeRemaining,
                                        totalDuration:
                                            _workoutController.totalDuration,
                                        speedMph: _workoutController.speedMph,
                                        totalDistance:
                                            _workoutController.totalDistance,
                                        workoutProgressSeconds:
                                            _workoutController
                                                .workoutProgressSeconds,
                                        isUnlimitedFreeRide: _workoutController
                                            .isUnlimitedFreeRide,
                                      ),
                                ),
                        ),
                        const WorkoutTraceLegend(),
                        Expanded(
                          child: _workoutController.segments.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : AnimatedBuilder(
                                animation: Listenable.merge([
                                  _zoomAnimation,
                                  _pulseController,
                                  _workoutController,
                                ]),
                                builder: (context, child) {
                                  return LayoutBuilder(
                                    builder: (context, graphConstraints) {
                                      final verticalPadding =
                                          (graphConstraints
                                                      .maxHeight /
                                                  5)
                                              .clamp(
                                                0.0,
                                                WorkoutPadding
                                                    .standard,
                                              );
                                      final labelSpace =
                                          (graphConstraints
                                                      .maxHeight /
                                                  5)
                                              .clamp(
                                                0.0,
                                                WorkoutSpacing.medium,
                                              );
                                      final totalWidth =
                                          calculateWorkoutGraphWidth(
                                            viewportWidth:
                                                graphConstraints
                                                    .maxWidth,
                                            workoutDurationSeconds:
                                                _workoutController
                                                    .totalDuration,
                                            visibleMinutes:
                                                _zoomAnimation.value,
                                          );

                                      return SingleChildScrollView(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        controller: _scrollController,
                                        scrollDirection:
                                            Axis.horizontal,
                                        child: RepaintBoundary(
                                          child: SizedBox(
                                            width: totalWidth,
                                            child: Stack(
                                              children: [
                                                Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal:
                                                        WorkoutPadding
                                                            .standard,
                                                    vertical:
                                                        verticalPadding,
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      Expanded(
                                                        child: CustomPaint(
                                                          painter: WorkoutPainter(
                                                            showLabels:
                                                                graphConstraints
                                                                    .maxHeight >=
                                                                80,
                                                            maxPixelsPerWatt:
                                                                .75,
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
                                                            currentPower:
                                                                _workoutController
                                                                    .isPlaying
                                                                ? deviceData.ftmsData.watts.toDouble()
                                                                : null,
                                                            currentHr:
                                                                _workoutController
                                                                    .isPlaying
                                                                ? deviceData.ftmsData.heartRate
                                                                : null,
                                                            currentCadence:
                                                                _workoutController
                                                                    .isPlaying
                                                                ? deviceData.ftmsData.cadence
                                                                : null,
                                                            powerPointsList:
                                                                _workoutController
                                                                    .getPowerPointsUpToNow(),
                                                            hrPointsList:
                                                                _workoutController
                                                                    .getHrPointsUpToNow(),
                                                            cadencePointsList:
                                                                _workoutController
                                                                    .getCadencePointsUpToNow(),
                                                            pulseValue:
                                                                _pulseController
                                                                    .value,
                                                          ),
                                                          child:
                                                              Container(),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            labelSpace,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (_workoutController
                                                    .isPlaying)
                                                  Positioned(
                                                    left:
                                                        _workoutController
                                                                .progressPosition *
                                                            (totalWidth -
                                                                (2 *
                                                                    WorkoutPadding.standard)) +
                                                        WorkoutPadding
                                                            .standard,
                                                    top:
                                                        verticalPadding,
                                                    bottom:
                                                        labelSpace +
                                                        verticalPadding,
                                                    child: Container(
                                                      width: WorkoutSizes
                                                          .progressIndicatorWidth,
                                                      color: WorkoutVisuals
                                                          .mint
                                                          .withValues(
                                                            alpha: WorkoutOpacity
                                                                .segmentBorder,
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
                                },
                              ),
                        ),
                        ClassicWorkoutDock(
                          controls: WorkoutControls(
                            workoutController: _workoutController,
                            onStopWorkout: _showStopWorkoutDialog,
                            onSkipSegment: () {
                              _arcadeSession.willSkip();
                              _workoutController.skipToNextSegment();
                            },
                          ),
                          preview: _workoutController.segments.isEmpty
                              ? const SizedBox.shrink()
                              : ClassicWorkoutPreview(
                                  segments: _workoutController.segments,
                                  index: _workoutController.segments.indexOf(
                                    _workoutController.currentSegment!,
                                  ),
                                  seconds:
                                      _workoutController.workoutProgressSeconds,
                                  ftp: _workoutController.ftpValue,
                                  endless:
                                      _workoutController.isUnlimitedFreeRide,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showWorkoutLobby)
              Positioned.fill(
                child: WorkoutLobby(
                  name: _workoutController.workoutName ?? 'Your workout',
                  segments: _workoutController.segments,
                  endless: _workoutController.isUnlimitedFreeRide,
                  ftp: _workoutController.ftpValue,
                  onStart: _startingWorkout ? null : _startWorkoutFromLobby,
                  onFtp: (value) {
                    if (_showWorkoutLobby && !_startingWorkout) {
                      unawaited(_workoutController.updateFTP(value));
                    }
                  },
                  onSelect: _selectLobbyWorkout,
                  onBrowse: () => _workoutMenu().showWorkoutLibrary(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
