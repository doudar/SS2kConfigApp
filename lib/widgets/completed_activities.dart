import 'package:flutter/material.dart';
import '../utils/workout/fit_file_reader.dart';
import '../services/strava_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class CompletedActivities extends StatelessWidget {
  const CompletedActivities({Key? key}) : super(key: key);

  static void showCompletedActivitiesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: const CompletedActivities(),
        ),
      ),
    );
  }

  Future<void> _showActivityOptions(BuildContext context, ActivitySummary activity) async {
    if (activity.isInProgress) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This workout is still in progress.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final isStravaConnected = await StravaService.isAuthenticated();

    final String? exportChoice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(activity.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: ${DateFormat('MMM d, y HH:mm').format(activity.timestamp)}'),
              Text('Duration: ${activity.duration.toString().split('.').first}'),
              Text('Average Power: ${activity.averagePower}W'),
              Text('Average Cadence: ${activity.averageCadence}rpm'),
              Text('Average Heart Rate: ${activity.averageHeartRate}bpm'),
              const SizedBox(height: 16),
              const Text('Export Options:'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('CANCEL'),
              onPressed: () => Navigator.of(context).pop('cancel'),
            ),
            if (isStravaConnected)
              TextButton(
                child: const Text('UPLOAD TO STRAVA'),
                onPressed: () => Navigator.of(context).pop('strava'),
              ),
            TextButton(
              child: const Text('SHARE'),
              onPressed: () => Navigator.of(context).pop('share'),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;

    if (exportChoice == 'share') {
      try {
        await Share.shareXFiles([XFile(activity.filePath)]);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to share file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (exportChoice == 'strava') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uploading to Strava...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final success = await StravaService.uploadActivity(
        activity.filePath,
        activity.name,
        'Workout completed using SmartSpin2k',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Successfully uploaded to Strava' : 'Failed to upload to Strava'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Completed Activities',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<ActivitySummary>>(
            future: FitFileReader.getCompletedActivities(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final activities = snapshot.data ?? [];

              if (activities.isEmpty) {
                return const Center(child: Text('No completed activities found'));
              }

              return ListView.builder(
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  final activity = activities[index];
                  return ListTile(
                    title: Text(activity.isInProgress ? '${activity.name} (In Progress)' : activity.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('MMM d, y HH:mm').format(activity.timestamp)),
                        if (activity.isInProgress) const Text('Status: In Progress'),
                        Text(
                          'Duration: ${activity.duration.toString().split('.').first} • '
                          'Power: ${activity.averagePower}W • '
                          'Cadence: ${activity.averageCadence}rpm',
                        ),
                      ],
                    ),
                    onTap: () => _showActivityOptions(context, activity),
                  );
                },
              );
            },
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}
