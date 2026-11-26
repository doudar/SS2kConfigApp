import 'package:shared_preferences/shared_preferences.dart';
import 'ride_map.dart';

class WorkoutExportChoice {
  const WorkoutExportChoice({
    this.uploadToStrava = false,
    this.uploadToIntervals = false,
    this.discard = false,
    this.mapSettings = const RideMapSettings(),
  });

  final bool uploadToStrava;
  final bool uploadToIntervals;
  final bool discard;
  final RideMapSettings mapSettings;

  static WorkoutExportChoice loadPreferences(SharedPreferences prefs) =>
      WorkoutExportChoice(
        mapSettings: RideMapSettings.load(prefs),
        uploadToStrava: prefs.getBool('workout_upload_strava') ?? true,
        uploadToIntervals: prefs.getBool('workout_upload_intervals') ?? true,
      );

  Future<void> savePreferences(
    SharedPreferences prefs, {
    required bool stravaConnected,
    required bool intervalsConnected,
  }) async {
    if (discard) return;
    // A disconnected app keeps its preference for when it is reconnected.
    if (stravaConnected) {
      await prefs.setBool('workout_upload_strava', uploadToStrava);
    }
    if (intervalsConnected) {
      await prefs.setBool('workout_upload_intervals', uploadToIntervals);
    }
  }
}

/// Attempt every selected upload once, even if another service fails.
Future<Map<String, bool>> uploadWorkoutToApps(
  Map<String, Future<bool> Function()> uploads, {
  required void Function(String app) onUploading,
}) async {
  final results = <String, bool>{};
  for (final entry in uploads.entries) {
    onUploading(entry.key);
    try {
      results[entry.key] = await entry.value();
    } catch (_) {
      results[entry.key] = false;
    }
  }
  return results;
}
