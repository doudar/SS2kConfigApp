import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_road.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_levels.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_scenery.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_world_painter.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  test('world seeds are stable for negative and distant tiles', () {
    for (final tile in [-1000, -1, 0, 80, 100000]) {
      final a = ArcadeScenery.seed(tile, 1);
      expect(a, ArcadeScenery.seed(tile, 1));
      expect(a, isNonNegative);
      expect(a, isNot(ArcadeScenery.seed(tile, 2)));
    }
    expect(ArcadeScenery.depth(-5), 0);
    expect(ArcadeScenery.depth(89), 0);
    expect(ArcadeScenery.depth(90), 1);
    expect(ArcadeScenery.depth(180), 2);
    expect(ArcadeScenery.depth(100000), 2);
    expect(ArcadeScenery.depth(double.nan), 0);
  });

  test('biomes have varied flora and deep sectors reveal landmarks', () {
    for (final biome in ArcadeBiome.values) {
      Set<ArcadeSceneryKind> kinds(int depth) => {
        for (var tile = 0; tile < 500; tile++)
          ArcadeScenery.kind(
            biome: biome,
            tile: tile,
            side: 0,
            depth: depth,
            levelIndex: 0,
          ),
      };
      expect(kinds(0).length, greaterThanOrEqualTo(3));
      expect(kinds(2).length, greaterThan(kinds(0).length));
      expect(kinds(2), contains(ArcadeSceneryKind.ruin));
    }
    final kinds = {
      for (var level = 0; level < 6; level++)
        for (var tile = 0; tile < 1000; tile++)
          ArcadeScenery.kind(
            biome: ArcadeBiome.grove,
            tile: tile,
            side: 0,
            depth: 2,
            levelIndex: level,
          ),
    };
    expect(
      kinds,
      containsAll([
        ArcadeSceneryKind.rabbit,
        ArcadeSceneryKind.antenna,
        ArcadeSceneryKind.palm,
        ArcadeSceneryKind.crystal,
        ArcadeSceneryKind.coral,
      ]),
    );
  });

  test('ambient wildlife stays sparse and respects reduced motion', () {
    var visible = 0;
    final kinds = <ArcadeAmbientKind>{};
    for (var seconds = 0; seconds < 3600; seconds++) {
      final frame = ArcadeAmbient.at(seconds.toDouble());
      if (frame == null) continue;
      visible++;
      kinds.add(frame.kind);
      expect(frame.progress, inInclusiveRange(0, 1));
      expect(ArcadeAmbient.at(seconds.toDouble(), reducedMotion: true), isNull);
      expect(ArcadeAmbient.at(seconds.toDouble())!.progress, frame.progress);
    }
    expect(visible / 3600, lessThan(.15));
    expect(kinds, containsAll(ArcadeAmbientKind.values));
    expect(ArcadeAmbient.at(double.nan), isNull);
    expect(ArcadeAmbient.at(double.infinity), isNull);
    expect(ArcadeAmbient.at(-10), isNull);
  });

  testWidgets('all scenery and six world themes paint at tablet dimensions', (
    tester,
  ) async {
    final screenshot = const bool.fromEnvironment('ARCADE_SCREENSHOTS');
    if (screenshot && Platform.isWindows) {
      await tester.runAsync(() async {
        final font = File(
          '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
        );
        final loader = FontLoader('Roboto')
          ..addFont(
            font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      });
    }
    tester.view.physicalSize = const Size(1440, 1320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    const names = [
      'Sunwheel Meadows',
      'Overgrown Ruins',
      'Copper Dunes',
      'Frostline',
      'Stormworks',
      'Eclipse Citadel',
    ];
    final sectors = [
      WorkoutSegment(
        type: SegmentType.steadyState,
        duration: 240,
        powerLow: .55,
      ),
      WorkoutSegment(
        type: SegmentType.steadyState,
        duration: 180,
        powerLow: 1.15,
      ),
    ];
    final road = ArcadeRoadSnapshot(
      position: 211,
      speed: 2,
      spans: [
        ArcadeRoadSpan(sectors[0], 0, 480),
        ArcadeRoadSpan(sectors[1], 480, 840),
      ],
      currentIndex: 0,
      currentProgress: .5,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Column(
              children: [
                for (var row = 0; row < 3; row++)
                  SizedBox(
                    height: 380,
                    child: Row(
                      children: [
                        for (var col = 0; col < 2; col++)
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: ArcadeWorldPainter(
                                      segments: sectors,
                                      road: road,
                                      seconds: 42,
                                      animation: 42,
                                      biome: ArcadeBiome.grove,
                                      onTarget: true,
                                      charge: .4,
                                      pedalPhase: .4,
                                      moving: true,
                                      levelIndex: row * 2 + col,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  left: 18,
                                  child: Text(
                                    'LEVEL ${row * 2 + col + 1} / ${names[row * 2 + col]}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: CustomPaint(painter: _PropGallery()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    if (screenshot) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/arcade_worlds_preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    // Paint every prop's accessibility path too, with motion removed.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final kind in ArcadeSceneryKind.values) {
      ArcadeScenery.paint(
        canvas,
        Offset.zero,
        kind: kind,
        accent: Colors.cyan,
        variant: 12,
        reducedMotion: true,
        levelIndex: 3,
      );
    }
    recorder.endRecording().dispose();
  });

  testWidgets(
    'each story villain tows its cage and keeps its hillside identity',
    (tester) async {
      final sectors = [
        WorkoutSegment(
          type: SegmentType.steadyState,
          duration: 240,
          powerLow: .55,
        ),
      ];
      final road = ArcadeRoadSnapshot(
        position: 3,
        speed: 2,
        spans: [ArcadeRoadSpan(sectors.single, 0, 480)],
        currentIndex: 0,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (final level in ArcadeLevel.values) {
        for (final seconds in [1.5, 14.9, 15.0, 18.0, 23.0]) {
          final frame = ui.PictureRecorder();
          ArcadeWorldPainter(
            segments: sectors,
            road: road,
            seconds: seconds,
            animation: seconds,
            biome: ArcadeBiome.grove,
            onTarget: true,
            charge: 0,
            pedalPhase: .4,
            moving: true,
            escapeSeconds: seconds,
            levelIndex: level.index,
          ).paint(Canvas(frame), const Size(720, 380));
          final picture = frame.endRecording();
          if (seconds == 1.5) {
            canvas.save();
            canvas.translate(
              (level.index % 2) * 720.0,
              (level.index ~/ 2) * 380.0,
            );
            canvas.drawPicture(picture);
            final title = TextPainter(
              text: TextSpan(
                text: level.title,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            title.paint(canvas, const Offset(18, 12));
            canvas.restore();
          }
          picture.dispose();
        }
      }
      final gallery = recorder.endRecording();
      if (const bool.fromEnvironment('ARCADE_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final image = await gallery.toImage(1440, 1140);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/arcade_getaway_preview.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      gallery.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

class _PropGallery extends CustomPainter {
  const _PropGallery();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff152038),
    );
    for (final kind in ArcadeSceneryKind.values) {
      final x =
          size.width * (kind.index + .5) / ArcadeSceneryKind.values.length;
      ArcadeScenery.paint(
        canvas,
        Offset(x, 126),
        kind: kind,
        accent: const Color(0xff74ffd3),
        variant: kind.index,
        animation: 4,
      );
      final text = TextPainter(
        text: TextSpan(
          text: kind.name,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(x - text.width / 2, 148));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
