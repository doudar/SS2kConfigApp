import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'device previews are bundled, decodable and within their size budget',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      var previewBytes = 0;
      for (final path in [
        'assets/ss2kv3.png',
        'assets/device_previews/shifter.png',
        'assets/device_previews/workout.png',
        'assets/device_previews/settings.png',
        'assets/device_previews/power-table.png',
      ]) {
        expect(manifest.listAssets(), contains(path));
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0), reason: path);
        expect(frame.image.height, greaterThan(0), reason: path);
        if (path.contains('/device_previews/')) {
          previewBytes += bytes.lengthInBytes;
          expect(frame.image.width, 480, reason: path);
          expect(frame.image.height, 300, reason: path);
        }
        frame.image.dispose();
        codec.dispose();
      }
      expect(previewBytes, lessThan(200 * 1024));
    },
  );
}
