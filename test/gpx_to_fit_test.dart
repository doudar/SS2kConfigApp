import 'dart:io';

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';

void main() {
  test('convertGpxToFit preserves TrackPointExtension metrics', () async {
    final tempDir = await Directory.systemTemp.createTemp('gpx_to_fit_test');
    final gpxFile = File('${tempDir.path}/track_metrics.gpx');

    try {
      await gpxFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    version="1.1"
    xmlns="http://www.topografix.com/GPX/1/1"
    xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <trkseg>
      <trkpt lat="44.8113" lon="-91.4985">
        <ele>100.0</ele>
        <time>2026-01-01T00:00:00Z</time>
        <extensions>
          <power>200</power>
          <gpxtpx:TrackPointExtension>
            <gpxtpx:hr>150</gpxtpx:hr>
            <gpxtpx:cad>90</gpxtpx:cad>
          </gpxtpx:TrackPointExtension>
        </extensions>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''');

      final fitPath = await GpxToFitConverter.convertGpxToFit(gpxFile.path);
      final fitFile = FitFile.fromBytes(await File(fitPath).readAsBytes());
      final record = fitFile.records
          .map((r) => r.message)
          .whereType<RecordMessage>()
          .first;

      expect(record.power, 200);
      expect(record.heartRate, 150);
      expect(record.cadence, 90);
    } finally {
      await Directory(tempDir.path).delete(recursive: true);
    }
  });

  test('convertGpxToFit writes elapsed summary durations in seconds', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'gpx_to_fit_duration',
    );
    final gpxFile = File('${tempDir.path}/track_duration.gpx');

    try {
      await gpxFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele><time>2026-01-01T00:00:00Z</time></trkpt>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele><time>2026-01-01T00:00:01Z</time></trkpt>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele><time>2026-01-01T00:00:02Z</time></trkpt>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele><time>2026-01-01T00:00:03Z</time></trkpt>
  </trkseg></trk>
</gpx>''');

      final fitPath = await GpxToFitConverter.convertGpxToFit(gpxFile.path);
      final fitFile = FitFile.fromBytes(await File(fitPath).readAsBytes());
      final messages = fitFile.records.map((record) => record.message);
      final lap = messages.whereType<LapMessage>().first;
      final session = messages.whereType<SessionMessage>().first;
      final activity = messages.whereType<ActivityMessage>().first;

      expect(lap.totalElapsedTime, 3);
      expect(lap.totalTimerTime, 3);
      expect(session.totalElapsedTime, 3);
      expect(session.totalTimerTime, 3);
      expect(activity.totalTimerTime, 3);
    } finally {
      await Directory(tempDir.path).delete(recursive: true);
    }
  });

  test(
    'convertGpxToFit spaces timestamp-less records one second apart',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'gpx_to_fit_no_time',
      );
      final gpxFile = File('${tempDir.path}/track_no_time.gpx');

      try {
        await gpxFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><trkseg>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele></trkpt>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele></trkpt>
    <trkpt lat="44.8113" lon="-91.4985"><ele>100.0</ele></trkpt>
  </trkseg></trk>
</gpx>''');

        final fitPath = await GpxToFitConverter.convertGpxToFit(gpxFile.path);
        final fitFile = FitFile.fromBytes(await File(fitPath).readAsBytes());
        final records = fitFile.records
            .map((record) => record.message)
            .whereType<RecordMessage>()
            .toList();
        final session = fitFile.records
            .map((record) => record.message)
            .whereType<SessionMessage>()
            .first;

        expect(records[1].timestamp! - records[0].timestamp!, 1000);
        expect(records[2].timestamp! - records[1].timestamp!, 1000);
        expect(session.totalElapsedTime, 2);
      } finally {
        await Directory(tempDir.path).delete(recursive: true);
      }
    },
  );
}
