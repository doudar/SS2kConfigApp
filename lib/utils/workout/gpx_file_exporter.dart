import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/strava_service.dart';
import '../../services/intervals_service.dart';
import 'workout_controller.dart';
import 'workout_export_dialog.dart';
import 'workout_uploads.dart';
import 'ride_map.dart';
import 'workout_fit_export.dart';
import 'workout_skyline.dart';
import 'package:fit_tool/fit_tool.dart';
import 'package:xml/xml.dart';
import 'gpx_to_fit.dart';
import 'workout_coach_repository.dart';

class GpxFileExporter {
  static Future<String> generateGpxContent(
    String workoutName,
    List<TrackPoint> trackPoints, {
    RideMapSettings settings = const RideMapSettings(),
    List<Offset> plan = const [],
    double? ftp,
  }) async {
    if (trackPoints.isEmpty || settings.drawing == RideDrawing.none) return '';
    final records = WorkoutFitExport.records(
      trackPoints,
      settings,
      plan: plan,
      ftp: ftp,
    );
    return records.first.positionLat == null
        ? ''
        : _gpxContent(workoutName, records);
  }

  static String _gpxContent(String workoutName, List<RecordMessage> records) {
    String time(RecordMessage point) => DateTime.fromMillisecondsSinceEpoch(
      point.timestamp!,
      isUtc: true,
    ).toIso8601String();

    return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www.garmin.com/xmlschemas/GpxExtensionsv3.xsd http://www.garmin.com/xmlschemas/TrackPointExtension/v1 http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd"
     creator="SmartSpin2k" version="1.1" 
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
     xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3">
 <metadata>
  <time>${time(records.first)}</time>
 </metadata>
 <trk>
  <name>${XmlText(workoutName).toXmlString()}</name>
  <type>VirtualRide</type>
  <trkseg>
${records.map((point) => '''   <trkpt lat="${point.positionLat}" lon="${point.positionLong}">
    <ele>${point.altitude}</ele>
    <time>${time(point)}</time>
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

  static bool _tryCloseDialogIfShown(BuildContext context, bool dialogShown) {
    if (dialogShown && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      return true;
    }
    return false;
  }

  static Future<void> showExportDialog(
    BuildContext context,
    WorkoutController workoutController,
  ) async {
    bool optionsDialogShown = false;
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const WorkoutExportProgressDialog(
            message: 'Checking your connected apps…',
          );
        },
      );
      optionsDialogShown = true;
    }

    final isStravaConnected = await StravaService.isAuthenticated();
    final isIntervalsConnected = await IntervalsService.isAuthenticated();
    final prefs = await SharedPreferences.getInstance();
    if (_tryCloseDialogIfShown(context, optionsDialogShown)) {
      optionsDialogShown = false;
    }

    if (!context.mounted) return;
    // Open the prompt immediately, including when resuming from the overlay.
    // Both the finished summary and the map use the same checkpoint snapshot.
    final recorded = workoutController
        .getExportTrackPoints()
        .then<List<TrackPoint>?>(
          (points) => points,
          onError: (Object error) {
            debugPrint('Could not read ride summary: $error');
            return null; // Saving will retry the read.
          },
        );
    final exportChoice = await showDialog<WorkoutExportChoice>(
      context: context,
      builder: (context) => FutureBuilder<List<TrackPoint>?>(
        future: recorded,
        builder: (context, snapshot) => WorkoutExportDialog(
          workoutName: workoutController.workoutName ?? 'Indoor ride',
          duration: workoutController.formatDuration(
            workoutController.elapsedSeconds,
          ),
          averagePower: snapshot.data == null
              ? workoutController.averagePower
              : averageRecordedWatts(
                  snapshot.data!.map((p) => p.power),
                )?.toDouble(),
          averageCadence: workoutController.averageCadence,
          stravaConnected: isStravaConnected,
          intervalsConnected: isIntervalsConnected,
          initialChoice: WorkoutExportChoice.loadPreferences(prefs),
        ),
      ),
    );

    if (exportChoice == null) return;
    if (!exportChoice.discard) {
      await exportChoice.savePreferences(
        prefs,
        stravaConnected: isStravaConnected,
        intervalsConnected: isIntervalsConnected,
      );
      if (!context.mounted) return;
      final saved = await exportWorkoutFile(
        context,
        workoutController,
        mapSettings: exportChoice.mapSettings,
        recorded: recorded,
        uploadToStrava: exportChoice.uploadToStrava,
        uploadToIntervals: exportChoice.uploadToIntervals,
      );
      if (!saved) return;
    }

    await workoutController.clearInProgressFile();
    // Reset workout position to beginning
    workoutController.resetWorkout();
  }

  static Future<bool> exportWorkoutFile(
    BuildContext context,
    WorkoutController workoutController, {
    required RideMapSettings mapSettings,
    Future<List<TrackPoint>?>? recorded,
    bool uploadToStrava = false,
    bool uploadToIntervals = false,
  }) async {
    final progressMessage = ValueNotifier<String>(
      'Preparing workout export...',
    ); // disposed in finally
    bool progressDialogShown = false;
    if (context.mounted) {
      progressDialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return ValueListenableBuilder<String>(
            valueListenable: progressMessage,
            builder: (context, value, _) =>
                WorkoutExportProgressDialog(message: value),
          );
        },
      );
    }
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final workoutName = workoutController.workoutName ?? 'Unnamed Workout';

      progressMessage.value = 'Generating workout track...';
      final trackPoints =
          await recorded ?? await workoutController.getExportTrackPoints();

      if (trackPoints.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No workout data to export'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      progressMessage.value = 'Saving workout file...';
      final plan = skylinePlan(workoutController.segments);
      final ftp = workoutController.ftpValue;
      final records = WorkoutFitExport.records(
        trackPoints,
        mapSettings,
        plan: plan,
        ftp: ftp,
      );
      final appDir = await getApplicationDocumentsDirectory();

      final workoutsDir = Directory(
        '${appDir.path}${Platform.pathSeparator}workouts',
      );
      if (!await workoutsDir.exists()) {
        await workoutsDir.create(recursive: true);
      }

      final fitFilePath = '${workoutsDir.path}/workout_$timestamp.fit';
      try {
        final bytes = GpxToFitConverter.buildActivity(
          records,
          ftp: ftp.round(),
        ).toBytes();
        await File(fitFilePath).writeAsBytes(bytes);
      } catch (e) {
        if (records.first.positionLat == null) rethrow;
        final gpxFile = File('${workoutsDir.path}/workout_$timestamp.gpx');
        await gpxFile.writeAsString(_gpxContent(workoutName, records));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not save FIT file. Saved GPX to ${gpxFile.path}',
              ),
            ),
          );
          if (!uploadToStrava && !uploadToIntervals) {
            await SharePlus.instance.share(
              ShareParams(files: [XFile(gpxFile.path)]),
            );
          }
        }
        return true;
      }
      try {
        await WorkoutFitExport.savePlan(fitFilePath, plan);
      } on FileSystemException catch (error) {
        // The FIT is complete. Past rides can still draw its recorded power.
        debugPrint('Could not save workout skyline profile: $error');
      }
      WorkoutCoachRepository.invalidateLocal();

      final uploadResults = await uploadWorkoutToApps({
        if (uploadToStrava)
          'Strava': () => StravaService.uploadActivity(
            fitFilePath,
            workoutName,
            'Workout completed using SmartSpin2k',
          ),
        if (uploadToIntervals)
          'Intervals.icu': () => IntervalsService.uploadWorkout(
            fitFilePath,
            workoutName,
            'Workout completed using SmartSpin2k',
          ),
      }, onUploading: (app) => progressMessage.value = 'Uploading to $app...');
      if (context.mounted) {
        if (_tryCloseDialogIfShown(context, progressDialogShown)) {
          progressDialogShown = false;
        }
        final bool? shouldShare = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return WorkoutSavedDialog(
              filePath: fitFilePath,
              uploadResults: uploadResults,
            );
          },
        );

        if (shouldShare == true) {
          try {
            await SharePlus.instance.share(
              ShareParams(files: [XFile(fitFilePath)]),
            );
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
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export workout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (_tryCloseDialogIfShown(context, progressDialogShown)) {
        progressDialogShown = false;
      }
      progressMessage.dispose();
    }
  }
}
