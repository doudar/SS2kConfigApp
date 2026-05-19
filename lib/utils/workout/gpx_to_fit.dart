import 'dart:io';
import 'package:fit_tool/fit_tool.dart';
import 'package:gpx/gpx.dart';

class GpxToFitConverter {
  static int _toFitTimestamp(DateTime dt) {
    return (dt.toUtc().millisecondsSinceEpoch);
  }

  static String? _extensionText(Object? extensionValue) {
    if (extensionValue == null) return null;

    final text = extensionValue.toString();
    return text.isEmpty ? null : text;
  }

  static Object? _findExtensionValue(Map extensionMap, String tagName) {
    for (final entry in extensionMap.entries) {
      final key = entry.key.toString();
      if (key == tagName || key.endsWith(':$tagName')) {
        return entry.value;
      }
    }

    return null;
  }

  static int? _extractExtensionInt(Object? extensionValue, String tagName) {
    if (extensionValue is Map) {
      final mapValue = _findExtensionValue(extensionValue, tagName);
      final parsedMapValue = int.tryParse(mapValue?.toString() ?? '');
      if (parsedMapValue != null) {
        return parsedMapValue;
      }
    }

    final extensionText = _extensionText(extensionValue);
    if (extensionText == null) return null;

    final tagMatch = RegExp(
      '<(?:\\w+:)?$tagName>([^<]+)</(?:\\w+:)?$tagName>',
    ).firstMatch(extensionText);
    if (tagMatch != null) {
      return int.tryParse(tagMatch.group(1)!.trim());
    }

    return null;
  }

  /// Converts a GPX file to FIT format and returns the path to the new FIT file
  static Future<String> convertGpxToFit(String gpxFilePath) async {
    // Read GPX file
    final gpxFile = File(gpxFilePath);
    final gpxString = await gpxFile.readAsString();
    final xmlGpx = GpxReader().fromString(gpxString);

    // Create FIT file builder
    final builder = FitFileBuilder(autoDefine: true, minStringSize: 50);

    // Use GPX timestamps when available
    final firstTrackPointTime =
        xmlGpx.trks.isNotEmpty &&
            xmlGpx.trks[0].trksegs.isNotEmpty &&
            xmlGpx.trks[0].trksegs[0].trkpts.isNotEmpty
        ? xmlGpx.trks[0].trksegs[0].trkpts.first.time
        : null;

    final DateTime baseDateTime = firstTrackPointTime ?? DateTime.now().toUtc();
    final int startTimestamp = _toFitTimestamp(baseDateTime);

    // Add File ID message
    final fileIdMessage = FileIdMessage()
      ..type = FileType.activity
      ..manufacturer = Manufacturer.development.value
      ..product = 0
      ..timeCreated = startTimestamp
      ..serialNumber = 0x12345678;
    builder.add(fileIdMessage);

    // Add start event
    final eventMessage = EventMessage()
      ..event = Event.timer
      ..eventType = EventType.start
      ..timestamp = startTimestamp;
    builder.add(eventMessage);

    // Process track points
    final records = <RecordMessage>[];
    // Seed one second before the start so that when GPX timestamps are missing, the first
    // fallback calculation (previousTimestamp + 1) lands exactly on startTimestamp,
    // ensuring the first record starts at the correct time
    int previousTimestamp = startTimestamp - 1;

    if (xmlGpx.trks.isNotEmpty && xmlGpx.trks[0].trksegs.isNotEmpty) {
      for (var trackPoint in xmlGpx.trks[0].trksegs[0].trkpts) {
        final tpTime = trackPoint.time;
        final timestamp = tpTime != null
            ? _toFitTimestamp(tpTime)
            : (previousTimestamp + 1);
        final record = RecordMessage()
          ..timestamp = timestamp
          ..positionLong = trackPoint.lon
          ..positionLat = trackPoint.lat
          ..altitude = trackPoint.ele;

        // Extract heart rate, cadence, and power from extensions
        final ext = trackPoint.extensions;

        // Extract power
        final powerStr = _extensionText(ext['power']) ?? '0';
        record.power = int.tryParse(powerStr) ?? 0;

        // Extract heart rate and cadence from TrackPointExtension
        final tpExt = ext['gpxtpx:TrackPointExtension'];
        final tpExtStr = _extensionText(tpExt);
        final heartRate = _extractExtensionInt(tpExt, 'hr');
        final cadence = _extractExtensionInt(tpExt, 'cad');
        if (heartRate != null) {
          record.heartRate = heartRate;
        }
        if (cadence != null) {
          record.cadence = cadence;
        }

        if (tpExtStr != null && heartRate == null && cadence == null) {
          final values = tpExtStr
              .trim()
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (values.length >= 2) {
            record.heartRate = int.tryParse(values[0]) ?? 0;
            record.cadence = int.tryParse(values[1]) ?? 0;
          }
        }

        records.add(record);
        previousTimestamp = timestamp;
      }
      builder.addAll(records);
      // Add Lap message
      final lastRecordTimestamp = previousTimestamp;
      final lapMessage = LapMessage()
        ..timestamp = lastRecordTimestamp
        ..startTime = startTimestamp;
      // ..totalElapsedTime = elapsedTime
      // ..totalTimerTime = elapsedTime;
      builder.add(lapMessage);

      // Add Session message
      final sessionMessage = SessionMessage()
        ..timestamp = lastRecordTimestamp
        ..startTime = startTimestamp
        // ..totalElapsedTime = elapsedTime
        // ..totalTimerTime = elapsedTime
        ..sport = Sport.cycling
        ..subSport = SubSport.virtualActivity
        ..firstLapIndex = 0
        ..numLaps = 1;
      builder.add(sessionMessage);

      // Add Activity message for summary timing
      final activityMessage = ActivityMessage()
        ..timestamp = lastRecordTimestamp
        //..totalTimerTime = elapsedTime
        ..numSessions = 1
        ..type = Activity.manual
        ..event = Event.activity
        ..eventType = EventType.stop;
      builder.add(activityMessage);

      // Build and save FIT file
      final fitFile = builder.build();
      final fitFilePath = gpxFilePath.replaceAll('.gpx', '.fit');
      final outFile = File(fitFilePath);
      await outFile.writeAsBytes(fitFile.toBytes());

      return fitFilePath;
    } else {
      throw Exception('No track points found in GPX file');
    }
  }

  /// Converts GPX to FIT, deletes the GPX file, and returns the FIT file path
  static Future<String> convertAndCleanup(String gpxFilePath) async {
    try {
      final fitFilePath = await convertGpxToFit(gpxFilePath);
      // Delete the original GPX file
      final gpxFile = File(gpxFilePath);
      if (await gpxFile.exists()) {
        await gpxFile.delete();
      }
      return fitFilePath;
    } catch (e) {
      throw Exception('Failed to convert GPX to FIT: $e');
    }
  }
}
