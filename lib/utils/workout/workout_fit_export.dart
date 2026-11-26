import 'dart:io';
import 'dart:math' as math;

import 'package:fit_tool/fit_tool.dart';

import 'gpx_to_fit.dart';
import 'ride_map.dart';
import 'workout_controller.dart';
import 'workout_skyline.dart';

class WorkoutFitExport {
  static List<RecordMessage> records(
    List<TrackPoint> points,
    RideMapSettings settings, {
    double? ftp,
  }) {
    if (points.isEmpty) return [];
    double distance = 0;
    final samples = <RecordMessage>[];
    for (final point in points) {
      // The workout recorder emits one speed sample per second of ride time.
      distance += point.speed;
      final record = RecordMessage()
        ..timestamp = point.timestamp.millisecondsSinceEpoch
        ..altitude = point.elevation
        ..heartRate = point.heartRate
        ..cadence = point.cadence
        ..power = point.power
        ..speed = point.speed
        ..distance = distance;
      samples.add(record);
    }
    final drawing = settings.drawing.forRide(
      DateTime.fromMillisecondsSinceEpoch(
        samples.first.timestamp!,
        isUtc: true,
      ),
      includeSkyline: ftp != null,
    );
    _applyMap(samples, settings.withDrawing(drawing), ftp: ftp);
    return samples;
  }

  static void _applyMap(
    List<RecordMessage> samples,
    RideMapSettings settings, {
    double? ftp,
    double? savedTss,
  }) {
    if (settings.drawing == RideDrawing.none) return;
    final start = DateTime.fromMillisecondsSinceEpoch(
      samples.first.timestamp!,
      isUtc: true,
    );
    final isSkyline = settings.drawing == RideDrawing.skyline;
    final origin = samples.first.distance!;
    final totalDistance = samples.last.distance!;
    final span = totalDistance - origin;
    WorkoutSkyline? skyline;
    var includeLettering = true;
    if (isSkyline) {
      // Repeated positions add no detail. Use the widest gap so a few
      // moving seconds among many stationary records cannot distort the text.
      var maxStep = 0.0, previous = origin;
      for (final sample in samples) {
        final distance = sample.distance!;
        maxStep = math.max(maxStep, distance - previous);
        previous = distance;
      }
      // A closed silhouette needs a few points per side. The small turns
      // in the lettering need much finer spacing and room on the map.
      if (span <= 0 || totalDistance < 25 || maxStep > span / 12) return;
      includeLettering = totalDistance >= 1000 && maxStep <= span / 800;
      skyline = WorkoutSkyline.fromRide(
        samples.map((r) => r.power).toList(),
        ftp: ftp,
        savedTss: savedTss,
      );
      if (skyline.averageWatts == null) return;
    }
    final route = RideMapRoute.forRide(
      settings,
      start,
      skyline: skyline,
      skylineDistance: totalDistance,
      includeLettering: includeLettering,
    );
    if (route == null) return;
    final coordinates = isSkyline
        ? route.positionsForClosedRide(
            samples.map((r) => (r.distance! - origin) / span),
          )
        : samples.map((r) => route.position(r.distance!));
    var index = 0;
    for (final coordinate in coordinates) {
      samples[index++]
        ..positionLat = coordinate.lat
        ..positionLong = coordinate.lon;
    }
  }

  // Older app exports have GPS but no recorded speed or distance.
  static double _legacyDistance(RecordMessage previous, RecordMessage current) {
    final lat1 = previous.positionLat, lat2 = current.positionLat;
    final lon1 = previous.positionLong, lon2 = current.positionLong;
    if (lat1 == null || lat2 == null || lon1 == null || lon2 == null) return 0;
    const radians = math.pi / 180;
    final a =
        math.pow(math.sin((lat2 - lat1) * radians / 2), 2) +
        math.cos(lat1 * radians) *
            math.cos(lat2 * radians) *
            math.pow(math.sin((lon2 - lon1) * radians / 2), 2);
    return 2 * RideMapRoute.earthRadius * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  /// Apply today's upload preferences to an app-created FIT in Past rides.
  /// Only the temporary upload copy is modified.
  static Future<bool> uploadSavedRide(
    File source,
    RideMapSettings settings,
    Future<bool> Function(String) upload, {
    double? fallbackFtp,
  }) async {
    final saved = FitFile.fromBytes(await source.readAsBytes());
    final samples = saved.records
        .map((r) => r.message)
        .whereType<RecordMessage>();
    if (samples.isEmpty) throw const FormatException('No workout samples');
    final session = saved.records
        .map((r) => r.message)
        .whereType<SessionMessage>()
        .firstOrNull;
    final drawing = settings.drawing.forRide(
      DateTime.fromMillisecondsSinceEpoch(
        samples.first.timestamp!,
        isUtc: true,
      ),
      includeSkyline: session?.thresholdPower != null,
    );
    final records = <RecordMessage>[];
    RecordMessage? previous;
    double distance = 0;
    for (final sample in samples) {
      distance =
          sample.distance ??
          distance + (previous == null ? 0 : _legacyDistance(previous, sample));
      final elapsed = previous == null
          ? 0
          : (sample.timestamp! - previous.timestamp!) / 1000;
      final speed =
          sample.speed ??
          (elapsed > 0 ? (distance - records.last.distance!) / elapsed : 0.0);
      records.add(
        RecordMessage()
          ..timestamp = sample.timestamp
          ..altitude = sample.altitude
          ..heartRate = sample.heartRate
          ..cadence = sample.cadence
          ..speed = math.max(0, speed)
          ..power = sample.power
          ..distance = distance,
      );
      previous = sample;
    }
    final rideFtp = session?.thresholdPower;
    final ftp = rideFtp != null && rideFtp > 0
        ? rideFtp.toDouble()
        : fallbackFtp;
    _applyMap(
      records,
      settings.withDrawing(drawing),
      ftp: ftp,
      savedTss: session?.trainingStressScore,
    );
    final temp = await Directory.systemTemp.createTemp('ss2k_upload_');
    try {
      final file = File('${temp.path}/${source.uri.pathSegments.last}');
      await file.writeAsBytes(
        GpxToFitConverter.buildActivity(
          records,
          ftp: session?.thresholdPower,
        ).toBytes(),
      );
      return await upload(file.path);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
