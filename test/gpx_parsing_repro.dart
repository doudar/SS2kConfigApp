import 'package:gpx/gpx.dart';
import 'package:test/test.dart';

void main() {
  test('GPX Parsing Reproduction', () {
    final gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
 <trk>
  <trkseg>
   <trkpt lat="44.8113" lon="-91.4985">
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
</gpx>''';

    final xmlGpx = GpxReader().fromString(gpxContent);
    final trackPoint = xmlGpx.trks[0].trksegs[0].trkpts[0];
    final ext = trackPoint.extensions;

    print('Extensions keys: ${ext.keys}');
    print('Power: ${ext['power']}');
    print('TrackPointExtension: ${ext['gpxtpx:TrackPointExtension']}');
    print('TrackPointExtension Type: ${ext['gpxtpx:TrackPointExtension'].runtimeType}');
    
    final tpExtStr = ext['gpxtpx:TrackPointExtension']?.toString() ?? '';
    print('TrackPointExtension toString: "$tpExtStr"');

    final values = tpExtStr.trim().split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    print('Split values: $values');
  });
}
