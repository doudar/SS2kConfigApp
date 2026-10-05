// ignore_for_file: invalid_use_of_visible_for_testing_member

// Renders the app's real screens with seeded demo data and writes the PNGs
// embedded by the SmartSpin2k documentation site.
//
//   flutter test tool/docs_screenshot_capture_test.dart \
//     --dart-define=DOCS_IMAGES_DIR="D:/git/SS2K-Documentation/images/app"
//
// Without DOCS_IMAGES_DIR the images land in build/docs_screenshots.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/main_device_screen.dart';
import 'package:ss2kconfigapp/screens/onboarding/onboarding_wizard.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/screens/settings_category_screen.dart';
import 'package:ss2kconfigapp/screens/settings_screen.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/utils/ble_scan_results_protocol.dart';
import 'package:ss2kconfigapp/utils/ble_sensor_services.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/demo.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/nearby_ble_devices.dart';
import 'package:ss2kconfigapp/utils/onboarding/onboarding_state.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_session.dart';
import 'package:ss2kconfigapp/utils/theme_provider.dart';
import 'package:ss2kconfigapp/widgets/setting_tile.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

const _captureKey = ValueKey<String>('docs-screenshot-boundary');
const _outputDirectory = String.fromEnvironment(
  'DOCS_IMAGES_DIR',
  defaultValue: 'build/docs_screenshots',
);
const _fontFamily = 'DocsSans';

// A 540x960 logical phone captured at 2x gives the documentation's 1080x1920.
const _logicalSize = Size(540, 960);
const _pixelRatio = 2.0;
const _outputWidth = 1080;
const _outputHeight = 1920;

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

File _findCaptureFont(String name) {
  var folder = File(Platform.resolvedExecutable).parent;
  while (true) {
    // Flutter SDK artifacts can use either casing on case-sensitive hosts.
    for (final filename in [name, name.toLowerCase()]) {
      final file = File('${folder.path}/material_fonts/$filename');
      if (file.existsSync()) return file;
    }
    if (folder.parent.path == folder.path) break;
    folder = folder.parent;
  }
  throw StateError('Could not locate $name in the Flutter SDK.');
}

// Flutter's own Roboto faces make captures portable across build hosts.
// Several weights keep bold labels from being synthesized.
Future<void> _loadCaptureFonts() async {
  final faces = [
    for (final file in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Black.ttf',
    ])
      ByteData.sublistView(_findCaptureFont(file).readAsBytesSync()),
  ];
  for (final family in ['Roboto', _fontFamily]) {
    final loader = FontLoader(family);
    for (final face in faces) {
      loader.addFont(Future.value(face));
    }
    await loader.load();
  }
  await (FontLoader('MaterialIcons')..addFont(
        Future.value(
          ByteData.sublistView(
            _findCaptureFont('MaterialIcons-Regular.otf').readAsBytesSync(),
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
  if (!ready) {
    throw StateError('SmartSpin2k dark theme did not finish loading.');
  }
  final theme = provider.darkTheme;
  provider.dispose();
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: _fontFamily),
  );
}

/// [isHome] renders [screen] as the root route, as the app does for ScanScreen
/// and the first-run wizard. Other screens are pushed above a placeholder so
/// their app bars show the back button they have in the running app.
Widget _captureApp({
  required ThemeData theme,
  required Widget screen,
  bool isHome = false,
}) {
  return RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      themeAnimationDuration: Duration.zero,
      home: isHome ? screen : null,
      initialRoute: isHome ? null : '/capture',
      routes: <String, WidgetBuilder>{
        if (!isHome) '/': (_) => const Scaffold(body: SizedBox.expand()),
        if (!isHome) '/capture': (_) => screen,
      },
    ),
  );
}

