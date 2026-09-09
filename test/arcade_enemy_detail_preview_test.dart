import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_enemy_art.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story_villain_art.dart';

const _styles = [
  ArcadeDroneStyle.beetle,
  ArcadeDroneStyle.wasp,
  ArcadeDroneStyle.orb,
  ArcadeDroneStyle.bramble,
  ArcadeDroneStyle.duneScorpion,
  ArcadeDroneStyle.frostWarden,
  ArcadeDroneStyle.stormRay,
  ArcadeDroneStyle.voidRegent,
];

void main() {
  testWidgets(
    'enemy details render at portrait and ride scale through moving and damaged poses',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1120);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('ARCADE_SCREENSHOTS') &&
          Platform.isWindows) {
        await tester.runAsync(() async {
          final bytes = await File(
            '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
          ).readAsBytes();
          await (FontLoader(
            'Roboto',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        });
      }
      final key = GlobalKey();
      for (final clock in [0.0, .7, 1.9]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              backgroundColor: const Color(0xff080f21),
              body: RepaintBoundary(
                key: key,
                child: Wrap(
                  children: [
                    for (final style in _styles)
                      SizedBox(
                        width: 540,
                        height: 280,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                style.targetName,
                                style: TextStyle(
                                  color: ArcadeEnemyArt.tint(style),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                              const Text(
                                'PORTRAIT                             RIDING SIZE / DAMAGED',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white54,
                                  letterSpacing: 1,
                                ),
                              ),
                              Expanded(
                                child: CustomPaint(
                                  size: const Size(508, 230),
                                  painter: _Details(style, clock),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('ARCADE_SCREENSHOTS') && clock == .7) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            const stage = String.fromEnvironment(
              'ARCADE_DETAIL_STAGE',
              defaultValue: 'after',
            );
            final file = File('build/arcade_enemy_details_$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    },
  );
}

class _Details extends CustomPainter {
  const _Details(this.style, this.clock);
  final ArcadeDroneStyle style;
  final double clock;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(
        i == 0
            ? 128
            : i == 1
            ? 320
            : 420,
        size.height / 2 + 8,
      );
      canvas.scale(i == 0 ? (style.isBoss ? 1.35 : 2.1) : .72);
      if (i == 2 && style.isBoss) {
        ArcadeStoryVillainArt.paint(
          canvas,
          Offset.zero,
          clock,
          style: style,
          running: true,
          damage: .6,
        );
      } else {
        ArcadeEnemyArt.paint(canvas, style, clock, damage: i == 2 ? .6 : 0);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _Details old) =>
      style != old.style || clock != old.clock;
}
