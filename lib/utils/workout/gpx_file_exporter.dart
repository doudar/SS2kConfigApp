import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/strava_service.dart';
import '../../services/intervals_service.dart';
import 'workout_controller.dart';
import 'bike_shape_generator.dart';
import 'gpx_to_fit.dart';

class GpxFileExporter {
  static Future<List<TrackPoint>> generateBikeTrackPoints(List<TrackPoint> originalPoints) async {
    final mappedPoints = <TrackPoint>[];
    
    // Extract speeds from original points
    final speeds = originalPoints.map((point) => point.speed).toList();
    
    // Generate bike shape coordinates based on speeds
    final bikePoints = await BikeShapeGenerator.generateBikeShape(speeds);
    
    // Map original data to new coordinates
    for (int i = 0; i < originalPoints.length; i++) {
      final point = originalPoints[i];
      final bikePoint = bikePoints[i];
      
      mappedPoints.add(TrackPoint(
        timestamp: point.timestamp,
        lat: bikePoint.lat,
        lon: bikePoint.lon,
        elevation: point.elevation,
        heartRate: point.heartRate,
        cadence: point.cadence,
        power: point.power,
        speed: point.speed,
      ));
    }
    
    return mappedPoints;
  }

  static Future<String> generateGpxContent(
    String workoutName,
    List<TrackPoint> trackPoints,
  ) async {
    if (trackPoints.isEmpty) {
      return ''; // Return empty string if no track points
    }

    // Generate bike shape track points based on speed and distance
    final bikeTrackPoints = await generateBikeTrackPoints(trackPoints);

    return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www.garmin.com/xmlschemas/GpxExtensionsv3.xsd http://www.garmin.com/xmlschemas/TrackPointExtension/v1 http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd"
     creator="SmartSpin2k" version="1.1" 
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
     xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3">
 <metadata>
  <time>${bikeTrackPoints.first.timestamp.toIso8601String()}</time>
 </metadata>
 <trk>
  <name>$workoutName</name>
  <type>VirtualRide</type>
  <trkseg>
${bikeTrackPoints.map((point) => '''   <trkpt lat="${point.lat}" lon="${point.lon}">
    <ele>${point.elevation}</ele>
    <time>${point.timestamp.toIso8601String()}</time>
    <extensions>
     <power>${point.power}</power>
     <gpxtpx:TrackPointExtension>
      <gpxtpx:hr>${point.heartRate}</gpxtpx:hr>
      <gpxtpx:cad>${point.cadence}</gpxtpx:cad>
     </gpxtpx:TrackPointExtension>
    </extensions>
   </trkpt>''').join('\n')}
  </trkseg>
 </trk>
</gpx>''';
  }

  static Future<void> showExportDialog(BuildContext context, WorkoutController workoutController, String? currentWorkoutContent) async {
    final isStravaConnected = await StravaService.isAuthenticated();
    final isIntervalsConnected = await IntervalsService.isAuthenticated();

    final String? exportChoice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Export Workout'),
          content: const Text('How would you like to export your workout?'),
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
            if (isIntervalsConnected)
              TextButton(
                child: const Text('UPLOAD TO INTERVALS.ICU'),
                onPressed: () => Navigator.of(context).pop('intervals'),
              ),
            TextButton(
              child: const Text('SAVE FILE'),
              onPressed: () => Navigator.of(context).pop('save'),
            ),
          ],
        );
      },
    );

    if (exportChoice == 'save' || exportChoice == 'strava' || exportChoice == 'intervals') {
      await exportWorkoutFile(
        context, 
        workoutController,
        uploadToStrava: exportChoice == 'strava',
        uploadToIntervals: exportChoice == 'intervals',
      );
    }

    // Reset workout position to beginning
    if (currentWorkoutContent != null) {
      workoutController.loadWorkout(currentWorkoutContent);
    }
  }

  static Future<void> exportWorkoutFile(
    BuildContext context, 
    WorkoutController workoutController, 
    {bool uploadToStrava = false, bool uploadToIntervals = false}
  ) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final gpxFileName = 'workout_${timestamp}.gpx';
      final workoutName = workoutController.workoutName ?? 'Unnamed Workout';
      
      // Generate GPX content using collected track points
      final gpxContent = await generateGpxContent(
        workoutName,
        workoutController.trackPoints,
      );

      if (gpxContent.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No workout data to export'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get the appropriate directory based on platform
      final Directory appDir;
      if (Platform.isIOS) {
        appDir = await getApplicationDocumentsDirectory();
      } else {
        appDir = await getApplicationDocumentsDirectory();
      }

      // Create workouts directory if it doesn't exist
      final workoutsDir = Directory('${appDir.path}${Platform.pathSeparator}workouts');
      if (!await workoutsDir.exists()) {
        await workoutsDir.create(recursive: true);
      }

      // Save the GPX file temporarily
      final gpxFile = File('${workoutsDir.path}${Platform.pathSeparator}$gpxFileName');
      await gpxFile.writeAsString(gpxContent);

      try {
        // Convert GPX to FIT
        final fitFilePath = await GpxToFitConverter.convertAndCleanup(gpxFile.path);

        if (uploadToStrava) {
          if (context.mounted) {
            // Show uploading indicator
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Uploading to Strava...'),
                duration: Duration(seconds: 1),
              ),
            );
          }

          final success = await StravaService.uploadActivity(
            fitFilePath,
            workoutName,
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
        } else if (uploadToIntervals) {
          if (context.mounted) {
            // Show uploading indicator
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Uploading to Intervals.icu...'),
                duration: Duration(seconds: 1),
              ),
            );
          }

          final success = await IntervalsService.uploadWorkout(
            fitFilePath,
            workoutName,
            'Workout completed using SmartSpin2k',
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? 'Successfully uploaded to Intervals.icu' : 'Failed to upload to Intervals.icu'),
                backgroundColor: success ? const Color(0xFF1B4F72) : Colors.red,
              ),
            );
          }
        } else if (context.mounted) {
          final bool? shouldShare = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Workout Exported'),
                content: Text('File saved to: $fitFilePath\n\nWould you like to share it now?'),
                actions: <Widget>[
                  TextButton(
                    child: const Text('NO'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  TextButton(
                    child: const Text('YES'),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              );
            },
          );

          if (shouldShare == true) {
            try {
              await Share.shareXFiles([XFile(fitFilePath)]);
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
          }
        }
      } catch (e) {
        // If FIT conversion fails, fall back to sharing GPX
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to convert to FIT format: $e\nSharing GPX file instead.'),
              backgroundColor: Colors.orange,
            ),
          );
          if (!uploadToStrava && !uploadToIntervals) {
            await Share.shareXFiles([XFile(gpxFile.path)]);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export workout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
