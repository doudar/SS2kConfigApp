// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'package:flutter/material.dart';
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
      });
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
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WorkoutScreen(device: device),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WorkoutLobby), findsOneWidget);
      expect(controller.isPlaying, isFalse);
      expect(find.byTooltip('Play').hitTestable(), findsNothing);
      // Changing FTP in the lobby also updates the preserved in-ride wheel.
      await controller.updateFTP(250);
      await tester.pump();
      await tester.pump();
      final wheel = tester.widget<ListWheelScrollView>(
        find.byType(ListWheelScrollView),
      );
      expect(
        (wheel.controller! as FixedExtentScrollController).selectedItem,
        200,
      );
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
      expect(find.byType(WorkoutControls), findsOneWidget);
      final progress = controller.workoutProgressSeconds;
      expect(progress, greaterThan(0));
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.isPlaying, isFalse);
      expect(find.byType(WorkoutLobby), findsNothing);
      expect(controller.workoutProgressSeconds, progress);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Play'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.isPlaying, isTrue);
      expect(controller.workoutProgressSeconds, greaterThanOrEqualTo(progress));
      expect(find.byType(WorkoutLobby), findsNothing);
      await controller.stopWorkout();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
    },
  );
}
