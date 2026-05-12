import 'dart:io';

import 'package:fit_tool/fit_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';

void main() {
  test('convertGpxToFit preserves TrackPointExtension metrics', () async {
    final tempDir = await Directory.systemTemp.createTemp('gpx_to_fit_test');
    final gpxFile = File('${tempDir.path}/track_metrics.gpx');

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

    await Directory(tempDir.path).delete(recursive: true);
  });
}
