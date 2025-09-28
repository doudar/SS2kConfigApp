import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;
import '../bledata.dart';
import '../ftmsControlPoint.dart';
import 'workout_parser.dart';
import 'workout_storage.dart';
import 'sounds.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class TrackPoint {
  final DateTime timestamp;
  final double lat;
  final double lon;
  final double elevation;
  final int heartRate;
  final int cadence;
  final int power;
  final double speed; // Speed in m/s

  TrackPoint({
    required this.timestamp,
    required this.lat,
    required this.lon,
    required this.elevation,
    required this.heartRate,
    required this.cadence,
    required this.power,
    required this.speed,
  });
}

class WorkoutController extends ChangeNotifier {
  // Static map to store device-specific controllers
  static final Map<String, WorkoutController> _instances = {};
  bool _isDisposed = false;

  List<WorkoutSegment> segments = [];
  String? workoutName;
  double maxPower = 0;
  double totalDuration = 0;
  double ftpValue = 200; // Default FTP value
  bool isPlaying = false;
  double progressPosition = 0;
  Timer? progressTimer;
  Map<int, double> actualPowerPoints = {}; // Map time index to power value
  int elapsedSeconds = 0;
  double _previouslyElapsedTime = 0; // Store elapsed time from previous segments
  double _workoutProgressTime = 0; // Track workout's intended progress position
  int currentSegmentTimeRemaining = 0;
  final BLEData bleData;
  final BluetoothDevice device;
  bool _isCountingDown = false;
  String? _currentWorkoutContent;
  double _totalDistance = 0; // Track total distance in meters
  double _lastAltitude = 100.0; // Starting altitude in meters
  double _totalAscent = 0; // Track total ascent in meters

  // Store track points during workout
  final List<TrackPoint> trackPoints = [];
  DateTime? _workoutStartTime;
  DateTime? _lastTrackPointTime;

  // Factory constructor to get device-specific instance
  factory WorkoutController(BLEData bleData, BluetoothDevice device) {
    final deviceId = device.remoteId.str;
    if (!_instances.containsKey(deviceId)) {
      _instances[deviceId] = WorkoutController._internal(bleData, device);
    }
    return _instances[deviceId]!;
  }

  WorkoutController._internal(this.bleData, this.device) {
    _resetSimulationParameters();
    _initializeController();
  }

  // Override dispose to only mark as disposed
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  // Method to cleanup when completely done with a device
  void cleanup() {
    progressTimer?.cancel();
    final deviceId = device.remoteId.str;
    _instances.remove(deviceId);
    super.dispose();
  }

  // Getter for speed calculation
  double get speedMph {
    if (!isPlaying) return 0.0;
    final currentPower = bleData.ftmsData.watts.toDouble();
    return currentPower > 0 ? 2.418 * math.pow(currentPower, 0.394) : 0.0;
  }

  Future<void> _initializeController() async {
    // Load saved FTP value
    ftpValue = await WorkoutStorage.loadFTP();

    // Load saved workout state
    final savedState = await WorkoutStorage.loadWorkoutState();
    final workoutContent = savedState['workoutContent'] as String?;

    if (workoutContent != null) {
      // Load the saved workout
      loadWorkout(workoutContent, isResume: true);

      // Restore progress
      final savedProgress = savedState['progressPosition'];
      if (savedProgress is num) {
        progressPosition = savedProgress.toDouble();
      }
      final savedElapsed = savedState['elapsedSeconds'];
      if (savedElapsed is num) {
        elapsedSeconds = savedElapsed.toInt();
      }
      final savedWorkoutProgress = savedState['_workoutProgressTime'];
      if (savedWorkoutProgress is num) {
        _workoutProgressTime = savedWorkoutProgress.toDouble();
      }

      // Resume if it was playing
  if (savedState['wasPlaying'] == true) {
        isPlaying = true;
        startProgress();
      }
    }
  }

  WorkoutSegment? get currentSegment {
    if (segments.isEmpty) return null;
    int totalTime = 0;
    for (var segment in segments) {
      totalTime += segment.duration;
      if (totalTime > _workoutProgressTime.round()) {
        return segment;
      }
    }
    return segments.last;
  }

