// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/workout_screen.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controls.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby.dart';
import 'package:ss2kconfigapp/utils/workout/classic_workout_preview.dart';
import 'package:ss2kconfigapp/utils/workout/workout_painter.dart';
import 'package:ss2kconfigapp/utils/workout/workout_metrics.dart';
import 'package:ss2kconfigapp/widgets/workout_ftp_dialog.dart';
import 'package:ss2kconfigapp/utils/workout/workout_playback_bar.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_workout_frame.dart';
import 'package:ss2kconfigapp/utils/workout/workout_metric_row.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

final class _BlePlatform extends FlutterBluePlusPlatform {}

final class _WakelockPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  testWidgets(
    'Classic lobby starts once and stays out of paused and resumed rides',
    (tester) async {
      // The existing metric tiles use fixed dimensions; render with Flutter's
      // real font rather than the deliberately wide Ahem test font.
      await tester.runAsync(() async {
        var folder = File(Platform.resolvedExecutable).parent;
        while (!File(
              '${folder.path}/material_fonts/roboto-regular.ttf',
            ).existsSync() &&
            folder.parent.path != folder.path) {
          folder = folder.parent;
        }
        final bytes = ByteData.sublistView(
          await File(
            '${folder.path}/material_fonts/roboto-regular.ttf',
          ).readAsBytes(),
        );
        for (final family in ['Ahem', 'Roboto']) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
        await (FontLoader('MaterialIcons')..addFont(
              File(
                '${folder.path}/material_fonts/materialicons-regular.otf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      });
      debugWorkoutPainterFontFamily = 'Roboto';
      addTearDown(() => debugWorkoutPainterFontFamily = null);
      FlutterBluePlusPlatform.instance = _BlePlatform();
      WakelockPlusPlatformInterface.instance = _WakelockPlatform();
      SharedPreferences.setMockInitialValues({'workout_tts_enabled': false});
      final messenger = tester.binding.defaultBinaryMessenger;
      const audioChannel = MethodChannel('com.ryanheise.just_audio.methods');
      messenger.setMockMethodCallHandler(audioChannel, (call) async {
        if (call.method == 'init') {
          throw PlatformException(
            code: 'test',
            message: 'Audio disabled in widget test',
          );
        }
        return <String, Object>{};
      });
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('workout_lobby_'),
      );
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const ttsChannel = MethodChannel('flutter_tts');
      messenger.setMockMethodCallHandler(
        pathChannel,
        (_) async => directory!.path,
      );
      messenger.setMockMethodCallHandler(
        ttsChannel,
        (call) async =>
            call.method == 'getVoices' || call.method == 'getEngines'
            ? <Object>[]
            : 1,
      );
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      final device = BluetoothDevice.fromId('workout-lobby-test');
      final data = DeviceDataManager.forDevice(device)..setupDemoData();
      final controller = WorkoutController(data, device);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        controller.loadWorkout(
          '<workout_file><name>Lobby test</name><workout><SteadyState Duration="600" Power="0.7"/></workout></workout_file>',
        );
      });
      addTearDown(() async {
        controller.cleanup();
        data.dispose();
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(ttsChannel, null);
        messenger.setMockMethodCallHandler(audioChannel, null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await directory!.delete(recursive: true);
      });
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: captureKey,
            child: WorkoutScreen(device: device),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WorkoutLobby), findsOneWidget);
      expect(controller.isPlaying, isFalse);
      expect(find.text('Ride menu'), findsOneWidget);
      await tester.tap(find.text('Arcade mode'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ride menu'), findsOneWidget);
      expect(find.text('Classic mode'), findsOneWidget);
      expect(find.byTooltip('Return to Classic'), findsNothing);
      await tester.tap(find.text('Classic mode'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Ride menu'));
      await tester.pumpAndSettle();
      expect(find.text('Just ride'), findsOneWidget);
      await tester.ensureVisible(find.text('Back to ride'));
      await tester.tap(find.text('Back to ride'));
      await tester.pumpAndSettle();
      expect(controller.isPlaying, isFalse);
      expect(find.text('RESUME').hitTestable(), findsNothing);
      // The compact in-ride FTP action reflects edits made in the lobby.
      await controller.updateFTP(250);
      await tester.pump();
      expect(find.text('FTP 250'), findsOneWidget);
      data.ftmsData.watts = 177;
      data.ftmsData.cadence = 92;
      data.ftmsData.heartRate = 145;
      await tester.runAsync(() async {
        await tester.tap(find.text('START WORKOUT'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      expect(controller.isPlaying, isTrue);
      // File creation ran outside fake async; put the progress timer back on
      // the widget test clock before advancing simulated workout time.
      controller.startProgress();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isPlaying, isTrue);
      expect(find.byType(WorkoutLobby), findsNothing);
      await tester.tap(find.text('Ride menu'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Just ride'), findsOneWidget);
      expect(controller.isPlaying, isTrue);
      await tester.ensureVisible(find.text('Back to ride'));
      await tester.tap(find.text('Back to ride'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.isPlaying, isTrue);
      expect(find.byType(WorkoutControls), findsOneWidget);
      expect(find.byType(ClassicWorkoutPreview), findsOneWidget);
      {
        for (final size in [
          const Size(1200, 900),
          const Size(360, 800),
          const Size(800, 400),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.byType(WorkoutMetrics)).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(WorkoutTraceLegend)).top,
            ),
          );
          expect(find.text('PAUSE').hitTestable(), findsOneWidget);
          final bar = tester.getRect(find.byType(WorkoutPlaybackBar));
          final preview = tester.getRect(find.byType(ClassicWorkoutPreview));
          expect(bar.top, greaterThanOrEqualTo(preview.bottom));
          expect(bar.width, size.width);
          expect(bar.bottom, closeTo(size.height, .01));
          if (const bool.fromEnvironment('CLASSIC_STYLE_SCREENSHOTS'))
            await tester.runAsync(() async {
              final boundary =
                  captureKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'build/classic-screen-${size.width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
        }
        tester.view.physicalSize = const Size(1200, 900);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }
      final progress = controller.workoutProgressSeconds;
      expect(progress, greaterThan(0));
      // Navigation moves into Arcade only while its device header is hidden.
      tester.view.physicalSize = const Size(360, 800);
      await tester.pump();
      await tester.tap(find.text('Arcade mode'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester
            .widget<ArcadeWorkoutFrame>(find.byType(ArcadeWorkoutFrame))
            .expanded,
        isTrue,
      );
      expect(find.text('Ride menu').hitTestable(), findsOneWidget);
      expect(find.text('Classic mode').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Return to Classic').hitTestable(), findsOneWidget);
      if (const bool.fromEnvironment('CLASSIC_STYLE_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/arcade-active-header-actions.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('PAUSE').hitTestable());
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester
            .widget<ArcadeWorkoutFrame>(find.byType(ArcadeWorkoutFrame))
            .expanded,
        isFalse,
      );
      expect(find.byTooltip('Return to Classic'), findsNothing);
      expect(find.text('Classic mode'), findsOneWidget);
      expect(find.text('Ride menu'), findsOneWidget);
      await tester.tap(find.text('Classic mode'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(() async {
        await tester.tap(find.text('RESUME').hitTestable());
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      controller.startProgress();
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('FTP 250'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WorkoutFtpDialog), findsOneWidget);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(260);
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.ftpValue, 260);
      expect(find.text('FTP 260'), findsOneWidget);
      final beforePause = controller.workoutProgressSeconds;
      await tester.tap(find.text('PAUSE'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isPlaying, isFalse);
      expect(find.byType(WorkoutLobby), findsNothing);
      expect(controller.workoutProgressSeconds, beforePause);
      expect(find.text('WORKOUT SUMMARY'), findsOneWidget);
      expect(find.text('PAUSED'), findsOneWidget);
      final summaryMetrics = tester.widgetList<MetricBox>(
        find.byType(MetricBox),
      );
      expect(
        summaryMetrics
            .firstWhere((tile) => tile.metric.label == 'Planned TSS')
            .metric
            .value,
        '8.2',
      );
      expect(
        summaryMetrics
            .firstWhere((tile) => tile.metric.label == 'Planned IF')
            .metric
            .value,
        '0.70',
      );
      for (final size in [
        const Size(320, 568),
        const Size(360, 800),
        const Size(800, 400),
        const Size(1200, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 350));
        final layoutError = tester.takeException();
        expect(find.text('RESUME').hitTestable(), findsOneWidget);
        final panel = tester.getRect(
          find.byKey(const ValueKey('workout-summary-panel')),
        );
        for (final tile in tester.widgetList<MetricBox>(
          find.byType(MetricBox),
        )) {
          final value = tester.getRect(
            find.byKey(ValueKey('metric-value-${tile.metric.label}')),
          );
          expect(value.left, greaterThanOrEqualTo(panel.left));
          expect(value.right, lessThanOrEqualTo(panel.right));
        }
        if (const bool.fromEnvironment('CLASSIC_STYLE_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/workout-summary-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(layoutError, isNull, reason: 'Paused summary at $size');
      }
      await tester.runAsync(() async {
        await tester.tap(find.text('RESUME'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isPlaying, isTrue);
      expect(controller.workoutProgressSeconds, greaterThanOrEqualTo(progress));
      expect(find.byType(WorkoutLobby), findsNothing);
      await tester.runAsync(() => controller.stopWorkout());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
    },
  );
}
