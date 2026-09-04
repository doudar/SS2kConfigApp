import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'device, shift and workout tile images are bundled and decodable',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final path in [
        'assets/ss2kv3.png',
        'assets/shiftscreen.png',
        'assets/Workout_Screen.png',
        'assets/settingsScreen.png',
      ]) {
        expect(manifest.listAssets(), contains(path));
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0), reason: path);
        expect(frame.image.height, greaterThan(0), reason: path);
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
