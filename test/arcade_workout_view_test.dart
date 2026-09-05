import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_workout_view.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_world_painter.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'arcade scales across phones and desktop; controls remain accessible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('arcade_widget_'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => temp.path,
      );
      if (const bool.fromEnvironment('ARCADE_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          if (Platform.isWindows) {
            final font = File(
              '${Platform.environment['WINDIR']}/Fonts/segoeui.ttf',
            );
            final loader = FontLoader('Roboto')
              ..addFont(
                font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
              );
            await loader.load();
          }
        });
      }
      final data = DeviceData();
      final controller = WorkoutController(
        data,
        BluetoothDevice.fromId('00:00:00:00:A0:01'),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        controller.loadWorkout(
          '''<workout_file><name>Crank Quest</name><workout>
        <SteadyState Duration="90" Power="1.2"/>
        <SteadyState Duration="60" Power="0.5"/>
        <SteadyState Duration="120" Power="0.7"/>
        <SteadyState Duration="90" Power="0.95"/>
      </workout></workout_file>''',
        );
      });
      final game = ArcadeSession();
      void syncRoad() => game.road.update(
        segments: controller.segments,
        seconds: controller.workoutProgressSeconds,
        watts: data.ftmsData.watts.toDouble(),
        ftp: controller.ftpValue,
        playing: controller.isPlaying,
      );
      controller.addListener(syncRoad);
      syncRoad();
      data.ftmsData.watts = 240;
      data.setWorkoutTargetPower(240);
      var exits = 0;
      addTearDown(() async {
        controller.removeListener(syncRoad);
        controller.cleanup();
        data.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await temp.delete(recursive: true);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final size in [
        const Size(390, 750),
        const Size(844, 330),
        const Size(1200, 760),
        const Size(320, 568),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: ArcadeWorkoutView(
                  controller: controller,
                  deviceData: data,
                  session: game,
                  onStop: () {},
                  onExit: () => exits++,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('CRANK QUEST'), findsOneWidget);
        expect(find.text('PLAY'), findsOneWidget);
        expect(find.byTooltip('Arcade audio'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('ARCADE_SCREENSHOTS')) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/arcade_preview_${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      // Drive the actual view ticker from trainer cadence, without starting the
      // workout's transport/recording timer in this rendering test.
      controller.isPlaying = true;
      game.hasSignal = true;
      data.ftmsData.cadence = 60;
      await tester.runAsync(() => controller.updateFTP(200));
      await tester.pump();
      ArcadeWorldPainter world() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<ArcadeWorldPainter>()
          .single;
      double phase() => world().pedalPhase;
      final start = phase();
      final startPosition = world().road.position;
      await tester.pump(const Duration(milliseconds: 100));
      expect(world().road.speed, closeTo(2.4, .001));
      expect(world().road.position - startPosition, closeTo(.24, .001));
      final at60 = phase();
      expect(at60 - start, closeTo(.2 * math.pi, .001));
      data.ftmsData.cadence = 120;
      await tester.pump(const Duration(milliseconds: 100));
      final at120 = phase();
      expect(at120 - at60, closeTo(2 * (at60 - start), .001));
      // A new sector rebuilds the world while the crank clock keeps running.
      // Reward freshness can drop while the RPM display retains live cadence;
      // this must not gate the rider animation.
      game.hasSignal = false;
      controller.skipToNextSegment();
      await tester.pump(const Duration(milliseconds: 100));
      final afterSkip = phase();
      expect(afterSkip - at120, closeTo(.4 * math.pi, .001));
      expect(controller.currentSegment?.powerLow, .5);
      await tester.pump(const Duration(milliseconds: 100));
      final afterTransition = phase();
      expect(afterTransition - afterSkip, closeTo(.4 * math.pi, .001));
      data.ftmsData.cadence = 0;
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), afterTransition);
      data.ftmsData.cadence = 90;
      game.hasSignal = false;
      await tester.pump(const Duration(milliseconds: 100));
      final beforePause = phase();
      expect(
        (beforePause - afterTransition) % (math.pi * 2),
        closeTo(.3 * math.pi, .001),
      );
      controller.isPlaying = false;
      await tester.runAsync(() => controller.updateFTP(200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase(), beforePause);
      final pausedPosition = world().road.position;
      await tester.pump(const Duration(milliseconds: 100));
      expect(world().road.position, pausedPosition);

      await tester.tap(find.byTooltip('Arcade audio'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.widgetWithText(CheckedPopupMenuItem<String>, 'Music'),
            )
            .checked,
        isFalse,
      );
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.widgetWithText(
                CheckedPopupMenuItem<String>,
                'Sound effects',
              ),
            )
            .checked,
        isTrue,
      );
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Sound effects'),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      await tester.tap(find.byTooltip('Arcade audio'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Music'),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      final savedAudio = await ArcadePreferences.load();
      expect(savedAudio.musicEnabled, isTrue);
      expect(savedAudio.effectsEnabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('How to play'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Crank Quest'), findsOneWidget);
      await tester.tap(find.text('LET’S RIDE'));
      await tester.pumpAndSettle();

      // Exercise the real playfield gesture, with no workout recording timer.
      game.musicEnabled = false;
      game.update(
        segments: controller.segments,
        seconds: controller.workoutProgressSeconds,
        playing: true,
        watts: 100,
        target: 100,
        freshSignal: true,
      );
      controller.isPlaying = true;
      await tester.runAsync(() => controller.updateFTP(200));
      void readyDrone({ArcadeDroneStyle style = ArcadeDroneStyle.wheel}) {
        for (var i = 0; i < 1200 && !game.drones.snapshot().ready; i++) {
          game.drones.update(
            seconds: .05,
            playing: true,
            enabled: true,
            onTarget: true,
            sector: 1,
            style: style,
          );
        }
        expect(game.drones.snapshot().ready, true);
      }

      readyDrone();
      await tester.pump(const Duration(milliseconds: 20));
      final playfield = find.byKey(const ValueKey('arcade-drone-playfield'));
      final sceneSize = tester.getSize(playfield);
      final sceneOrigin = tester.getTopLeft(playfield);
      final dronePose = world().droneLayout(sceneSize)!;
      await tester.tapAt(sceneOrigin + dronePose.position);
      await tester.pump();
      expect(game.drones.snapshot().phase, ArcadeDronePhase.firing);
      expect(game.drones.snapshot().shotHit, true);
      readyDrone();
      await tester.pump(const Duration(milliseconds: 20));
      final miss = Offset(12, sceneSize.height * .45);
      expect(world().droneLayout(sceneSize)!.contains(miss), false);
      await tester.tapAt(sceneOrigin + miss);
      await tester.pump();
      expect(game.drones.snapshot().phase, ArcadeDronePhase.firing);
      expect(game.drones.snapshot().shotHit, false);

      readyDrone(style: ArcadeDroneStyle.golem);
      await tester.pump(const Duration(milliseconds: 20));
      final bossPose = world().droneLayout(sceneSize)!;
      expect(bossPose.frame.isBoss, true);
      final head = bossPose.position + Offset(0, -35 * bossPose.bodyScale);
      await tester.tapAt(sceneOrigin + head);
      await tester.pump();
      expect(game.drones.snapshot().phase, ArcadeDronePhase.firing);
      expect(game.drones.snapshot().shotHit, true);

      await tester.tap(find.byTooltip('Return to Classic'));
      expect(exits, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );
}
