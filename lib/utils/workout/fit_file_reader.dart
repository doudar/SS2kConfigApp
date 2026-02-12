import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fit_tool/fit_tool.dart';
import 'package:path_provider/path_provider.dart';
import 'workout_painter.dart';
import 'workout_parser.dart';
import 'workout_storage.dart';

class ActivitySummary {
  final String name;
  final DateTime timestamp;
  final Duration duration;
  final int averagePower;
  final int averageCadence;
  final int averageHeartRate;
  final String filePath;
  final bool isInProgress;

  ActivitySummary({
    required this.name,
    required this.timestamp,
    required this.duration,
    required this.averagePower,
    required this.averageCadence,
    required this.averageHeartRate,
    required this.filePath,
    this.isInProgress = false,
  });
}

class PowerWindow {
  final int durationSeconds;
  final double averagePower;

  PowerWindow({
    required this.durationSeconds,
    required this.averagePower,
  });
}

class WorkoutPowerSeries {
  final List<PowerWindow> windows;
  final int totalDurationSeconds;

  WorkoutPowerSeries({
    required this.windows,
    required this.totalDurationSeconds,
  });
}

class FitFileReader {
  static const int _thumbnailWidth = 120;
  static const int _thumbnailHeight = 70;
  static const int _thumbnailWindowSeconds = 15;

