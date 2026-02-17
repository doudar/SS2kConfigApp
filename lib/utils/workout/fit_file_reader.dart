import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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
  final int? averageHeartRate;
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

class ActivityPageResult {
  final List<ActivitySummary> activities;
  final int nextOffset;
  final bool hasMore;

  ActivityPageResult({
    required this.activities,
    required this.nextOffset,
    required this.hasMore,
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

class _AverageMetrics {
  final int averagePower;
  final int averageCadence;
  final int? averageHeartRate;

  const _AverageMetrics({
    required this.averagePower,
    required this.averageCadence,
    required this.averageHeartRate,
  });
}

class FitFileReader {
  static const int _thumbnailWidth = 120;
  static const int _thumbnailHeight = 70;
  static const int _thumbnailWindowSeconds = 15;

  static Future<ActivityPageResult> getCompletedActivitiesPage({
    required int offset,
    required int limit,
  }) async {
    final List<ActivitySummary> activities = [];

    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory workoutsDir = Directory('${appDir.path}${Platform.pathSeparator}workouts');

      if (!await workoutsDir.exists()) {
        return ActivityPageResult(activities: activities, nextOffset: 0, hasMore: false);
      }

      final files = await workoutsDir.list().toList();
      final fitFiles = files
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.fit'))
          .toList();
      final inProgressFiles = files
          .whereType<File>()
          .where(_isInProgressFile)
          .toList();

      fitFiles.sort((a, b) {
        final aMs = a.statSync().modified.millisecondsSinceEpoch;
        final bMs = b.statSync().modified.millisecondsSinceEpoch;
        return bMs.compareTo(aMs);
      });

      final safeOffset = offset.clamp(0, fitFiles.length);
      final end = (safeOffset + limit).clamp(0, fitFiles.length);
      final pageFiles = fitFiles.sublist(safeOffset, end);

      final pageSummaries = await Future.wait(
        pageFiles.map((file) => _readFitSummaryWithMetadata(file)),
      );
      activities.addAll(pageSummaries.whereType<ActivitySummary>());

      if (safeOffset == 0) {
        for (final file in inProgressFiles) {
          try {
            final summary = await _readInProgressSummary(file);
            if (summary != null) {
              activities.add(summary);
            }
          } catch (e) {
            print('Error reading in-progress workout ${file.path}: $e');
          }
        }
      }

      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return ActivityPageResult(
        activities: activities,
        nextOffset: end,
        hasMore: end < fitFiles.length,
      );
    } catch (e) {
      print('Error reading completed activities: $e');
      return ActivityPageResult(activities: activities, nextOffset: offset, hasMore: false);
    }
  }

  static Future<List<ActivitySummary>> getCompletedActivities() async {
    final activities = <ActivitySummary>[];
    int offset = 0;
    const batchSize = 50;

    while (true) {
      final page = await getCompletedActivitiesPage(offset: offset, limit: batchSize);
      activities.addAll(page.activities);
      if (!page.hasMore) {
        break;
      }
      offset = page.nextOffset;
    }

    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return activities;
  }

  static bool _isInProgressFile(FileSystemEntity entity) {
    final fileName = entity.path.split(Platform.pathSeparator).last.toLowerCase();
    return fileName.startsWith('workout_in_progress_') && fileName.endsWith('.jsonl');
  }

  static Future<ActivitySummary?> _readFitSummaryWithMetadata(File file) async {
    try {
      final metadataFile = File(_getFitMetadataPath(file.path));
      final sourceModifiedMs = (await file.stat()).modified.millisecondsSinceEpoch;

      if (await metadataFile.exists()) {
        final raw = await metadataFile.readAsString();
        final map = jsonDecode(raw);
        if (map is Map<String, dynamic> && map['sourceModifiedMs'] == sourceModifiedMs) {
          final timestamp = DateTime.tryParse(map['timestamp'] as String? ?? '');
          final durationSeconds = map['durationSeconds'];
          final averagePower = map['averagePower'];
          final averageCadence = map['averageCadence'];
          if (timestamp != null && durationSeconds is int && averagePower is int && averageCadence is int) {
            return ActivitySummary(
              name: (map['name'] as String?) ?? _workoutNameFromPath(file.path),
              timestamp: timestamp,
              duration: Duration(seconds: durationSeconds),
              averagePower: averagePower,
              averageCadence: averageCadence,
              averageHeartRate: map['averageHeartRate'] as int?,
              filePath: file.path,
            );
          }
        }
      }

      final parsed = await compute(_parseFitSummaryInBackground, file.path);
      if (parsed == null) {
        return null;
      }

      final timestamp = DateTime.tryParse(parsed['timestamp'] as String? ?? '');
      final durationSeconds = parsed['durationSeconds'];
      final averagePower = parsed['averagePower'];
      final averageCadence = parsed['averageCadence'];
      if (timestamp == null || durationSeconds is! int || averagePower is! int || averageCadence is! int) {
        return null;
      }

      final summary = ActivitySummary(
        name: (parsed['name'] as String?) ?? _workoutNameFromPath(file.path),
        timestamp: timestamp,
        duration: Duration(seconds: durationSeconds),
        averagePower: averagePower,
        averageCadence: averageCadence,
        averageHeartRate: parsed['averageHeartRate'] as int?,
        filePath: file.path,
      );

      final metadata = {
        'name': summary.name,
        'timestamp': summary.timestamp.toIso8601String(),
        'durationSeconds': summary.duration.inSeconds,
        'averagePower': summary.averagePower,
        'averageCadence': summary.averageCadence,
        'averageHeartRate': summary.averageHeartRate,
        'sourceModifiedMs': sourceModifiedMs,
      };
      await metadataFile.writeAsString(jsonEncode(metadata));

      return summary;
    } catch (e) {
      print('Error reading FIT file ${file.path}: $e');
      return null;
    }
  }

  static String _getFitMetadataPath(String fitFilePath) => '$fitFilePath.meta.json';

  static Future<ActivitySummary?> _readInProgressSummary(File file) async {
    final lines = await file.readAsLines();
    String? name;
    DateTime? startTime;
    DateTime? endTime;
    int totalPower = 0;
    int totalCadence = 0;
    int totalHeartRate = 0;
    int powerCount = 0;
    int cadenceCount = 0;
    int heartRateCount = 0;

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
        final power = (data['power'] as num?)?.toInt();
        if (power != null) {
          totalPower += power;
          powerCount++;
        }

        final cadence = (data['cadence'] as num?)?.toInt();
        if (cadence != null) {
          totalCadence += cadence;
          cadenceCount++;
        }

        final heartRate = (data['heartRate'] as num?)?.toInt();
        if (heartRate != null) {
          totalHeartRate += heartRate;
          heartRateCount++;
        }
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
    final averages = _calculateAverageMetrics(
      totalPower: totalPower,
      powerCount: powerCount,
      totalCadence: totalCadence,
      cadenceCount: cadenceCount,
      totalHeartRate: totalHeartRate,
      heartRateCount: heartRateCount,
    );
    const fallbackName = 'Unnamed Workout';

    return ActivitySummary(
      name: name ?? fallbackName,
      timestamp: startTime,
      duration: duration,
      averagePower: averages.averagePower,
      averageCadence: averages.averageCadence,
      averageHeartRate: averages.averageHeartRate,
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

  static Future<void> deleteActivityMetadata(String fitFilePath) async {
    final metadataFile = File(_getFitMetadataPath(fitFilePath));
    if (await metadataFile.exists()) {
      await metadataFile.delete();
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

  static _AverageMetrics _calculateAverageMetrics({
    required int totalPower,
    required int powerCount,
    required int totalCadence,
    required int cadenceCount,
    required int totalHeartRate,
    required int heartRateCount,
  }) {
    final averagePower = powerCount > 0 ? (totalPower ~/ powerCount) : 0;
    final averageCadence = cadenceCount > 0 ? (totalCadence ~/ cadenceCount) : 0;
    final averageHeartRate = heartRateCount > 0 ? (totalHeartRate ~/ heartRateCount) : null;

    return _AverageMetrics(
      averagePower: averagePower,
      averageCadence: averageCadence,
      averageHeartRate: averageHeartRate,
    );
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

Map<String, dynamic>? _parseFitSummaryInBackground(String filePath) {
  try {
    final bytes = File(filePath).readAsBytesSync();
    final fitFile = FitFile.fromBytes(bytes);

    int totalPower = 0;
    int totalCadence = 0;
    int totalHeartRate = 0;
    int powerCount = 0;
    int cadenceCount = 0;
    int heartRateCount = 0;
    DateTime? startTime;
    DateTime? endTime;

    for (final record in fitFile.records) {
      if (record.message is RecordMessage) {
        final msg = record.message as RecordMessage;
        if (msg.power != null) {
          totalPower += msg.power!;
          powerCount++;
        }
        if (msg.cadence != null) {
          totalCadence += msg.cadence!;
          cadenceCount++;
        }
        if (msg.heartRate != null) {
          totalHeartRate += msg.heartRate!;
          heartRateCount++;
        }
      } else if (record.message is SessionMessage) {
        final session = record.message as SessionMessage;
        if (session.startTime != null) {
          startTime = DateTime.fromMillisecondsSinceEpoch(session.startTime!);
        }
        if (session.timestamp != null) {
          endTime = DateTime.fromMillisecondsSinceEpoch(session.timestamp!);
        }
      }
    }

    if (startTime == null || endTime == null) {
      return null;
    }

    final durationSeconds = endTime.difference(startTime).inSeconds;
    final averages = FitFileReader._calculateAverageMetrics(
      totalPower: totalPower,
      powerCount: powerCount,
      totalCadence: totalCadence,
      cadenceCount: cadenceCount,
      totalHeartRate: totalHeartRate,
      heartRateCount: heartRateCount,
    );

    return {
      'name': filePath.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.fit$', caseSensitive: false), ''),
      'timestamp': startTime.toIso8601String(),
      'durationSeconds': durationSeconds > 0 ? durationSeconds : 1,
      'averagePower': averages.averagePower,
      'averageCadence': averages.averageCadence,
      'averageHeartRate': averages.averageHeartRate,
    };
  } catch (_) {
    return null;
  }
}
