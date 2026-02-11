import 'dart:convert';
import 'dart:io';
import 'package:fit_tool/fit_tool.dart';
import 'package:path_provider/path_provider.dart';

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

class FitFileReader {
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

    final duration = endTime != null ? endTime.difference(startTime) : Duration.zero;
    final hasRecords = recordCount > 0;
    final averagePower = hasRecords ? totalPower ~/ recordCount : 0;
    final averageCadence = hasRecords ? totalCadence ~/ recordCount : 0;
    final averageHeartRate = hasRecords ? totalHeartRate ~/ recordCount : 0;
    const fallbackName = 'Workout';

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
}
