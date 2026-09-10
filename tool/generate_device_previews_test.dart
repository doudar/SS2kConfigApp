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
import 'package:ss2kconfigapp/screens/power_table_screen.dart';
import 'package:ss2kconfigapp/screens/settings_screen.dart';
import 'package:ss2kconfigapp/screens/settings_category_screen.dart';
import 'package:ss2kconfigapp/widgets/setting_tile.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/screens/main_device_screen.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_workout_view.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';
import 'package:ss2kconfigapp/widgets/device_preview_tile.dart';
import 'package:ss2kconfigapp/utils/workout/workout_storage.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/power_table_painter.dart'
    as power_table_painter;
import 'package:ss2kconfigapp/utils/power_table_sharing.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_painter.dart'
    as workout_painter;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

const _captureKey = ValueKey<String>('device-preview-boundary');

// The demo data drives every visible value. Installing the platform-interface
// default keeps BluetoothDevice's connection streams available to production
// widgets without touching host Bluetooth in the headless renderer.
final class _ScreenshotBlePlatform extends FlutterBluePlusPlatform {}

final class _ScreenshotWakelockPlatform extends WakelockPlusPlatformInterface {
  bool _enabled = false;

  @override
  Future<void> toggle({required bool enable}) async => _enabled = enable;

  @override
  Future<bool> get enabled async => _enabled;
}

// Flutter's own fonts make captures portable across build hosts.
Future<void> _loadCaptureFonts() async {
  var folder = File(Platform.resolvedExecutable).parent;
  while (!File(
        '${folder.path}/material_fonts/roboto-regular.ttf',
      ).existsSync() &&
      folder.parent.path != folder.path) {
    folder = folder.parent;
  }
  final regular = ByteData.sublistView(
    File('${folder.path}/material_fonts/roboto-regular.ttf').readAsBytesSync(),
  );
  for (final family in ['Ahem', 'Roboto', 'PreviewSans']) {
    await (FontLoader(family)..addFont(Future.value(regular))).load();
  }
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '${folder.path}/material_fonts/materialicons-regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      ))
      .load();
}

Future<ThemeData> _loadDarkTheme(WidgetTester tester) async {
  final provider = ThemeProvider();
  var ready = false;
  void onLoaded() => ready = true;
  provider.addListener(onLoaded);
  for (var attempt = 0; attempt < 100 && !ready; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  provider.removeListener(onLoaded);
  if (!ready)
    throw StateError('SmartSpin2k dark theme did not finish loading.');
  final theme = provider.darkTheme;
  provider.dispose();
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'PreviewSans'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'PreviewSans'),
  );
}

void _seedPreviewData(DeviceData data) {
  data.setupDemoData();
  data.ftmsData
    ..watts = 247
    ..cadence = 88
    ..heartRate = 142
    ..resistance = 1840
    ..speed = 21;
  data.simulatedTargetWatts = '300';

  for (final characteristic in data.customCharacteristic) {
    final vName = characteristic['vName'];
    if (vName == deviceNameVname) characteristic['value'] = 'SmartSpin2k';
    if (vName == shifterPositionVname) characteristic['value'] = '12';
    if (vName == targetPositionVname) characteristic['value'] = '1840';
    if (vName == simulatedTargetWattsVname) characteristic['value'] = '300';
    if (vName == inclineVname) characteristic['value'] = '2.5';
  }

  // Load a real .ptab fixture shaped to match the smooth cadence arcs used in
  // the store reference artwork. Parsing goes through the production importer.
  final previewPtab = File(
    '${Directory.current.path}/store_assets/source/store-preview.ptab',
  ).readAsStringSync();
  final parsedPtab = PowerTableSharing.parseCSV(previewPtab);
  data.powerTableData = parsedPtab['powerTable'] as List<List<int?>>;
}

Widget _captureApp({required ThemeData theme, required Widget screen}) {
  return RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      initialRoute: '/capture',
      routes: <String, WidgetBuilder>{
        '/': (_) => const Scaffold(body: SizedBox.expand()),
        '/capture': (_) => screen,
      },
    ),
  );
}