Future<void> _pumpStableFrame(WidgetTester tester) async {
  // Never pumpAndSettle: DeviceHeader runs 5 s and 20 s periodic timers, the
  // shifter a 2 s timer, and scan tiles animate. A fixed duration keeps the
  // capture deterministic and gives async setup time to finish.
  for (var tick = 0; tick < 24; tick++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final exception = tester.takeException();
  if (exception != null) throw exception;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ThemeData theme,
  Widget screen, {
  bool isHome = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _logicalSize;
  await tester.pumpWidget(
    _captureApp(theme: theme, screen: screen, isHome: isHome),
  );
  await _pumpStableFrame(tester);
}

/// Disposes timers, stream listeners, and static GlobalKeys (Snackbar keys in
/// ScanScreen and SettingsScreen) before the next screen is mounted.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// Image decoding needs real async work, which the fake-async test zone never
/// performs. Decode the assets once so production Image widgets resolve them
/// synchronously from the image cache.
Future<void> _precacheAssets(WidgetTester tester, ThemeData theme) async {
  // MainDeviceScreen reads its version footer from the bundled pubspec. Test
  // assets load synchronously; caching the string here, in the fake-async zone,
  // lets the screen's FutureBuilder resolve on its first frames. (A future
  // cached inside runAsync would deliver its result to the real event loop.)
  await rootBundle.loadString('pubspec.yaml');

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _logicalSize;
  await tester.pumpWidget(
    _captureApp(
      theme: theme,
      screen: const Scaffold(body: SizedBox.expand()),
    ),
  );
  final context = tester.element(find.byType(Scaffold).last);
  await tester.runAsync(() async {
    final providers = <ImageProvider>[
      // ScanResultTile leading image.
      const AssetImage('assets/ss2kv3.png'),
      // DevicePreviewTile uses Image.asset(cacheWidth: 480).
      for (final slug in ['shifter', 'settings', 'power-table', 'workout'])
        ResizeImage(
          AssetImage('assets/device_previews/$slug.png'),
          width: 480,
        ),
    ];
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
  await _unmount(tester);
}

/// flutter_test paints any paragraph whose style names no font family in its
/// block-glyph FlutterTest font, and FontLoader cannot replace that fallback.
/// A few production styles rely on the platform default family (ScanScreen's
/// AppBar titleTextStyle and the Guided Setup button textStyle), so give those
/// paragraphs the capture font for the frame that is captured. Only the render
/// objects change; the next rebuild restores the production text.
Future<void> _applyCaptureFontToUnstyledText(
  WidgetTester tester,
  RenderObject root,
) async {
  var patched = false;
  void visit(RenderObject object) {
    if (object is RenderParagraph) {
      final text = object.text;
      if (text is TextSpan && text.style?.fontFamily == null) {
        object.text = TextSpan(
          text: text.text,
          children: text.children,
          style: (text.style ?? const TextStyle()).copyWith(
            fontFamily: _fontFamily,
          ),
          recognizer: text.recognizer,
          mouseCursor: text.mouseCursor,
          onEnter: text.onEnter,
          onExit: text.onExit,
          semanticsLabel: text.semanticsLabel,
          semanticsIdentifier: text.semanticsIdentifier,
          locale: text.locale,
          spellOut: text.spellOut,
        );
        patched = true;
      }
    }
    object.visitChildren(visit);
  }

  visit(root);
  if (!patched) return;
  await tester.pump();
  final exception = tester.takeException();
  if (exception != null) throw exception;
}

Future<void> _writeCapture(WidgetTester tester, String slug) async {
  final boundary =
      find.byKey(_captureKey).evaluate().single.renderObject!
          as RenderRepaintBoundary;
  await _applyCaptureFontToUnstyledText(tester, boundary);
  final outputPath = '$_outputDirectory/$slug.png';
  final error = await tester.runAsync<String?>(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    try {
      if (image.width != _outputWidth || image.height != _outputHeight) {
        return 'Expected ${_outputWidth}x$_outputHeight, '
            'got ${image.width}x${image.height}';
      }
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return 'Flutter returned no PNG data';
      final output = File(outputPath);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return null;
    } finally {
      image.dispose();
    }
  });
  if (error != null) throw StateError('$slug: $error');

  // ignore: avoid_print
  print('Captured $outputPath');
}

void _expectTexts(List<String> texts) {
  for (final text in texts) {
    expect(find.text(text), findsOneWidget, reason: text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlusPlatform.instance = _ScreenshotBlePlatform();
  WakelockPlusPlatformInterface.instance = _ScreenshotWakelockPlatform();

  setUp(() => NearbyBleDevices.instance.clear());
  tearDown(() {
    NearbyBleDevices.instance.clear();
    demoModeBypass.value = false;
    DemoDevice.debugAdvertisedName = null;
    OnboardingState.completedNotifier.value = true;
  });

  testWidgets('capture documentation screenshots', (tester) async {
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadCaptureFonts);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'peloton_wifi_warning_suppressed': true,
      'shifter_shift_sound_enabled': false,
    });

    final theme = await _loadDarkTheme(tester);
    await _precacheAssets(tester, theme);

    // The demo id skips the GitHub release check in MainDeviceScreen.
    final device = BluetoothDevice(
      remoteId: const DeviceIdentifier('SmartSpin2k Demo'),
    );
    final data = DeviceDataManager.forDevice(device);
    addTearDown(() {
      DeviceDataManager.clearDataForDevice(device);
      data.dispose();
    });
    Map<String, dynamic> c(String vName) =>
        data.customCharacteristic.firstWhere((m) => m['vName'] == vName);

    // MainDeviceScreen re-runs setupDemoData() for the demo id, which resets
    // every characteristic to its default. Re-apply before each device shot.
    void applySharedSeed() {
      data.setupDemoData(); // isSimulated = true, firmware 24.1.3
      data.ftmsData
        ..watts = 180
        ..cadence = 82
        ..heartRate = 0;
      c(deviceNameVname)['value'] = 'SmartSpin2k';
      c(shifterPositionVname)['value'] = '5';
      c(connectedPWRVname)['value'] = 'none'; // today's firmware default
      c(connectedHRMVname)['value'] = 'none';
      c(ssidVname)['value'] = '';
      c(passwordVname)['value'] = '';
    }

    // Never write foundDevicesVname directly: every screen's initState calls
    // DeviceDataManager.forDevice(), which re-renders that value from an
    // internal map. The saved sensors are reconciled into that map whenever it
    // renders, so set them before clearing, or a previous shot's saved sensor
    // would reappear in the list.
    void seedPicker(List<BleScanDevice> found, {String? pwr, String? hrm}) {
      c(connectedPWRVname)['value'] = pwr ?? 'none';
      c(connectedHRMVname)['value'] = hrm ?? 'none';
      data.clearBleScanResults();
      data.mergeAppDiscoveredBleDevices(found);
    }

    // --- wizard-welcome-exit -------------------------------------------------
    OnboardingState.completedNotifier.value = false;
    await _pumpScreen(
      tester,
      theme,
      ChangeNotifierProvider(
        create: (_) => WizardSession(),
        child: const OnboardingWizard(),
      ),
      isHome: true,
    );
    _expectTexts([
      'Welcome',
      'Exit Setup',
      "Let's set up your SmartSpin2k",
      'Select your bike type',
      'Install the SmartSpin2k hardware',
      'Connect your SmartSpin2k via Bluetooth',
      'Pair and verify your data source',
      'Optionally add heart rate and WiFi',
    ]);
    await _writeCapture(tester, 'wizard-welcome-exit');
    await _unmount(tester);
    OnboardingState.completedNotifier.value = true;

    // --- scan-empty ----------------------------------------------------------
    await _pumpScreen(tester, theme, const ScanScreen(), isHome: true);
    _expectTexts([
      'Find Your SmartSpin2k:',
      'SCAN',
      'Guided Setup',
      'Having Trouble?',
    ]);
    await _writeCapture(tester, 'scan-empty');

    // --- scan-found (same mounted ScanScreen) --------------------------------
    DemoDevice.debugAdvertisedName = 'SmartSpin2k';
    final demoButton = find.textContaining('Demo Mode');
    for (final target in const [Offset(40, 940), Offset(10, 955)]) {
      for (var tap = 0; tap < 5; tap++) {
        await tester.tapAt(target);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();
      if (demoButton.evaluate().isNotEmpty) break;
    }
    expect(demoButton, findsOneWidget);
    await tester.tap(demoButton);
    await _pumpStableFrame(tester);
    _expectTexts(['Find Your SmartSpin2k:', 'SmartSpin2k', 'CONNECT']);
    expect(find.text('SmartSpin2k Demo'), findsNothing);
    expect(find.text('Signal strength:'), findsOneWidget);
    await _writeCapture(tester, 'scan-found');
    await _unmount(tester);
    // DropdownCard hides SCAN while the process-global bypass is set.
    demoModeBypass.value = false;
    DemoDevice.debugAdvertisedName = null;

    // --- device --------------------------------------------------------------
    applySharedSeed();
    await _pumpScreen(tester, theme, MainDeviceScreen(device: device));
    _expectTexts([
      'Device',
      'SmartSpin2k',
      '24.1.3',
      'Virtual Shifter',
      'Settings',
      'Power Table',
      'Workout',
      'Maintenance',
    ]);
    expect(find.text('App Version: unknown'), findsNothing);
    expect(find.textContaining('App Version:'), findsOneWidget);
    await _writeCapture(tester, 'device');

    // --- device-maintenance (same mounted MainDeviceScreen) ------------------
    await tester.tap(find.text('Maintenance'));
    await _pumpStableFrame(tester);
    _expectTexts(['Calibrate Trainer', 'Update Firmware', 'View Logs']);
    await _writeCapture(tester, 'device-maintenance');
    await _unmount(tester);

    // --- settings ------------------------------------------------------------
    applySharedSeed();
    await _pumpScreen(tester, theme, SettingsScreen(device: device));
    _expectTexts(['Settings', 'Basic', 'Bluetooth', 'Network', 'Advanced']);
    await _writeCapture(tester, 'settings');
    await _unmount(tester);

    // --- settings-bluetooth --------------------------------------------------
    applySharedSeed();
    await _pumpScreen(
      tester,
      theme,
      SettingsCategoryScreen(
        device: device,
        title: 'Bluetooth',
        settingType: SettingType.bluetooth,
      ),
    );
    _expectTexts(['Bluetooth', 'Saved Power Meter', 'Saved HRM']);
    await _writeCapture(tester, 'settings-bluetooth');
    await _unmount(tester);

    // --- saved power meter pickers -------------------------------------------
    final pickerShots = <String, (List<BleScanDevice>, String)>{
      'saved-power-meter-ic4': (
        const [
          BleScanDevice(uuid: bleCyclingPowerDeviceUuid, name: 'IC Bike'),
          BleScanDevice(uuid: bleCyclingPowerDeviceUuid, name: 'ASSIOMA 12345'),
        ],
        'IC Bike',
      ),
      'saved-power-meter-grupetto': (
        const [
          BleScanDevice(
            uuid: bleFitnessMachineDeviceUuid,
            name: 'Grupetto FTMS',
          ),
          BleScanDevice(uuid: bleCyclingPowerDeviceUuid, name: 'ASSIOMA 12345'),
        ],
        'Grupetto FTMS',
      ),
      'saved-power-meter-pedals': (
        const [
          BleScanDevice(uuid: bleCyclingPowerDeviceUuid, name: 'ASSIOMA 12345'),
          BleScanDevice(uuid: bleCyclingPowerDeviceUuid, name: 'IC Bike'),
        ],
        'ASSIOMA 12345',
      ),
    };
    for (final shot in pickerShots.entries) {
      final (found, saved) = shot.value;
      applySharedSeed();
      seedPicker(found, pwr: saved);
      await _pumpScreen(
        tester,
        theme,
        SettingEditScreen(device: device, c: c(connectedPWRVname)),
      );
      _expectTexts([
        'Edit Setting',
        'Saved Power Meter',
        'Current: $saved',
        'any',
        'none',
        for (final sensor in found) sensor.name,
        'SCAN',
        'Clear Scan Results',
        'BACK',
        'SAVE',
      ]);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await _writeCapture(tester, shot.key);
      await _unmount(tester);
    }

    // --- saved-hrm -----------------------------------------------------------
    applySharedSeed();
    seedPicker(const [
      BleScanDevice(uuid: bleHeartRateDeviceUuid, name: 'Polar H10 ABC123'),
    ], hrm: 'Polar H10 ABC123');
    await _pumpScreen(
      tester,
      theme,
      SettingEditScreen(device: device, c: c(connectedHRMVname)),
    );
    _expectTexts([
      'Edit Setting',
      'Saved HRM',
      'Current: Polar H10 ABC123',
      'any',
      'none',
      'Polar H10 ABC123',
      'SCAN',
      'Clear Scan Results',
      'BACK',
      'SAVE',
    ]);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await _writeCapture(tester, 'saved-hrm');
    await _unmount(tester);

    // --- settings-basic ------------------------------------------------------
    applySharedSeed();
    await _pumpScreen(
      tester,
      theme,
      SettingsCategoryScreen(
        device: device,
        title: 'Basic',
        settingType: SettingType.basic,
      ),
    );
    _expectTexts([
      'Basic',
      'Shift Step',
      'Swap Shifter Direction',
      'Simulated Groupset',
    ]);
    await _writeCapture(tester, 'settings-basic');
    await _unmount(tester);

    // --- swap-shifter-direction ----------------------------------------------
    applySharedSeed();
    await _pumpScreen(
      tester,
      theme,
      SettingEditScreen(device: device, c: c(shiftDirVname)),
    );
    _expectTexts([
      'Edit Setting',
      'Swap Shifter Direction',
      'On',
      'BACK',
      'SAVE',
    ]);
    expect(find.byType(Switch), findsOneWidget);
    await _writeCapture(tester, 'swap-shifter-direction');
    await _unmount(tester);

    // --- wifi-network --------------------------------------------------------
    applySharedSeed();
    await _pumpScreen(
      tester,
      theme,
      SettingEditScreen(device: device, c: c(ssidVname)),
    );
    _expectTexts([
      'WiFi network',
      'Network name (SSID)',
      'Password',
      'Save to SmartSpin2k',
    ]);
    await _writeCapture(tester, 'wifi-network');
    await _unmount(tester);

    // --- virtual-shifter-live ------------------------------------------------
    applySharedSeed();
    await _pumpScreen(tester, theme, ShifterScreen(device: device));
    _expectTexts([
      'Virtual Shifter',
      'DEMO',
      'POWER',
      '180',
      'W',
      'CADENCE',
      '82',
      'rpm',
      'VIRTUAL GEAR',
      'Shift down',
      'Shift up',
      'INCLINE',
      'TRAVEL',
    ]);
    expect(find.text('5'), findsWidgets);
    await _writeCapture(tester, 'virtual-shifter-live');
    await _unmount(tester);
  });
}