  static Future<List<ActivitySummary>> getCompletedActivities() async {
    final List<ActivitySummary> activities = [];
    
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory workoutsDir = Directory('${appDir.path}${Platform.pathSeparator}workouts');
      
      if (!await workoutsDir.exists()) {
        return activities;
      }

      final List<FileSystemEntity> files = await workoutsDir.list().toList();
      final List<FileSystemEntity> fitFiles = [];
      final List<FileSystemEntity> inProgressFiles = [];
      for (final file in files) {
        if (file.path.toLowerCase().endsWith('.fit')) {
          fitFiles.add(file);
        } else if (_isInProgressFile(file)) {
          inProgressFiles.add(file);
        }
      }

      for (final file in fitFiles) {
        try {
          final bytes = await File(file.path).readAsBytes();
          final fitFile = FitFile.fromBytes(bytes);
          
          int totalPower = 0;
          int totalCadence = 0;
          int totalHeartRate = 0;
          int recordCount = 0;
          DateTime? startTime;
          DateTime? endTime;

          for (final record in fitFile.records) {
            if (record.message is RecordMessage) {
              final recordMessage = record.message as RecordMessage;
              if (recordMessage.power != null) totalPower += recordMessage.power!;
              if (recordMessage.cadence != null) totalCadence += recordMessage.cadence!;
              if (recordMessage.heartRate != null) totalHeartRate += recordMessage.heartRate!;
              recordCount++;
            } else if (record.message is SessionMessage) {
              final session = record.message as SessionMessage;
              startTime = DateTime.fromMillisecondsSinceEpoch(session.startTime!);
              endTime = DateTime.fromMillisecondsSinceEpoch(session.timestamp!);
            }
          }

          if (recordCount > 0 && startTime != null && endTime != null) {
            activities.add(ActivitySummary(
              name: file.path.split(Platform.pathSeparator).last.replaceAll('.fit', ''),
              timestamp: startTime,
              duration: endTime.difference(startTime),
              averagePower: totalPower ~/ recordCount,
              averageCadence: totalCadence ~/ recordCount,
              averageHeartRate: totalHeartRate ~/ recordCount,
              filePath: file.path,
            ));
          }
        } catch (e) {
          print('Error reading FIT file ${file.path}: $e');
        }
      }

      for (final file in inProgressFiles) {
        try {
          final summary = await _readInProgressSummary(File(file.path));
          if (summary != null) {
            activities.add(summary);
          }
        } catch (e) {
          print('Error reading in-progress workout ${file.path}: $e');
        }
      }

      // Sort activities by date, most recent first
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return activities;
    } catch (e) {
      print('Error reading completed activities: $e');
      return activities;
    }
  }

  static bool _isInProgressFile(FileSystemEntity entity) {
    final fileName = entity.path.split(Platform.pathSeparator).last.toLowerCase();
    return fileName.startsWith('workout_in_progress_') && fileName.endsWith('.jsonl');
  }

  static Future<ActivitySummary?> _readInProgressSummary(File file) async {
    final lines = await file.readAsLines();
    String? name;
    DateTime? startTime;
    DateTime? endTime;
    int totalPower = 0;
    int totalCadence = 0;
    int totalHeartRate = 0;
    int recordCount = 0;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final data = jsonDecode(line);
      if (data is! Map<String, dynamic>) continue;
      final type = data['type'];
      if (type == 'metadata') {
        name = data['workoutName'] as String?;
        final start = data['startTime'] as String?;
        if (start != null) {
          startTime = DateTime.tryParse(start);
        }
      } else if (type == 'trackPoint') {
        final timestamp = DateTime.tryParse(data['timestamp'] as String? ?? '');
        if (timestamp != null) {
          startTime ??= timestamp;
          endTime = timestamp;
        }
        totalPower += (data['power'] as num?)?.toInt() ?? 0;
        totalCadence += (data['cadence'] as num?)?.toInt() ?? 0;
        totalHeartRate += (data['heartRate'] as num?)?.toInt() ?? 0;
        recordCount++;
      }
    }

    if (startTime == null) {
      return null;
    }

    Duration duration = endTime != null ? endTime.difference(startTime) : Duration.zero;
    final savedInProgressPath = await WorkoutStorage.loadInProgressFilePath();
    if (savedInProgressPath == file.path) {
      final savedState = await WorkoutStorage.loadWorkoutState();
      final savedWorkoutProgress = savedState['workoutProgressTime'];
      if (savedWorkoutProgress is num) {
        final seconds = savedWorkoutProgress.round();
        if (seconds > 0) {
          duration = Duration(seconds: seconds);
        }
      }
    }
    final hasRecords = recordCount > 0;
    final averagePower = hasRecords ? totalPower ~/ recordCount : 0;
    final averageCadence = hasRecords ? totalCadence ~/ recordCount : 0;
    final averageHeartRate = hasRecords ? totalHeartRate ~/ recordCount : 0;
    const fallbackName = 'Unnamed Workout';

    return ActivitySummary(
      name: name ?? fallbackName,
      timestamp: startTime,
      duration: duration,
      averagePower: averagePower,
      averageCadence: averageCadence,
      averageHeartRate: averageHeartRate,
      filePath: file.path,
      isInProgress: true,
    );
  }

  static Future<File?> getOrGenerateWorkoutThumbnail(String fitFilePath) async {
    final thumbPath = await _getWorkoutThumbnailPath(fitFilePath);
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      return thumbFile;
    }

    final legacyThumbPath = await _getLegacyThumbnailPath(fitFilePath);
    if (legacyThumbPath != null) {
      final legacyFile = File(legacyThumbPath);
      if (await legacyFile.exists()) {
        await thumbFile.create(recursive: true);
        await legacyFile.copy(thumbFile.path);
        return thumbFile;
      }
    }

    final powerSeries = await _readPowerWindows(fitFilePath, windowSeconds: _thumbnailWindowSeconds);
    if (powerSeries == null || powerSeries.windows.isEmpty) {
      return null;
    }

    final workoutName = _workoutNameFromPath(fitFilePath);
    final zwoContent = _buildZwoFromPowerWindows(workoutName, powerSeries.windows);

    try {
      final parsedWorkout = WorkoutParser.parseZwoFile(zwoContent);
      if (parsedWorkout.segments.isEmpty) {
        return null;
      }

      final totalDuration = parsedWorkout.segments.fold<int>(0, (sum, segment) => sum + segment.duration);
      final maxPower = parsedWorkout.segments.fold<double>(
        0,
        (currentMax, segment) => segment.maxPower > currentMax ? segment.maxPower : currentMax,
      );

      if (totalDuration <= 0 || maxPower <= 0) {
        return null;
      }

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final size = ui.Size(_thumbnailWidth.toDouble(), _thumbnailHeight.toDouble());

      final painter = WorkoutPainter(
        segments: parsedWorkout.segments,
        maxPower: maxPower,
        totalDuration: totalDuration.toDouble(),
        ftpValue: 1.0,
        currentProgress: 0,
        actualPowerPoints: const <int, double>{},
        showLabels: false,
      );

      painter.paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(_thumbnailWidth, _thumbnailHeight);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return null;
      }

      await thumbFile.create(recursive: true);
      await thumbFile.writeAsBytes(byteData.buffer.asUint8List());
      return thumbFile;
    } catch (e) {
      print('Error generating workout thumbnail for $fitFilePath: $e');
      return null;
    }
  }

  static Future<void> deleteWorkoutThumbnail(String fitFilePath) async {
    final thumbPath = await _getWorkoutThumbnailPath(fitFilePath);
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }

    final legacyThumbPath = await _getLegacyThumbnailPath(fitFilePath);
    if (legacyThumbPath != null) {
      final legacyFile = File(legacyThumbPath);
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    }
  }

  static Future<String> _getWorkoutThumbnailPath(String fitFilePath) async {
    final parentDir = File(fitFilePath).parent;
    final workoutName = _workoutNameFromPath(fitFilePath);
    return '${parentDir.path}${Platform.pathSeparator}$workoutName.png';
  }

  static Future<String?> _getLegacyThumbnailPath(String fitFilePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final workoutsDir = Directory('${appDir.path}${Platform.pathSeparator}workouts');
      final thumbsDir = Directory('${workoutsDir.path}${Platform.pathSeparator}thumbs');
      final workoutName = _workoutNameFromPath(fitFilePath);
      return '${thumbsDir.path}${Platform.pathSeparator}$workoutName.png';
    } catch (_) {
      return null;
    }
  }

  static String _workoutNameFromPath(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    return fileName.replaceAll(RegExp(r'\.fit$', caseSensitive: false), '');
  }

  static String _buildZwoFromPowerWindows(String workoutName, List<PowerWindow> windows) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<workout_file>');
    buffer.writeln('<name>${_escapeXml(workoutName)}</name>');
    buffer.writeln('<workout>');
    for (final window in windows) {
      final powerValue = window.averagePower.isFinite ? window.averagePower : 0;
      buffer.writeln(
        '  <SteadyState Duration="${window.durationSeconds}" Power="${powerValue.toStringAsFixed(0)}" />',
      );
    }
    buffer.writeln('</workout>');
    buffer.writeln('</workout_file>');
    return buffer.toString();
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static Future<WorkoutPowerSeries?> _readPowerWindows(
    String fitFilePath, {
    int windowSeconds = 15,
  }) async {
    try {
      final bytes = await File(fitFilePath).readAsBytes();
      final fitFile = FitFile.fromBytes(bytes);

      final powerSums = <int, double>{};
      final powerCounts = <int, int>{};
      int? firstTimestamp;
      int? lastTimestamp;

      for (final record in fitFile.records) {
        if (record.message is! RecordMessage) {
          continue;
        }
        final recordMessage = record.message as RecordMessage;
        final power = recordMessage.power;
        if (power == null) {
          continue;
        }

        int? timestamp = recordMessage.timestamp;
        if (timestamp == null) {
          timestamp = (lastTimestamp ?? 0) + 1000;
        }

        firstTimestamp ??= timestamp;
        lastTimestamp = timestamp;

        final offsetSeconds = ((timestamp - firstTimestamp) / 1000).floor();
        final binIndex = (offsetSeconds / windowSeconds).floor();

        powerSums[binIndex] = (powerSums[binIndex] ?? 0) + power.toDouble();
        powerCounts[binIndex] = (powerCounts[binIndex] ?? 0) + 1;
      }

      if (firstTimestamp == null || lastTimestamp == null) {
        return null;
      }

        final computedSeconds = ((lastTimestamp - firstTimestamp) / 1000).ceil();
        final totalDurationSeconds = computedSeconds > 0 ? computedSeconds : 1;
      final maxBinIndex = (totalDurationSeconds / windowSeconds).ceil() - 1;
      final windows = <PowerWindow>[];

      for (int binIndex = 0; binIndex <= maxBinIndex; binIndex++) {
        final count = powerCounts[binIndex] ?? 0;
        final sum = powerSums[binIndex] ?? 0.0;
        final avg = count > 0 ? sum / count : 0.0;
        final remaining = totalDurationSeconds - (binIndex * windowSeconds);
        final duration = remaining > windowSeconds ? windowSeconds : remaining;

        if (duration > 0) {
          windows.add(PowerWindow(durationSeconds: duration, averagePower: avg));
        }
      }

      return WorkoutPowerSeries(
        windows: windows,
        totalDurationSeconds: totalDurationSeconds,
      );
    } catch (e) {
      print('Error reading power windows from $fitFilePath: $e');
      return null;
    }
  }
}