  int get currentSegmentElapsedSeconds {
    if (segments.isEmpty) return 0;
    int totalTime = 0;
    for (var segment in segments) {
      if (totalTime + segment.duration > _workoutProgressTime.round()) {
        return _workoutProgressTime.round() - totalTime;
      }
      totalTime += segment.duration;
    }
    return 0;
  }

  // Helper method to reset simulation parameters
  Future<void> _resetSimulationParameters() async {
    if (bleData.ftmsControlPointCharacteristic != null) {
      try {
        await FTMSControlPoint.writeIndoorBikeSimulation(
          bleData.ftmsControlPointCharacteristic!,
          windSpeed: 0,
          grade: 0,
          crr: 0,
          cw: 0,
        );
      } catch (e) {
        print('Error resetting simulation parameters: $e');
      }
    }
  }

  Future<void> togglePlayPause() async {
    // For iOS, ensure we reset simulation parameters before starting
    if (Platform.isIOS && !isPlaying) {
      // Try resetting parameters up to 3 times before starting
      for (int i = 0; i < 3; i++) {
        try {
          await _resetSimulationParameters();
          // Add a small delay to ensure parameters are reset
          await Future.delayed(const Duration(milliseconds: 100));
          break; // Break if successful
        } catch (e) {
          print('Error resetting simulation parameters (attempt ${i + 1}): $e');
          if (i == 2) {
            // Last attempt failed
            if (!_isDisposed) {
              notifyListeners(); // Notify to update UI if needed
            }
            return; // Don't proceed with starting the workout
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    if (isPlaying) {
      // Save current elapsed time before pausing
      if (_workoutStartTime != null) {
        final currentTime = DateTime.now();
        final currentSegmentTime = currentTime.difference(_workoutStartTime!).inMilliseconds / 1000.0;
        _previouslyElapsedTime += currentSegmentTime;
      }
      progressTimer?.cancel();
      // Reset simulation parameters when stopping
      _resetSimulationParameters();
    } else {
      // Only reset these values if we're at the start of the workout
      if (progressPosition == 0) {
        _totalDistance = 0;
        _lastAltitude = 100.0;
        _totalAscent = 0;
        actualPowerPoints = {};
        elapsedSeconds = 0;
        trackPoints.clear();
        _previouslyElapsedTime = 0;
        _workoutProgressTime = 0;
      }
      _workoutStartTime = DateTime.now();
      // Update target power immediately when resuming
      _updateTargetPower();
      startProgress();
    }
    isPlaying = !isPlaying;
    _saveWorkoutState();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> stopWorkout() async {
    isPlaying = false;
    progressTimer?.cancel();
    _resetSimulationParameters();
    _saveWorkoutState();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void skipToNextSegment() {
    if (segments.isEmpty || !isPlaying) return;

    double segmentStartTime = 0;

    for (int i = 0; i < segments.length; i++) {
      if (_workoutProgressTime >= segmentStartTime && _workoutProgressTime < segmentStartTime + segments[i].duration) {
        // If this is the last segment, stop the workout
        if (i == segments.length - 1) {
          progressPosition = 1.0;
          _previouslyElapsedTime = totalDuration;
          isPlaying = false;
          progressTimer?.cancel();
          // Play workout end sound and reset simulation parameters
          workoutSoundGenerator.workoutEndSound();
          _resetSimulationParameters();
          _saveWorkoutState();
          if (!_isDisposed) {
            notifyListeners();
          }
          return;
        }

        // Skip to the start of the next segment
        // Keep track of actual elapsed time
        double currentSegmentElapsedTime = _workoutProgressTime - segmentStartTime;
        _previouslyElapsedTime += currentSegmentElapsedTime;

        // Calculate the start time of the next segment
        double nextSegmentStart = segmentStartTime + segments[i].duration;

        // Update power history for skipped time
        final currentTime = _workoutProgressTime.round();
        final skippedTime = (nextSegmentStart - _workoutProgressTime).round();

        actualPowerPoints[currentTime + 1] = 0;
        actualPowerPoints[currentTime + skippedTime - 1] = 0;

        // Set workout progress to the start of next segment
        _workoutProgressTime = nextSegmentStart;
        progressPosition = _workoutProgressTime / totalDuration;

        // Reset the start time for the new segment
        _workoutStartTime = DateTime.now();
        _saveWorkoutState();
        if (!_isDisposed) {
          notifyListeners();
        }
        return;
      }
      segmentStartTime += segments[i].duration;
    }
  }

  void loadWorkout(String xmlContent, {bool isResume = false}) {
    try {
      final workoutData = WorkoutParser.parseZwoFile(xmlContent);

      double maxPowerTemp = 0;
      double totalDurationTemp = 0;

      for (var segment in workoutData.segments) {
        if (segment.isRamp) {
          maxPowerTemp =
              [maxPowerTemp, segment.powerLow, segment.powerHigh].reduce((curr, next) => curr > next ? curr : next);
        } else {
          maxPowerTemp = [maxPowerTemp, segment.powerLow].reduce((curr, next) => curr > next ? curr : next);
        }
        totalDurationTemp += segment.duration;
      }

      maxPowerTemp *= 1.1;

      segments = workoutData.segments;
      workoutName = workoutData.name;
      maxPower = maxPowerTemp;
      totalDuration = totalDurationTemp;

      // Only reset these values if it's not a resume
      if (!isResume) {
        progressPosition = 0;
        actualPowerPoints = {};
        elapsedSeconds = 0;
        _totalDistance = 0;
        _lastAltitude = 100.0;
        _totalAscent = 0;
        _previouslyElapsedTime = 0;
        _workoutProgressTime = 0;
        isPlaying = false; // Ensure workout starts in stopped state for fresh loads
      }

      _currentWorkoutContent = xmlContent;

      // Reset simulation parameters when loading new workout
      _resetSimulationParameters();

      _saveWorkoutState();
      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  void _updateTargetPower() {
    if (segments.isEmpty) return;

    double currentTime = progressPosition * totalDuration;
    double elapsedTime = 0;

    for (var segment in segments) {
      if (currentTime >= elapsedTime && currentTime < elapsedTime + segment.duration) {
        double segmentProgress = (currentTime - elapsedTime) / segment.duration;
        double targetPower;

        if (segment.isRamp) {
          if (segment.type == SegmentType.cooldown) {
            // For cooldowns, start at powerHigh and decrease to powerLow
            targetPower = segment.powerHigh - (segment.powerHigh - segment.powerLow) * segmentProgress;
          } else {
            // For all other ramps, start at powerLow and increase to powerHigh
            targetPower = segment.powerLow + (segment.powerHigh - segment.powerLow) * segmentProgress;
          }
        } else {
          targetPower = segment.powerLow;
        }

        // Calculate target power in watts and update ftmsData
        // When target power is 0, the BLEData class will handle switching to simulation mode
        bleData.ftmsData.targetERG = (targetPower * ftpValue).round();
        currentSegmentTimeRemaining = ((elapsedTime + segment.duration) - currentTime).round();

        _handleSegmentCountdown(currentSegmentTimeRemaining);
        break;
      }
      elapsedTime += segment.duration;
    }
  }

  void startProgress() {
    progressTimer?.cancel();

    // Only initialize these if we're at the start of the workout
    if (progressPosition == 0) {
      _workoutStartTime = DateTime.now();
      _lastTrackPointTime = _workoutStartTime;
      trackPoints.clear();
    }

    progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isDisposed || !isPlaying) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final currentSegmentTime = now.difference(_workoutStartTime!).inMilliseconds / 1000.0;
      final totalElapsedTime = _previouslyElapsedTime + currentSegmentTime;

      // Update actual elapsed time
      elapsedSeconds = totalElapsedTime.round();

      // Update workout progress time
      _workoutProgressTime += 0.1; // Increment by 100ms
      progressPosition = _workoutProgressTime / totalDuration;

      // Store power value at current time index
      final currentPower = bleData.ftmsData.watts.toDouble();
      actualPowerPoints[_workoutProgressTime.round()] = currentPower;

      // Calculate speed (m/s) from power
      double speedMps = speedMph * 0.44704; // Convert mph to m/s

      // Update total distance (in meters)
      _totalDistance += speedMps * 0.1; // 0.1 seconds worth of distance

      // Simulate altitude changes based on power output
      double newAltitude = 100.0 + (currentPower / 400.0) * math.sin(elapsedSeconds / 10.0);
      if (newAltitude > _lastAltitude) {
        _totalAscent += newAltitude - _lastAltitude;
      }
      _lastAltitude = newAltitude;

      // Store track point every second
      if (_lastTrackPointTime == null || now.difference(_lastTrackPointTime!) >= const Duration(seconds: 1)) {
        trackPoints.add(TrackPoint(
          timestamp: now,
          lat: 44.8113, // Eau Claire center - this will be updated by GPX exporter to create bike shape
          lon: -91.4985,
          elevation: _lastAltitude,
          heartRate: bleData.ftmsData.heartRate,
          cadence: bleData.ftmsData.cadence,
          power: bleData.ftmsData.watts,
          speed: speedMps,
        ));
        _lastTrackPointTime = now;
      }

      if (progressPosition >= 1.0) {
        //progressPosition = 0; we will reset the progress position in the workout_screen.dart so that the save file dialog triggers correctly.
        isPlaying = false;
        timer.cancel();
        // Play workout end sound and reset simulation parameters
        if (!_isDisposed) {
          workoutSoundGenerator.workoutEndSound();
          _resetSimulationParameters();
        }
        _saveWorkoutState();
        if (!_isDisposed) {
          notifyListeners();
        }
        return;
      }

      // Update target watts and remaining time based on current position
      _updateTargetPower();

      _saveWorkoutState();
      if (!_isDisposed) {
        notifyListeners();
      }
    });
  }

  void _handleSegmentCountdown(int timeRemaining) {
    if (!isPlaying) return; // Don't play sounds if workout isn't active

    if (timeRemaining <= 3 && timeRemaining > 0 && !_isCountingDown) {
      _isCountingDown = true;
      workoutSoundGenerator.intervalCountdownSound();
    } else if (timeRemaining > 3) {
      _isCountingDown = false;
    }
  }

  Future<void> _saveWorkoutState() async {
    await WorkoutStorage.saveWorkoutState(
      workoutContent: _currentWorkoutContent,
      progressPosition: progressPosition,
      elapsedSeconds: elapsedSeconds,
      workoutProgressTime: _workoutProgressTime,
      isPlaying: isPlaying,
    );
  }

  // Get power points as a list up to current time
  List<double> getPowerPointsUpToNow() {
    final maxSeconds = _workoutProgressTime.round();
    List<double> points = List.filled(maxSeconds + 1, 0);

    for (int i = 0; i <= maxSeconds; i++) {
      // Use the actual power value if we have it, otherwise interpolate between known points
      if (actualPowerPoints.containsKey(i)) {
        points[i] = actualPowerPoints[i]!;
      } else {
        // Find nearest known points before and after
        int? beforeTime = actualPowerPoints.keys
            .where((time) => time < i)
            .fold<int?>(null, (max, time) => max == null || time > max ? time : max);
        int? afterTime = actualPowerPoints.keys
            .where((time) => time > i)
            .fold<int?>(null, (min, time) => min == null || time < min ? time : min);

        if (beforeTime != null && afterTime != null) {
          // Interpolate between known points
          double beforeValue = actualPowerPoints[beforeTime]!;
          double afterValue = actualPowerPoints[afterTime]!;
          double ratio = (i - beforeTime) / (afterTime - beforeTime);
          points[i] = beforeValue + (afterValue - beforeValue) * ratio;
        } else if (beforeTime != null) {
          // Use last known value
          points[i] = actualPowerPoints[beforeTime]!;
        } else if (afterTime != null) {
          // Use next known value
          points[i] = actualPowerPoints[afterTime]!;
        } else {
          // No known values, use current power
          points[i] = bleData.ftmsData.watts.toDouble();
        }
      }
    }

    return points;
  }

  Future<void> updateFTP(double? newValue) async {
    if (newValue != null) {
      ftpValue = newValue;
      await WorkoutStorage.saveFTP(ftpValue);
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Getters for GPX file generation
  double get totalDistance => _totalDistance;
  double get currentAltitude => _lastAltitude;
  double get totalAscent => _totalAscent;

  // Getter for workout progress time
  double get workoutProgressSeconds => _workoutProgressTime;
}
