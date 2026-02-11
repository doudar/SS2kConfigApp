import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutStorage {
  static const String _ftpKey = 'workout_ftp_value';
  static const String _workoutStateKey = 'workout_state';
  static const String _workoutContentKey = 'workout_content';
  static const String _workoutProgressTime = 'workout_progress_time';
  static const String _skippedTimeKey = 'workout_skipped_time';
  static const String _isPlayingKey = 'workout_is_playing';
  static const String _inProgressFilePathKey = 'workout_in_progress_file_path';
  static const String _savedWorkoutsKey = 'saved_workouts';
  static const String _workoutThumbnailPrefix = 'workout_thumbnail_';
  static const String defaultWorkoutName = "Anthony's Mix";

  // Save FTP value
  static Future<void> saveFTP(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ftpKey, value);
  }

  // Load FTP value
  static Future<double> loadFTP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_ftpKey) ?? 200.0; // Default FTP value
  }

  // Save workout state
  static Future<void> saveWorkoutState({
    required String? workoutContent,
    required double progressPosition,
    required double workoutProgressTime,
    required double skippedTime,
    required bool isPlaying,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (workoutContent != null) {
      await prefs.setString(_workoutContentKey, workoutContent);
    }
    
    final stateJson = jsonEncode({
      'progressPosition': progressPosition,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    await prefs.setString(_workoutStateKey, stateJson);
    await prefs.setDouble(_workoutProgressTime, workoutProgressTime);
    await prefs.setDouble(_skippedTimeKey, skippedTime);
    await prefs.setBool(_isPlayingKey, isPlaying);
  }

  // Load workout state
  static Future<Map<String, dynamic>> loadWorkoutState() async {
    final prefs = await SharedPreferences.getInstance();
    
    final workoutContent = prefs.getString(_workoutContentKey);
    final stateJson = prefs.getString(_workoutStateKey);
    final workoutProgressTime = prefs.getDouble(_workoutProgressTime) ?? 0;
    final skippedTime = prefs.getDouble(_skippedTimeKey) ?? 0;
    final wasPlaying = prefs.getBool(_isPlayingKey) ?? false;
    
    double progressPosition = 0.0;
    
    if (stateJson != null) {
      final state = jsonDecode(stateJson) as Map<String, dynamic>;
      final savedTimestamp = state['timestamp'] as int;
      final savedProgress = state['progressPosition'] as double;
      
      if (wasPlaying) {
        // Calculate time elapsed since last save
        final elapsedMillis = DateTime.now().millisecondsSinceEpoch - savedTimestamp;
        final elapsedMinutes = elapsedMillis / 60000; // Convert to minutes
        
        // Adjust progress based on elapsed time
        progressPosition = savedProgress + (elapsedMinutes / 60); // Assuming workout duration is in seconds
        progressPosition = progressPosition.clamp(0.0, 1.0);
      } else {
        progressPosition = savedProgress;
      }
    }
    
    return {
      'workoutContent': workoutContent,
      'progressPosition': progressPosition,
      'workoutProgressTime': workoutProgressTime,
      'skippedTime': skippedTime,
      'wasPlaying': wasPlaying,
    };
  }

  // Clear workout state
  static Future<void> clearWorkoutState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workoutStateKey);
    await prefs.remove(_workoutContentKey);
    await prefs.remove(_workoutProgressTime);
    await prefs.remove(_skippedTimeKey);
    await prefs.remove(_isPlayingKey);
    await prefs.remove(_inProgressFilePathKey);
  }

  static Future<void> saveInProgressFilePath(String? filePath) async {
    final prefs = await SharedPreferences.getInstance();
    if (filePath == null) {
      await prefs.remove(_inProgressFilePathKey);
    } else {
      await prefs.setString(_inProgressFilePathKey, filePath);
    }
  }

  static Future<String?> loadInProgressFilePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_inProgressFilePathKey);
  }

  // Save a workout to the library
  static Future<void> saveWorkoutToLibrary({
    required String workoutContent,
    required String workoutName,
    required String thumbnailData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get existing workouts
    final workouts = await getSavedWorkouts();
    
    // Add new workout
    workouts.add({
      'name': workoutName,
      'content': workoutContent,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    // Save updated workout list
    await prefs.setString(_savedWorkoutsKey, jsonEncode(workouts));
    
    // Save thumbnail separately (using workout name as key)
    await prefs.setString('$_workoutThumbnailPrefix$workoutName', thumbnailData);
  }

  // Get list of saved workouts
  static Future<List<Map<String, dynamic>>> getSavedWorkouts() async {
    final prefs = await SharedPreferences.getInstance();
    final workoutsJson = prefs.getString(_savedWorkoutsKey);
    
    List<Map<String, dynamic>> workouts = [];
    if (workoutsJson != null) {
      final List<dynamic> decoded = jsonDecode(workoutsJson);
      workouts = decoded.cast<Map<String, dynamic>>();
    }

    // Check if default workout exists in the list
    bool hasDefaultWorkout = workouts.any((workout) => workout['name'] == defaultWorkoutName);

    if (!hasDefaultWorkout) {
      // Load default workout content from assets
      final defaultWorkoutContent = await rootBundle.loadString('assets/Anthonys_Mix.zwo');
      
      // Generate a basic thumbnail string (a placeholder until the actual thumbnail is generated)
      final placeholderThumbnail = base64Encode(utf8.encode('placeholder'));
      
      // Add default workout to the beginning of the list
      workouts.insert(0, {
        'name': defaultWorkoutName,
        'content': defaultWorkoutContent,
        'timestamp': 0, // Use 0 to ensure it stays at the top
      });

      // Save the updated list back to preferences
      await prefs.setString(_savedWorkoutsKey, jsonEncode(workouts));
      
      // Save the placeholder thumbnail
      await prefs.setString('$_workoutThumbnailPrefix$defaultWorkoutName', placeholderThumbnail);
    }
    
    return workouts;
  }

  // Get thumbnail for a workout
  static Future<String?> getWorkoutThumbnail(String workoutName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_workoutThumbnailPrefix$workoutName');
  }

  // Delete a workout from the library
  static Future<void> deleteWorkout(String workoutName) async {
    // Prevent deletion of default workout
    if (workoutName == defaultWorkoutName) return;

    final prefs = await SharedPreferences.getInstance();
    
    // Get existing workouts
    final workouts = await getSavedWorkouts();
    
    // Remove workout with matching name
    workouts.removeWhere((workout) => workout['name'] == workoutName);
    
    // Save updated workout list
    await prefs.setString(_savedWorkoutsKey, jsonEncode(workouts));
    
    // Remove thumbnail
    await prefs.remove('$_workoutThumbnailPrefix$workoutName');
  }

  // Update thumbnail for a workout
  static Future<void> updateWorkoutThumbnail(String workoutName, String thumbnailData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_workoutThumbnailPrefix$workoutName', thumbnailData);
  }
}
