import 'dart:io';
import 'package:fit_tool/fit_tool.dart';
import 'package:gpx/gpx.dart';

class GpxToFitConverter {
  /// Converts a GPX file to FIT format and returns the path to the new FIT file
  static Future<String> convertGpxToFit(String gpxFilePath) async {
    // Read GPX file
    final gpxFile = File(gpxFilePath);
    final gpxString = await gpxFile.readAsString();
    final xmlGpx = GpxReader().fromString(gpxString);

    // Create FIT file builder
    final builder = FitFileBuilder(autoDefine: true, minStringSize: 50);

    // Use GPX timestamps when available
    final firstTrackPointTime = xmlGpx.trks.isNotEmpty &&
            xmlGpx.trks[0].trksegs.isNotEmpty &&
            xmlGpx.trks[0].trksegs[0].trkpts.isNotEmpty
        ? xmlGpx.trks[0].trksegs[0].trkpts.first.time
        : null;

    final baseTimestamp = (firstTrackPointTime ?? DateTime.now()).millisecondsSinceEpoch;

    // Add File ID message
    final fileIdMessage = FileIdMessage()
      ..type = FileType.activity
      ..manufacturer = Manufacturer.development.value
      ..product = 0
      ..timeCreated = baseTimestamp
      ..serialNumber = 0x12345678;
    builder.add(fileIdMessage);

    // Add start event
    final startTimestamp = baseTimestamp;
    final eventMessage = EventMessage()
      ..event = Event.timer
      ..eventType = EventType.start
      ..timestamp = startTimestamp;
    builder.add(eventMessage);

    // Process track points
    final records = <RecordMessage>[];
    int? previousTimestamp;

    if (xmlGpx.trks.isNotEmpty && xmlGpx.trks[0].trksegs.isNotEmpty) {
      for (var trackPoint in xmlGpx.trks[0].trksegs[0].trkpts) {
        final tpTime = trackPoint.time?.millisecondsSinceEpoch;
        final timestamp = tpTime ?? (previousTimestamp != null ? previousTimestamp + 1000 : startTimestamp);
        final record = RecordMessage()
          ..timestamp = timestamp
          ..positionLong = trackPoint.lon
          ..positionLat = trackPoint.lat
          ..altitude = trackPoint.ele;

        // Extract heart rate, cadence, and power from extensions
        final ext = trackPoint.extensions;
        
        // Extract power
        final powerStr = ext['power']?.toString() ?? '0';
        record.power = int.tryParse(powerStr) ?? 0;
        
        // Extract heart rate and cadence from TrackPointExtension
        final tpExt = ext['gpxtpx:TrackPointExtension'];
        if (tpExt is Map) {
          final hr = tpExt['gpxtpx:hr'];
          final cad = tpExt['gpxtpx:cad'];
          if (hr != null) {
            record.heartRate = int.tryParse(hr.toString()) ?? 0;
          }
          if (cad != null) {
            record.cadence = int.tryParse(cad.toString()) ?? 0;
          }
        } else {
          // Legacy/Fallback parsing logic
          final tpExtStr = tpExt?.toString() ?? '';
          if (tpExtStr.isNotEmpty) {
            // The TrackPointExtension string contains both HR and cadence values
            // Split the string and extract the values
            final values = tpExtStr.trim().split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            if (values.length >= 2) {
              record.heartRate = int.tryParse(values[0]) ?? 0;
              record.cadence = int.tryParse(values[1]) ?? 0;
            }
          }
        }
      
        records.add(record);
        previousTimestamp = timestamp;
      }
      builder.addAll(records);
      // Add Lap message
      final endTimestamp = previousTimestamp ?? startTimestamp;
      final elapsedTime = (endTimestamp - startTimestamp).toDouble();
      final lapMessage = LapMessage()
        ..timestamp = endTimestamp
        ..startTime = startTimestamp
        ..totalElapsedTime = elapsedTime
        ..totalTimerTime = elapsedTime;
      builder.add(lapMessage);

      // Add Session message
      final sessionMessage = SessionMessage()
        ..timestamp = endTimestamp
        ..startTime = startTimestamp
        ..totalElapsedTime = elapsedTime
        ..totalTimerTime = elapsedTime
        ..sport = Sport.cycling
        ..subSport = SubSport.exercise
        ..firstLapIndex = 0
        ..numLaps = 1;
      builder.add(sessionMessage);

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
