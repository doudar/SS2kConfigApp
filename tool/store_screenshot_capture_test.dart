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
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/screens/workout_screen.dart';
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

const _captureKey = ValueKey<String>('store-screenshot-boundary');

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

class _CaptureTarget {
  const _CaptureTarget(this.folder, this.logicalSize, this.outputSize);

  final String folder;
  final Size logicalSize;
  final Size outputSize;
}

const _targets = <_CaptureTarget>[
  _CaptureTarget('ios_iphone', Size(660, 1434), Size(1320, 2868)),
  _CaptureTarget('ios_ipad', Size(1376, 1032), Size(2752, 2064)),
  _CaptureTarget('macos', Size(1440, 900), Size(2880, 1800)),
  _CaptureTarget('android_phone', Size(540, 960), Size(1080, 1920)),
];

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _loadCaptureFonts() async {
  // flutter_test defaults to the block-shaped Ahem font. Load a normal system
  // face plus Flutter's icon font so the capture matches the running app.
  await _loadFont('Ahem', '/System/Library/Fonts/Supplemental/Arial.ttf');
  await _loadFont('StoreSans', '/System/Library/Fonts/Supplemental/Arial.ttf');
  await _loadFont(
    'MaterialIcons',
    '/Users/anthonydoud/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

Future<ThemeData> _loadDarkTheme(WidgetTester tester) async {
  final provider = ThemeProvider();
  for (
    var attempt = 0;
    attempt < 100 && provider.darkTheme == null;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  final theme = provider.darkTheme;
  if (theme == null) {
    throw StateError('SmartSpin2k dark theme did not finish loading.');
  }
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'StoreSans'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'StoreSans'),
  );
}

void _seedStoreDemoData(DeviceData data) {
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
  _CaptureTarget target,
  String slug,
) async {
  final boundary =
      find.byKey(_captureKey).evaluate().single.renderObject!
          as RenderRepaintBoundary;
  final outputPath =
      '${Directory.current.path}/store_assets/source/flutter/${target.folder}/$slug.png';
  final wroteImage = await tester.runAsync<bool>(() async {
    final rawImage = await boundary.toImage(pixelRatio: 2);
    final outputWidth = target.outputSize.width.round();
    final outputHeight = target.outputSize.height.round();
    ui.Image outputImage = rawImage;

    if (rawImage.width != outputWidth || rawImage.height != outputHeight) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        rawImage,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint(),
      );
      outputImage = await recorder.endRecording().toImage(
        outputWidth,
        outputHeight,
      );
      rawImage.dispose();
    }

    final byteData = await outputImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    outputImage.dispose();
    if (byteData == null) return false;

    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return true;
  });
  if (wroteImage != true) throw StateError('Flutter returned no PNG data.');

  // ignore: avoid_print
  print('Captured $outputPath');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlusPlatform.instance = _ScreenshotBlePlatform();
  WakelockPlusPlatformInterface.instance = _ScreenshotWakelockPlatform();

  testWidgets('capture real Flutter store screens', (tester) async {
    await _loadCaptureFonts();
    power_table_painter.debugPowerTablePainterFontFamily = 'StoreSans';
    workout_painter.debugWorkoutPainterFontFamily = 'StoreSans';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          call,
        ) async {
          if (call.method == 'getVoices' || call.method == 'getEngines') {
            return <Object>[];
          }
          return 1;
        });
    final workoutContent = File(
      '${Directory.current.path}/assets/Anthonys_Mix.zwo',
    ).readAsStringSync();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_mode': ThemeMode.dark.toString(),
      'workout_tts_enabled': false,
      'power_table_swap_axes': false,
      'workout_content': workoutContent,
    });

    final theme = await _loadDarkTheme(tester);
    final device = BluetoothDevice(
      remoteId: const DeviceIdentifier('SmartSpin2k'),
    );
    final deviceData = DeviceDataManager.forDevice(device);
    _seedStoreDemoData(deviceData);
    final workoutController = WorkoutController(deviceData, device);
    await workoutController.restoreSavedWorkoutState();

    final screens = <String, Widget Function()>{
      'settings': () => SettingsScreen(device: device),
      'shifting': () => ShifterScreen(device: device),
      'power-curve': () => PowerTableScreen(device: device),
    };

    for (final target in _targets) {
      tester.view.devicePixelRatio = 1;

      for (final entry in screens.entries) {
        tester.view.physicalSize = target.logicalSize;
        // ignore: avoid_print
        print('Rendering ${target.folder}/${entry.key}');
        await tester.pumpWidget(
          _captureApp(theme: theme, screen: entry.value()),
        );
        await _pumpStableFrame(tester, entry.key);
        await _writeCapture(tester, target, entry.key);

        // Dispose timers, stream listeners, and animation controllers before
        // moving to the next real screen.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    // WorkoutSoundGenerator owns one process-wide AudioPlayer. Keep one real
    // WorkoutScreen mounted while changing viewports so its singleton is only
    // disposed once, exactly as it would be during a normal navigation visit.
    final firstTarget = _targets.first;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = firstTarget.logicalSize;
    // ignore: avoid_print
    print('Rendering ${firstTarget.folder}/workout');
    await tester.pumpWidget(
      _captureApp(
        theme: theme,
        screen: WorkoutScreen(device: device),
      ),
    );
    await _pumpStableFrame(tester, 'workout');
    await _writeCapture(tester, firstTarget, 'workout');

    for (final target in _targets.skip(1)) {
      tester.view.physicalSize = target.logicalSize;
      // ignore: avoid_print
      print('Rendering ${target.folder}/workout');
      await tester.pump();
      await _pumpStableFrame(tester, 'workout');
      await _writeCapture(tester, target, 'workout');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    expect(binding, isNotNull);
  });
}
