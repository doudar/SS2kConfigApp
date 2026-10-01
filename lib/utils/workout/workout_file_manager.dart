import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'workout_storage.dart';
import 'workout_controller.dart';
import 'workout_parser.dart';

class WorkoutFileManager {
  static Future<void> pickAndLoadWorkout({
    required BuildContext context,
    required WorkoutController workoutController,
    Future<bool> Function()? onBeforeLoad,
    required Function(String) onWorkoutLoaded,
  }) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);

      if (file != null) {
        final content = utf8.decode(await file.readAsBytes());

        if (!content.trim().contains('<workout_file>')) {
          throw Exception(
            'Invalid workout file format. Expected .zwo file content.',
          );
        }

        // Parse the workout data first
        final workoutData = WorkoutParser.parseZwoFile(content);
        if (workoutData.name == null || workoutData.name!.isEmpty) {
          throw Exception('Invalid workout file: Missing workout name');
        }

        // Check if a workout with this name already exists
        final existingWorkouts = await WorkoutStorage.getSavedWorkouts();
        if (existingWorkouts.any((w) => w['name'] == workoutData.name)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'A workout named "${workoutData.name}" already exists',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        if (onBeforeLoad != null) {
          final shouldLoad = await onBeforeLoad();
          if (!shouldLoad) {
            return;
          }
        }

        // Load the workout to generate the graph, ensuring it starts in stopped state
        workoutController.loadWorkout(content, isResume: false);
        onWorkoutLoaded(content);

        // Render the same compact profile as every other library entry.
        final thumbnail = await WorkoutStorage.getOrGenerateWorkoutThumbnail(
          workoutName: workoutData.name!,
          workoutContent: content,
        );
        if (thumbnail == null) {
          throw Exception('Failed to generate workout thumbnail');
        }

        // Save to library
        await WorkoutStorage.saveWorkoutToLibrary(
          workoutContent: content,
          workoutName: workoutData.name!,
          thumbnailData: thumbnail,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Workout imported successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading workout file: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
