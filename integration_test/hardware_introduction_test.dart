import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ss2kconfigapp/main.dart' as app;
import 'package:ss2kconfigapp/screens/onboarding/steps/welcome_step.dart';
import 'package:ss2kconfigapp/screens/scan_screen.dart';
import 'package:ss2kconfigapp/screens/main_device_screen.dart';
import 'package:ss2kconfigapp/screens/settings_screen.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/screens/power_table_screen.dart';
import 'package:ss2kconfigapp/screens/workout_screen.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch, guided setup and demo device navigation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // The app has no just_audio Windows backend. Keep this UI walkthrough
    // independent of sound playback without hiding other platform failures.
    if (Platform.isWindows) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (call) async {
          if (call.method == 'init') {
            final id = call.arguments['id'];
            for (final channel in ['methods', 'events', 'data']) {
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                MethodChannel('com.ryanheise.just_audio.$channel.$id'),
                (_) async => <String, dynamic>{},
              );
            }
          }
          return <String, dynamic>{};
        },
      );
    }
    final previousPaths = PathProviderPlatform.instance;
    final directory = await Directory.systemTemp.createTemp('ss2k_intro_flow_');
    PathProviderPlatform.instance = _TestPaths(directory.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previousPaths;
      await directory.delete(recursive: true);
    });
    app.main();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(WelcomeStep), findsOneWidget);
    expect(find.text('Hardware required'), findsOneWidget);
    await tester.tap(find.text('Set up my hardware'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Select Your Bike'), findsOneWidget);
    await tester.tap(find.text('Exit Setup'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ScanScreen), findsOneWidget);

    // Only the existing demo path is used: never discover or control hardware.
    final demoTarget = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector &&
          widget.behavior == HitTestBehavior.translucent,
    );
    for (var i = 0; i < 5; i++) {
      await tester.tap(demoTarget.last);
      await tester.pump();
    }
    await tester.tap(find.text('Tap Here to Enter\n Demo Mode'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('CONNECT'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MainDeviceScreen), findsOneWidget);
    for (final screen in <String, Type>{
      'Settings': SettingsScreen,
      'Virtual Shifter': ShifterScreen,
      'Power Table': PowerTableScreen,
      'Workout': WorkoutScreen,
    }.entries) {
      await tester.tap(find.text(screen.key));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(screen.value), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (screen.value == WorkoutScreen) {
        // The bundled default workout loads through the normal app path.
        final ftp = find.textContaining(' W · Adjust');
        await tester.ensureVisible(ftp);
        await tester.tap(ftp);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Slider), const Offset(20, 0));
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        final start = find.byKey(const ValueKey('workout-lobby-start'));
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        final pause = find.text('PAUSE');
        await tester.ensureVisible(pause);
        await tester.tap(pause);
        await tester.pump();
        expect(find.text('RESUME'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }
  });
}
