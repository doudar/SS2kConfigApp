import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_journey_map.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';

void main() {
  testWidgets('story catalog scales and highlights the selected adventure', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('ARCADE_SCREENSHOTS') &&
        Platform.isWindows) {
      await tester.runAsync(() async {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final font = File(
          '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
        );
        await (FontLoader(
          'Roboto',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      });
    }
    for (final size in [
      const Size(320, 440),
      const Size(844, 300),
      const Size(1080, 860),
    ]) {
      tester.view.physicalSize = size;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(size.width < 400 ? 1.5 : 1),
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: ArcadeJourneyMap(story: ArcadeStory(2)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('THIS RIDE · THE GREAT WHEEL HEIST'), findsOneWidget);
      expect(find.text('Copper Dunes · Dune Scorpion'), findsOneWidget);
      expect(find.text('THIS RIDE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('ARCADE_SCREENSHOTS') &&
          size.width > 1000) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/arcade_journey_preview.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
