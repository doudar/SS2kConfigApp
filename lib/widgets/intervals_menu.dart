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
          case 'intervals_root':
            _showIntervalsSubMenu(context);
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
          value: 'intervals_root',
          child: Row(
            children: [
              Icon(Icons.hub),
              SizedBox(width: 8),
              Text('Intervals.icu'),
              SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20),
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
              Text('Calibrate Trainer'),
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

  void _showIntervalsSubMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Intervals.icu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text("Today's Workout"),
              onTap: () {
                Navigator.of(ctx).pop();
                onIntervalsToday();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Pick Workout'),
              onTap: () {
                Navigator.of(ctx).pop();
                onIntervalsPick();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }
}