Future<void> _pumpStableFrame(WidgetTester tester, String slug) async {
  // Avoid pumpAndSettle: the workout and power-table widgets intentionally
  // contain repeating animations. Advancing a fixed duration makes the
  // capture deterministic and gives async asset/theme setup time to finish.
  final ticks = slug == 'workout' ? 36 : 24;
  for (var tick = 0; tick < ticks; tick++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final exception = tester.takeException();
  if (exception != null) throw exception;
}

Future<void> _writeCapture(
  WidgetTester tester,
  String path, {
  double pixelRatio = 0.5,
}) async {
  final boundary =
      find.byKey(_captureKey).evaluate().single.renderObject!
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Flutter returned no preview image');
    final output = File(path);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes.buffer.asUint8List());
    // ignore: avoid_print
    print('$path: ${bytes.lengthInBytes} bytes');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('render bundled device screen previews', (tester) async {
    FlutterBluePlusPlatform.instance = _ScreenshotBlePlatform();
    WakelockPlusPlatformInterface.instance = _ScreenshotWakelockPlatform();
    await tester.runAsync(_loadCaptureFonts);
    power_table_painter.debugPowerTablePainterFontFamily = 'PreviewSans';
    workout_painter.debugWorkoutPainterFontFamily = 'PreviewSans';
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => call.method == 'getVoices' || call.method == 'getEngines'
          ? <Object>[]
          : 1,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        if (call.method == 'init')
          throw PlatformException(
            code: 'preview',
            message: 'Audio disabled for capture',
          );
        return <String, Object>{};
      },
    );
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('device_previews_'),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory!.path,
    );
    final content = File('assets/Anthonys_Mix.zwo').readAsStringSync();
    SharedPreferences.setMockInitialValues({
      'workout_tts_enabled': false,
      'workout_arcade_music': false,
      'workout_arcade_effects': false,
      'workout_arcade_last_story': 0,
      'power_table_swap_axes': false,
    });
    await WorkoutStorage.saveWorkoutState(
      workoutContent: content,
      progressPosition: 0.05,
      workoutProgressTime: 180,
      skippedTime: 0,
      isPlaying: false,
    );
    final theme = await _loadDarkTheme(tester);
    final device = BluetoothDevice.fromId('SmartSpin2k Demo');
    final data = DeviceDataManager.forDevice(device);
    _seedPreviewData(data);
    final controller = WorkoutController(data, device);
    await controller.restoreSavedWorkoutState();
    final session = ArcadeSession()
      ..effectsEnabled = false
      ..stageOpening(ArcadeStory(0));
    session.update(
      segments: controller.segments,
      seconds: 180,
      playing: true,
      watts: 188,
      target: 190,
      freshSignal: true,
    );
    session.restoreStoryPreference(0);
    controller.isPlaying = true; // Fixed frame; never start the workout clock.
    addTearDown(() async {
      controller.isPlaying = false;
      controller.cleanup();
      data.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      power_table_painter.debugPowerTablePainterFontFamily = null;
      workout_painter.debugWorkoutPainterFontFamily = null;
      for (final channel in [
        'flutter_tts',
        'com.ryanheise.just_audio.methods',
        'plugins.flutter.io/path_provider',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      }
      await directory!.delete(recursive: true);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 600);
    final screens = <String, Widget Function()>{
      'shifter': () => ShifterScreen(device: device),
      'settings': () => SettingsScreen(device: device),
      'power-table': () => PowerTableScreen(device: device),
      'workout': () => Scaffold(
        body: ArcadeWorkoutView(
          controller: controller,
          deviceData: data,
          session: session,
          hasDeviceHeader: true,
          onStop: () {},
          onExit: () {},
        ),
      ),
    };
    for (final entry in screens.entries) {
      if (entry.key == 'workout') {
        data.ftmsData = FtmsData(
          watts: 188,
          targetERG: 190,
          cadence: 88,
          heartRate: 142,
          speed: 21,
          mode: 2,
        );
        controller.currentSegmentTimeRemaining = 120;
        controller.isPlaying = true;
      }
      await tester.pumpWidget(_captureApp(theme: theme, screen: entry.value()));
      await _pumpStableFrame(tester, entry.key);
      await _writeCapture(tester, 'assets/device_previews/${entry.key}.png');
      if (entry.key == 'settings' &&
          const bool.fromEnvironment('SETTINGS_SCREENSHOTS')) {
        for (final size in [
          const Size(320, 568),
          const Size(390, 844),
          const Size(844, 390),
          const Size(1200, 900),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump();
          expect(tester.takeException(), isNull);
          await _writeCapture(
            tester,
            'build/settings-${size.width.toInt()}.png',
            pixelRatio: 1,
          );
        }
        tester.view.physicalSize = const Size(390, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _writeCapture(
          tester,
          'build/settings-large-text.png',
          pixelRatio: 1,
        );
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pump();
        await tester.ensureVisible(find.text('Basic'));
        await tester.tap(find.text('Basic'));
        await _pumpStableFrame(tester, 'settings-category');
        expect(find.byType(SettingsCategoryScreen), findsOneWidget);
        expect(find.byType(SettingTile), findsWidgets);
        await _writeCapture(tester, 'build/settings-basic.png', pixelRatio: 1);
        await tester.tap(find.text('Shift Step'));
        await _pumpStableFrame(tester, 'settings-editor');
        expect(find.byType(SettingEditScreen), findsOneWidget);
        await _writeCapture(tester, 'build/settings-slider.png', pixelRatio: 1);
        await tester.pumpWidget(const SizedBox.shrink());
        final editors = {
          'switch': shiftDirVname,
          'text': deviceNameVname,
          'password': passwordVname,
          'bluetooth': connectedPWRVname,
        };
        for (final editor in editors.entries) {
          final setting = data.customCharacteristic.firstWhere(
            (c) => c['vName'] == editor.value,
          );
          await tester.pumpWidget(
            _captureApp(
              theme: theme,
              screen: SettingEditScreen(device: device, c: setting),
            ),
          );
          await _pumpStableFrame(tester, 'settings-editor');
          await _writeCapture(
            tester,
            'build/settings-${editor.key}.png',
            pixelRatio: 1,
          );
          tester.view.physicalSize = const Size(320, 568);
          tester.platformDispatcher.textScaleFactorTestValue = 1.8;
          await tester.pump();
          expect(tester.takeException(), isNull);
          await _writeCapture(
            tester,
            'build/settings-${editor.key}-large.png',
            pixelRatio: 1,
          );
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        tester.view.physicalSize = const Size(960, 600);
      }
      if (entry.key == 'power-table' &&
          const bool.fromEnvironment('POWER_TABLE_SCREENSHOTS')) {
        for (final size in [
          const Size(320, 568),
          const Size(390, 844),
          const Size(844, 390),
          const Size(1200, 900),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump();
          expect(tester.takeException(), isNull);
          await _writeCapture(
            tester,
            'build/power-table-${size.width.toInt()}.png',
            pixelRatio: 1,
          );
        }
        tester.view.physicalSize = const Size(390, 844);
        await tester.pump();
        await tester.tap(find.text('Swap axes'));
        await tester.pump();
        expect(find.text('X: Resistance · Y: Power'), findsOneWidget);
        await _writeCapture(
          tester,
          'build/power-table-swapped.png',
          pixelRatio: 1,
        );
        await tester.tap(find.text('Table tools'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Power Table Management'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await _writeCapture(
          tester,
          'build/power-table-tools.png',
          pixelRatio: 1,
        );
        Navigator.of(tester.element(find.text('Power Table Management'))).pop();
        await _pumpStableFrame(tester, 'menu-close');
        expect(find.text('Power Table Management'), findsNothing);
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _writeCapture(
          tester,
          'build/power-table-large-text.png',
          pixelRatio: 1,
        );
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = const Size(960, 600);
      }
      if (entry.key == 'shifter' &&
          const bool.fromEnvironment('SHIFTER_SCREENSHOTS')) {
        for (final size in [
          const Size(320, 568),
          const Size(390, 844),
          const Size(844, 390),
          const Size(1200, 900),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump();
          expect(tester.takeException(), isNull);
          await _writeCapture(
            tester,
            'build/shifter-${size.width.toInt()}.png',
            pixelRatio: 1,
          );
        }
        tester.view.physicalSize = const Size(390, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _writeCapture(
          tester,
          'build/shifter-large-text.png',
          pixelRatio: 1,
        );
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = const Size(960, 600);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
    }
    final previewBytes = screens.keys.fold<int>(
      0,
      (total, slug) =>
          total + File('assets/device_previews/$slug.png').lengthSync(),
    );
    expect(
      previewBytes,
      lessThan(200 * 1024),
      reason: 'Keep all four bundled previews below 200 KiB.',
    );
    // Optional dashboard QA captures; excluded from the distributed app.
    if (const bool.fromEnvironment('DEVICE_DASHBOARD_SCREENSHOTS')) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(1200, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          _captureApp(
            theme: theme,
            screen: MainDeviceScreen(device: device),
          ),
        );
        final context = tester.element(find.byType(MainDeviceScreen));
        await tester.runAsync(() async {
          for (final slug in screens.keys) {
            await precacheImage(
              ResizeImage(
                AssetImage('assets/device_previews/$slug.png'),
                width: 480,
              ),
              context,
            );
          }
        });
        await _pumpStableFrame(tester, 'dashboard');
        expect(find.byType(DevicePreviewTile), findsNWidgets(4));
        await _writeCapture(
          tester,
          'build/device-dashboard-${size.width.toInt()}.png',
          pixelRatio: 1,
        );
        await tester.ensureVisible(find.text('Maintenance'));
        await tester.tap(find.text('Maintenance'));
        await tester.pump();
        expect(find.text('Calibrate Trainer'), findsOneWidget);
        expect(find.text('Update Firmware'), findsOneWidget);
        expect(find.text('View Logs'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
