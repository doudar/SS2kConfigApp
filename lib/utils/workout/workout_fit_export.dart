import 'dart:io';
import 'dart:math' as math;

import 'package:fit_tool/fit_tool.dart';

import 'gpx_to_fit.dart';
import 'ride_map.dart';
import 'workout_controller.dart';

class WorkoutFitExport {
  static List<RecordMessage> records(
    List<TrackPoint> points,
    RideMapSettings settings,
  ) {
    if (points.isEmpty) return [];
    final route = RideMapRoute.forRide(settings, points.first.timestamp);
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
        ..speed = point.speed;
      samples.add(_position(record, route, distance));
    }
    return samples;
  }

  static RecordMessage _position(
    RecordMessage record,
    RideMapRoute? route,
    double distance,
  ) {
    record.distance = distance;
    if (route != null) {
      final coordinate = route.position(distance);
      record
        ..positionLat = coordinate.lat
        ..positionLong = coordinate.lon;
    }
    return record;
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
    Future<bool> Function(String) upload,
  ) async {
    final saved = FitFile.fromBytes(await source.readAsBytes());
    final samples = saved.records
        .map((r) => r.message)
        .whereType<RecordMessage>();
    if (samples.isEmpty) throw const FormatException('No workout samples');
    final start = DateTime.fromMillisecondsSinceEpoch(
      samples.first.timestamp!,
      isUtc: true,
    );
    final route = RideMapRoute.forRide(settings, start);
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
        _position(
          RecordMessage()
            ..timestamp = sample.timestamp
            ..altitude = sample.altitude
            ..heartRate = sample.heartRate
            ..cadence = sample.cadence
            ..speed = math.max(0, speed)
            ..power = sample.power,
          route,
          distance,
        ),
      );
      previous = sample;
    }
    final temp = await Directory.systemTemp.createTemp('ss2k_upload_');
    try {
      final file = File('${temp.path}/${source.uri.pathSegments.last}');
      await file.writeAsBytes(
        GpxToFitConverter.buildActivity(records).toBytes(),
      );
      return await upload(file.path);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
