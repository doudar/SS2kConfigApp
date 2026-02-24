import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math show sqrt, max;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
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

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'lat': lat,
      'lon': lon,
      'elevation': elevation,
      'heartRate': heartRate,
      'cadence': cadence,
      'power': power,
      'speed': speed,
    };
  }

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    return TrackPoint(
      timestamp: DateTime.parse(json['timestamp'] as String),
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      elevation: (json['elevation'] as num).toDouble(),
      heartRate: (json['heartRate'] as num).toInt(),
      cadence: (json['cadence'] as num).toInt(),
      power: (json['power'] as num).toInt(),
      speed: (json['speed'] as num).toDouble(),
    );
  }
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
  Map<int, int> actualHrPoints = {}; // Map time index to HR value
  Map<int, int> actualCadencePoints = {}; // Map time index to Cadence value
  final List<double> _powerPointsList = [];
  final List<double> _hrPointsList = [];
  final List<double> _cadencePointsList = [];
  double _workoutProgressTime = 0; // Track workout's progress position (authoritative source for duration/elapsed time)
  double _skippedTime = 0; // Time skipped by user actions; excluded from elapsed
  int currentSegmentTimeRemaining = 0;
  final BLEData bleData;
  final BluetoothDevice device;
  bool _isCountingDown = false;
  String? _currentWorkoutContent;
  double _totalDistance = 0; // Track total distance in meters
  double _lastAltitude = 100.0; // Starting altitude in meters
  double _totalAscent = 0; // Track total ascent in meters
  bool _isFreeRide = false; // True when workout is entirely free ride segments
  bool _isUnlimitedFreeRide = false; // True when free ride has no predefined end time

  // Store track points during workout
  final List<TrackPoint> trackPoints = [];
  DateTime? _workoutStartTime; // Base timestamp for calculating absolute times
  DateTime? _lastTickTime; // Track last timer tick for accurate drift compensation
  double _lastTrackPointTime = 0; // Last track point time in workout progress seconds
  int _lastRecordedSecond = -1; // Track last whole-second data point recorded
  String? _inProgressFilePath;
  bool _isWritingInProgress = false;
  DateTime? _lastWorkoutStateSave;
  static const int _flushIntervalTrackPoints = 60; // track points recorded ~once/sec in startProgress before flushing
  static const Duration _workoutStateSaveInterval = Duration(seconds: 30);

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
    return currentPower > 0 ? 1.5 * math.sqrt(currentPower) : 0.0;
  }

  Future<void> _initializeController() async {
    // Load saved FTP value
    ftpValue = await WorkoutStorage.loadFTP();

    // Load saved workout state
    final savedState = await WorkoutStorage.loadWorkoutState();
    _inProgressFilePath = await WorkoutStorage.loadInProgressFilePath();
    if (_inProgressFilePath != null) {
      final inProgressFile = File(_inProgressFilePath!);
      if (!await inProgressFile.exists()) {
        _inProgressFilePath = null;
        await WorkoutStorage.saveInProgressFilePath(null);
      }
    }
    final workoutContent = savedState['workoutContent'] as String?;

    if (workoutContent != null) {
      // Load the saved workout
      loadWorkout(workoutContent, isResume: true);

      // Restore progress
      final savedProgress = savedState['progressPosition'];
      if (savedProgress is num) {
        progressPosition = savedProgress.toDouble();
      }
      final savedWorkoutProgress = savedState['workoutProgressTime'];
      if (savedWorkoutProgress is num) {
        _workoutProgressTime = savedWorkoutProgress.toDouble();
      }
      final savedSkippedTime = savedState['skippedTime'];
      if (savedSkippedTime is num) {
        _skippedTime = savedSkippedTime.toDouble();
      }

      // Ensure unlimited free rides cover restored progress
      _ensureFreeRideDuration();
      if (_isUnlimitedFreeRide && totalDuration > 0) {
        progressPosition = _workoutProgressTime / totalDuration;
      }

      // Do not auto-resume on app launch; wait for explicit user action.
      isPlaying = false;
    }
  }

  Future<bool> restoreSavedWorkoutState({bool autoPlay = false}) async {
    final savedState = await WorkoutStorage.loadWorkoutState();
    final workoutContent = savedState['workoutContent'] as String?;
    if (workoutContent == null) {
      return false;
    }

    _inProgressFilePath = await WorkoutStorage.loadInProgressFilePath();
    if (_inProgressFilePath != null) {
      final inProgressFile = File(_inProgressFilePath!);
      if (!await inProgressFile.exists()) {
        _inProgressFilePath = null;
        await WorkoutStorage.saveInProgressFilePath(null);
      }
    }

    isPlaying = false;
    loadWorkout(workoutContent, isResume: true);

    final savedProgress = savedState['progressPosition'];
    if (savedProgress is num) {
      progressPosition = savedProgress.toDouble();
    }
    final savedWorkoutProgress = savedState['workoutProgressTime'];
    if (savedWorkoutProgress is num) {
      _workoutProgressTime = savedWorkoutProgress.toDouble();
    }
    final savedSkippedTime = savedState['skippedTime'];
    if (savedSkippedTime is num) {
      _skippedTime = savedSkippedTime.toDouble();
    }

    // Ensure unlimited free rides cover restored progress
    _ensureFreeRideDuration();
    if (_isUnlimitedFreeRide && totalDuration > 0) {
      progressPosition = _workoutProgressTime / totalDuration;
    }

    if (autoPlay) {
      isPlaying = true;
      await _prepareInProgressFile();
      startProgress();
    }

    _saveWorkoutState();
    if (!_isDisposed) {
      notifyListeners();
    }

    return true;
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

  Future<void> _prepareInProgressFile() async {
    if (progressPosition == 0 && _inProgressFilePath != null) {
      await clearInProgressFile();
    }
    await _ensureInProgressFile();
  }

  Future<File> _ensureInProgressFile() async {
    if (_inProgressFilePath != null) {
      final file = File(_inProgressFilePath!);
      if (await file.exists()) {
        return file;
      }
    }

    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory workoutsDir = Directory('${appDir.path}${Platform.pathSeparator}workouts');
    if (!await workoutsDir.exists()) {
      await workoutsDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final filePath = '${workoutsDir.path}${Platform.pathSeparator}workout_in_progress_$timestamp.jsonl';
    final inProgressFile = File(filePath);
    final metadata = {
      'type': 'metadata',
      'workoutName': workoutName ?? 'Unnamed Workout',
      'startTime': (_workoutStartTime ?? DateTime.now()).toIso8601String(),
    };

    await inProgressFile.writeAsString('${jsonEncode(metadata)}\n', mode: FileMode.write);
    _inProgressFilePath = filePath;
    await WorkoutStorage.saveInProgressFilePath(filePath);
    return inProgressFile;
  }

  Future<void> _appendTrackPointsToInProgressFile(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final file = await _ensureInProgressFile();
    final sink = file.openWrite(mode: FileMode.append);
    for (final point in points) {
      final payload = point.toJson()..['type'] = 'trackPoint';
      sink.writeln(jsonEncode(payload));
    }
    await sink.flush();
    await sink.close();
  }

  List<TrackPoint> _snapshotTrackPoints() {
    // TrackPoint is immutable, so a shallow copy is sufficient.
    return List<TrackPoint>.from(trackPoints);
  }

  void _removeFirstTrackPoints(int count) {
    if (trackPoints.length >= count) {
      trackPoints.removeRange(0, count);
    } else {
      trackPoints.clear();
    }
  }

  List<TrackPoint>? _beginFlush({bool force = false}) {
    if (_isWritingInProgress) return null;
    if (!force && trackPoints.length < _flushIntervalTrackPoints) return null;
    if (trackPoints.isEmpty) return null;

    _isWritingInProgress = true;
    return _snapshotTrackPoints();
  }

  void _scheduleInProgressFlush({bool force = false}) {
    final pointsToWrite = _beginFlush(force: force);
    if (pointsToWrite == null) return;
    _appendTrackPointsToInProgressFile(pointsToWrite).then((_) {
      _removeFirstTrackPoints(pointsToWrite.length);
    }).catchError((e) {
      // Leave points in memory so the next flush can retry.
      print('Error saving in-progress workout: $e');
    }).whenComplete(() {
      _isWritingInProgress = false;
    });
  }

  Future<void> _flushInProgressTrackPoints({bool force = false}) async {
    final pointsToWrite = _beginFlush(force: force);
    if (pointsToWrite == null) return;
    try {
      await _appendTrackPointsToInProgressFile(pointsToWrite);
      _removeFirstTrackPoints(pointsToWrite.length);
    } catch (e) {
      print('Error saving in-progress workout: $e');
    } finally {
      _isWritingInProgress = false;
    }
  }

  Future<List<TrackPoint>> _readInProgressTrackPoints() async {
    if (_inProgressFilePath == null) return [];
    final file = File(_inProgressFilePath!);
    if (!await file.exists()) return [];

    final lines = await file.readAsLines();
    final points = <TrackPoint>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final data = jsonDecode(line);
      if (data is Map<String, dynamic> && data['type'] == 'trackPoint') {
        points.add(TrackPoint.fromJson(data));
      }
    }
    return points;
  }

  Future<List<TrackPoint>> getExportTrackPoints() async {
    final storedPoints = await _readInProgressTrackPoints();
    if (storedPoints.isEmpty) {
      return List<TrackPoint>.from(trackPoints);
    }
    if (trackPoints.isEmpty) {
      return storedPoints;
    }
    // Both lists are appended in time order; merge to preserve sorted timestamps.
    final merged = <TrackPoint>[];
    int storedIndex = 0;
    int memoryIndex = 0;
    while (storedIndex < storedPoints.length && memoryIndex < trackPoints.length) {
      final storedPoint = storedPoints[storedIndex];
      final memoryPoint = trackPoints[memoryIndex];
      if (storedPoint.timestamp.isBefore(memoryPoint.timestamp)) {
        merged.add(storedPoint);
        storedIndex++;
      } else {
        merged.add(memoryPoint);
        memoryIndex++;
      }
    }
    if (storedIndex < storedPoints.length) {
      merged.addAll(storedPoints.sublist(storedIndex));
    }
    if (memoryIndex < trackPoints.length) {
      merged.addAll(trackPoints.sublist(memoryIndex));
    }
    return merged;
  }

  Future<void> clearInProgressFile() async {
    final existingPath = _inProgressFilePath;
    _inProgressFilePath = null;
    await WorkoutStorage.saveInProgressFilePath(null);
    if (existingPath == null) return;

    final file = File(existingPath);
    if (await file.exists()) {
      await file.delete();
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
        trackPoints.clear();
        _workoutProgressTime = 0;
        _lastTrackPointTime = 0;
      }
      // Set workout start time when starting/resuming
      if (_workoutStartTime == null) {
        _workoutStartTime = DateTime.now();
      }
      await _prepareInProgressFile();
      // Update target power immediately when resuming
      _updateTargetPower();
      startProgress();
    }
    isPlaying = !isPlaying;
    _saveWorkoutState(force: true);
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> stopWorkout() async {
    isPlaying = false;
    progressTimer?.cancel();
    _resetSimulationParameters();
    await _flushInProgressTrackPoints(force: true);
    _saveWorkoutState(force: true);
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
          _workoutProgressTime = totalDuration;
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

        // Calculate the start time of the next segment
        double nextSegmentStart = segmentStartTime + segments[i].duration;

        // Update power history for skipped time
        final currentTime = _workoutProgressTime.round();
        final skippedTime = (nextSegmentStart - _workoutProgressTime).round();

        actualPowerPoints[currentTime + 1] = 0;
        actualPowerPoints[currentTime + skippedTime - 1] = 0;

        // Accumulate skipped time so elapsed excludes it
        final double skippedDelta = (nextSegmentStart - _workoutProgressTime).clamp(0, double.infinity);
        _skippedTime += skippedDelta;

        // Set workout progress to the start of next segment
        _workoutProgressTime = nextSegmentStart;
        
        // Advance tracking variables to prevent backfilling of skipped time
        _lastTrackPointTime = _workoutProgressTime;
        _lastRecordedSecond = _workoutProgressTime.floor();

        progressPosition = _workoutProgressTime / totalDuration;

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

      // Detect free ride mode
      final bool allFreeRide = workoutData.segments.isNotEmpty &&
          workoutData.segments.every((s) => s.type == SegmentType.freeRide);
      final bool hasUnlimitedSegment = workoutData.segments.any((s) =>
          s.type == SegmentType.freeRide && s.duration == 0);

      // For unlimited free rides, replace 0-duration segments with initial 1-hour duration
      List<WorkoutSegment> processedSegments;
      if (allFreeRide && hasUnlimitedSegment) {
        processedSegments = workoutData.segments.map((s) {
          if (s.duration == 0) {
            return WorkoutSegment(
              type: s.type,
              duration: 3600, // 1 hour initial duration
              powerLow: s.powerLow,
              powerHigh: s.powerHigh,
              isRamp: s.isRamp,
              repeat: s.repeat,
              onDuration: s.onDuration,
              offDuration: s.offDuration,
              onPower: s.onPower,
              offPower: s.offPower,
              cadence: s.cadence,
              cadenceLow: s.cadenceLow,
              cadenceHigh: s.cadenceHigh,
              textEvents: s.textEvents,
            );
          }
          return s;
        }).toList();
      } else {
        processedSegments = workoutData.segments;
      }

      double maxPowerTemp = 0;
      double totalDurationTemp = 0;

      for (var segment in processedSegments) {
        if (segment.isRamp) {
          maxPowerTemp =
              [maxPowerTemp, segment.powerLow, segment.powerHigh].reduce((curr, next) => curr > next ? curr : next);
        } else {
          maxPowerTemp = [maxPowerTemp, segment.powerLow].reduce((curr, next) => curr > next ? curr : next);
        }
        totalDurationTemp += segment.duration;
      }

      // For free rides, set max power to 3x FTP for a reasonable chart scale
      if (allFreeRide) {
        maxPowerTemp = 3.0;
      }

      maxPowerTemp *= 1.1;

      _isFreeRide = allFreeRide;
      _isUnlimitedFreeRide = allFreeRide && hasUnlimitedSegment;

      segments = processedSegments;
      workoutName = workoutData.name;
      maxPower = maxPowerTemp;
      totalDuration = totalDurationTemp;

      // Only reset these values if it's not a resume
      if (!isResume) {
        progressPosition = 0;
        actualPowerPoints = {};
        actualHrPoints = {};
        actualCadencePoints = {};
        _powerPointsList.clear();
        _hrPointsList.clear();
        _cadencePointsList.clear();
        _totalDistance = 0;
        _lastAltitude = 100.0;
        _totalAscent = 0;
        _workoutProgressTime = 0;
        _skippedTime = 0;
        _lastTrackPointTime = 0;
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

  void resetWorkout() {
    if (_currentWorkoutContent != null) {
      loadWorkout(_currentWorkoutContent!, isResume: false);
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
    _lastTickTime = DateTime.now();

    // Initialize workout start time if not set
    if (_workoutStartTime == null) {
      // For resumed workouts, calculate the effective start time by subtracting progress
      _workoutStartTime = DateTime.now().subtract(
        Duration(milliseconds: (_workoutProgressTime * 1000).round())
      );
    }

    // Only reset track points if we're at the start of the workout
    if (progressPosition == 0) {
      _lastTrackPointTime = 0;
      trackPoints.clear();
    }
    // When starting/resuming, set to one second before current progress so the first timer tick records the current second and avoids a gap
    _lastRecordedSecond = _workoutProgressTime.floor() - 1;

    progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isDisposed || !isPlaying) {
        timer.cancel();
        return;
      }

      // Calculate actual time elapsed since last tick to prevent drift
      final now = DateTime.now();
      final double delta = _lastTickTime != null 
          ? now.difference(_lastTickTime!).inMicroseconds / 1000000.0 
          : 0.1;
      _lastTickTime = now;

      // Update workout progress time based on actual elapsed time
      _workoutProgressTime += delta;
      progressPosition = _workoutProgressTime / totalDuration;

      // Store power value at current time index
      final currentPower = bleData.ftmsData.watts.toDouble();
      final currentHeartRate = bleData.ftmsData.heartRate;
      final currentCadence = bleData.ftmsData.cadence;

      final int currentSecond = _workoutProgressTime.floor();
      final int startSecond = math.max(0, _lastRecordedSecond + 1);
      for (int second = startSecond; second <= currentSecond; second++) {
        actualPowerPoints[second] = currentPower;
        actualHrPoints[second] = currentHeartRate;
        actualCadencePoints[second] = currentCadence;
        _appendPointLists(second, currentPower, currentHeartRate, currentCadence);
      }
      _lastRecordedSecond = currentSecond;

      // Calculate speed (m/s) from power
      double speedMps = speedMph * 0.44704; // Convert mph to m/s

      // Update total distance (in meters) using actual time delta
      _totalDistance += speedMps * delta;

      // Simulate altitude changes based on power output
      double newAltitude = 100.0 + (currentPower / 400.0) * .1;
      if (newAltitude > _lastAltitude) {
        _totalAscent += newAltitude - _lastAltitude;
      }
      _lastAltitude = newAltitude;

      // Store track point every second based on workout progress time
      while (_workoutProgressTime - _lastTrackPointTime >= 1.0) {
        final double nextPointTime = _lastTrackPointTime + 1.0;
        final timestamp = (_workoutStartTime ?? now).add(
          Duration(milliseconds: (nextPointTime * 1000).round()),
        );

        trackPoints.add(TrackPoint(
          timestamp: timestamp,
          lat: 44.8113, // Eau Claire center - this will be updated by GPX exporter to create bike shape
          lon: -91.4985,
          elevation: _lastAltitude,
          heartRate: currentHeartRate,
          cadence: currentCadence,
          power: currentPower.round(),
          speed: speedMps,
        ));
        _lastTrackPointTime = nextPointTime;
      }
 
      _scheduleInProgressFlush();

      // For unlimited free rides, extend duration when approaching the end
      if (_isUnlimitedFreeRide && _workoutProgressTime > totalDuration - 300) {
        _extendFreeRideDuration();
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
        _scheduleInProgressFlush(force: true);
        _saveWorkoutState(force: true);
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

  void _appendPointLists(int second, double power, int heartRate, int cadence) {
    final int targetLength = second + 1;
    if (_powerPointsList.length < targetLength) {
      final double lastPower = _powerPointsList.isNotEmpty ? _powerPointsList.last : power;
      final double lastHr = _hrPointsList.isNotEmpty ? _hrPointsList.last : heartRate.toDouble();
      final double lastCadence =
          _cadencePointsList.isNotEmpty ? _cadencePointsList.last : cadence.toDouble();
      while (_powerPointsList.length < targetLength) {
        _powerPointsList.add(lastPower);
        _hrPointsList.add(lastHr);
        _cadencePointsList.add(lastCadence);
      }
    }

    _powerPointsList[second] = power;
    _hrPointsList[second] = heartRate.toDouble();
    _cadencePointsList[second] = cadence.toDouble();
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

  Future<void> _saveWorkoutState({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastWorkoutStateSave != null) {
      final elapsed = now.difference(_lastWorkoutStateSave!);
      if (elapsed < _workoutStateSaveInterval) {
        return;
      }
    }

    _lastWorkoutStateSave = now;
    await WorkoutStorage.saveWorkoutState(
      workoutContent: _currentWorkoutContent,
      progressPosition: progressPosition,
      workoutProgressTime: _workoutProgressTime,
      skippedTime: _skippedTime,
      isPlaying: isPlaying,
    );
  }

  // Get power points as a list up to current time
  List<double> getPowerPointsUpToNow() {
    return _powerPointsList;
  }

  // Get HR points as a list up to current time
  List<double> getHrPointsUpToNow() {
    return _hrPointsList;
  }

  // Get Cadence points as a list up to current time
  List<double> getCadencePointsUpToNow() {
      return _cadencePointsList;
  }

  /// Extends the last free ride segment by 1 hour.
  void _extendFreeRideDuration() {
    const extensionSeconds = 3600; // Add 1 hour
    for (int i = segments.length - 1; i >= 0; i--) {
      if (segments[i].type == SegmentType.freeRide) {
        final s = segments[i];
        segments[i] = WorkoutSegment(
          type: s.type,
          duration: s.duration + extensionSeconds,
          powerLow: s.powerLow,
          powerHigh: s.powerHigh,
          isRamp: s.isRamp,
          repeat: s.repeat,
          onDuration: s.onDuration,
          offDuration: s.offDuration,
          onPower: s.onPower,
          offPower: s.offPower,
          cadence: s.cadence,
          cadenceLow: s.cadenceLow,
          cadenceHigh: s.cadenceHigh,
          textEvents: s.textEvents,
        );
        totalDuration += extensionSeconds;
        break;
      }
    }
  }

  /// Ensures the free ride duration covers the current progress time.
  void _ensureFreeRideDuration() {
    if (!_isUnlimitedFreeRide) return;
    while (_workoutProgressTime > totalDuration - 300) {
      _extendFreeRideDuration();
    }
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
  
  // Getter for elapsed seconds (based on workout progress time)
  int get elapsedSeconds => (_workoutProgressTime - _skippedTime).clamp(0, double.infinity).round();

  // Free ride getters
  bool get isFreeRide => _isFreeRide;
  bool get isUnlimitedFreeRide => _isUnlimitedFreeRide;

  double? get averagePower {
    if (actualPowerPoints.isEmpty) return null;
    double sum = 0;
    for (final value in actualPowerPoints.values) {
      sum += value;
    }
    return sum / actualPowerPoints.length;
  }

  double? get averageCadence {
    if (actualCadencePoints.isEmpty) return null;
    int sum = 0;
    int count = 0;
    for (final value in actualCadencePoints.values) {
      if (value > 0) {
        sum += value;
        count++;
      }
    }
    if (count == 0) return null;
    return sum / count;
  }

  double? get averageHeartRate {
    if (actualHrPoints.isEmpty) return null;
    int sum = 0;
    int count = 0;
    for (final value in actualHrPoints.values) {
      if (value > 0) {
        sum += value;
        count++;
      }
    }
    if (count == 0) return null;
    return sum / count;
  }
}
