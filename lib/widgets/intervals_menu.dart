import 'package:flutter/material.dart';

/// Popup menu for workout related actions including Intervals.icu items.
///
/// This extracts the large inline PopupMenuButton from `workout_screen.dart`
/// to keep that file lean. Callbacks are injected so the screen keeps control
/// over behavior without tight coupling.
class IntervalsMenu extends StatelessWidget {
  const IntervalsMenu({
    super.key,
    required this.onImportZwo,
    required this.onIntervalsToday,
    required this.onIntervalsPick,
    required this.onSelectWorkout,
    required this.onDeleteWorkout,
    required this.onAudioCoach,
    required this.onConnectedAccounts,
    required this.onCalibrate,
    required this.onCompletedActivities,
    required this.onWorkoutTextSettings,
  });

  final VoidCallback onImportZwo;
  final VoidCallback onIntervalsToday;
  final VoidCallback onIntervalsPick;
  final VoidCallback onSelectWorkout;
  final VoidCallback onDeleteWorkout;
  final VoidCallback onAudioCoach;
  final VoidCallback onConnectedAccounts;
  final VoidCallback onCalibrate;
  final VoidCallback onCompletedActivities;
  final VoidCallback onWorkoutTextSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'import':
            onImportZwo();
            break;
          case 'intervals_today':
            onIntervalsToday();
            break;
          case 'intervals_pick':
            onIntervalsPick();
            break;
          case 'select':
            onSelectWorkout();
            break;
          case 'delete':
            onDeleteWorkout();
            break;
          case 'audio':
            onAudioCoach();
            break;
          case 'connected_accounts':
            onConnectedAccounts();
            break;
          case 'calibrate':
            onCalibrate();
            break;
          case 'completed_activities':
            onCompletedActivities();
            break;
          case 'workout_text':
            onWorkoutTextSettings();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.file_upload),
              SizedBox(width: 8),
              Text('Import ZWO'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'intervals_today',
          child: Row(
            children: [
              Icon(Icons.calendar_today),
              SizedBox(width: 8),
              Text("Today's Workout (Intervals.icu)"),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'intervals_pick',
          child: Row(
            children: [
              Icon(Icons.cloud_download),
              SizedBox(width: 8),
              Text('Pick from Intervals.icu'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.folder_open),
              SizedBox(width: 8),
              Text('Select Workout'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete),
              SizedBox(width: 8),
              Text('Delete Workout'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'audio',
          child: Row(
            children: [
              Icon(Icons.record_voice_over),
              SizedBox(width: 8),
              Text('Audio Coach'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'connected_accounts',
          child: Row(
            children: [
              Icon(Icons.link),
              SizedBox(width: 8),
              Text('Connected Accounts'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'calibrate',
          child: Row(
            children: [
              Icon(Icons.tune),
              SizedBox(width: 8),
              Text('Calibrate'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'completed_activities',
          child: Row(
            children: [
              Icon(Icons.history),
              SizedBox(width: 8),
              Text('Completed Activities'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'workout_text',
          child: Row(
            children: [
              Icon(Icons.text_fields),
              SizedBox(width: 8),
              Text('Workout Text'),
            ],
          ),
        ),
      ],
    );
  }
}
