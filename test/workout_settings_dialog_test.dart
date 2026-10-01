import 'dart:io';
import 'dart:convert';
import 'package:ss2kconfigapp/widgets/workout_library.dart';
import 'package:ss2kconfigapp/utils/workout/workout_storage.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_tts_settings.dart';
import 'package:ss2kconfigapp/widgets/audio_coach_dialog.dart';
import 'package:ss2kconfigapp/widgets/workout_dialog.dart';
import 'package:ss2kconfigapp/widgets/workout_ftp_dialog.dart';
import 'package:ss2kconfigapp/widgets/workout_menu.dart';

class _Controller implements WorkoutController {
  @override
  bool isPlaying = false;
  @override
  double workoutProgressSeconds = 0;
  @override
  double ftpValue = 200;
  String? loaded;
  @override
  void loadWorkout(String xmlContent, {bool isResume = false}) {
    loaded = xmlContent;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Data implements DeviceData {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_WORKOUT_SETTINGS');
  late WorkoutTTSSettings tts;
  late _Controller controller;
  final boundaryKey = GlobalKey();

  setUp(() async {
    controller = _Controller();
    SharedPreferences.setMockInitialValues({
      'saved_workouts': jsonEncode([
        {
          'name': WorkoutStorage.defaultWorkoutName,
          'content':
              '<workout_file><name>Test ride</name><workout><SteadyState Duration="600" Power="0.6"/></workout></workout_file>',
          'timestamp': 0,
        },
      ]),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          call,
        ) async {
          if (call.method == 'getVoices')
            return [
              {
                'name': 'A long voice name that should fit on a phone',
                'locale': 'en-US',
              },
            ];
          if (call.method == 'getEngines') return <String>[];
          return 1;
        });
    tts = await WorkoutTTSSettings.create();
  });

  tearDown(() => tts.dispose());

  Future<void> host(
    WidgetTester tester, {
    Widget? dialog,
    Brightness brightness = Brightness.light,
    double scale = 1,
    ValueChanged<Object?>? onResult,
    bool browse = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundaryKey, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: browse
                ? TextButton(
                    onPressed: () => WorkoutMenu(
                      workoutController: controller,
                      deviceData: _Data(),
                      device: BluetoothDevice.fromId('workout-settings-test'),
                      ttsSettings: tts,
                      onWorkoutLoaded: (_, {name}) {},
                    ).showWorkoutLibrary(context),
                    child: const Text('Browse'),
                  )
                : dialog == null
                ? WorkoutMenu(
                    workoutController: controller,
                    deviceData: _Data(),
                    device: BluetoothDevice.fromId('workout-settings-test'),
                    ttsSettings: tts,
                    onWorkoutLoaded: (_, {name}) {},
                  )
                : TextButton(
                    onPressed: () async {
                      final result = await showDialog<Object>(
                        context: context,
                        builder: (_) => dialog,
                      );
                      onResult?.call(result);
                    },
                    child: const Text('OPEN'),
                  ),
          ),
        ),
      ),
    );
    await tester.tap(
      browse
          ? find.text('Browse')
          : dialog == null
          ? find.byTooltip('Workout Menu')
          : find.text('OPEN'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openGroup(WidgetTester tester, String item) async {
    final group = switch (item) {
      'Voice coach' ||
      'On-screen messages' ||
      'Power target (FTP)' ||
      'Trainer setup' => 'Ride settings',
      'Connected apps' || 'Past rides' => 'My training',
      _ => null,
    };
    if (group != null) await tapVisible(tester, find.text(group));
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/workout-settings-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'workout menus fit light and dark phones, landscape and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      if (capture)
        await tester.runAsync(() async {
          await (FontLoader('Roboto')..addFont(
                File(
                  'C:/Windows/Fonts/segoeui.ttf',
                ).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      for (final size in [
        const Size(320, 568),
        const Size(844, 330),
        const Size(1200, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final brightness in Brightness.values) {
          for (final entry in {
            'Voice coach': 'Voice coach',
            'On-screen messages': 'On-screen messages',
            'Connected apps': 'Connected apps',
            'Choose a workout': 'Choose a workout',
          }.entries) {
            await host(tester, brightness: brightness, scale: capture ? 1 : 2);
            expect(tester.takeException(), isNull);
            if (entry.key == 'Voice coach')
              await screenshot(
                tester,
                'menu-${size.width.toInt()}-${brightness.name}',
              );
            await openGroup(tester, entry.key);
            await tapVisible(tester, find.text(entry.key));
            expect(
              find.descendant(
                of: find.byType(WorkoutDialog).last,
                matching: find.text(entry.value),
              ),
              findsOneWidget,
            );
            expect(find.byType(WorkoutDialog), findsNWidgets(2));
            expect(tester.takeException(), isNull);
            await screenshot(
              tester,
              '${entry.key.replaceAll(' ', '-').toLowerCase()}-${size.width.toInt()}-${brightness.name}',
            );
            final close = find.text('CLOSE');
            if (close.evaluate().isNotEmpty) {
              await tapVisible(tester, close);
            } else {
              await tapVisible(tester, find.byTooltip('Close').last);
            }
            expect(find.byType(WorkoutDialog), findsOneWidget);
            expect(find.text('Ride menu'), findsOneWidget);
            await tapVisible(tester, find.text('Back to ride'));
            expect(find.byType(WorkoutDialog), findsNothing);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets('text and audio changes persist through the shared controls', (
    tester,
  ) async {
    await host(tester);
    await openGroup(tester, 'On-screen messages');
    await tapVisible(tester, find.text('On-screen messages'));
    final fontSlider = find.byType(Slider).first;
    await tester.ensureVisible(fontSlider);
    await tester.drag(fontSlider, const Offset(80, 0));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble('workout_text_size'),
      tester.widget<Slider>(fontSlider).value,
    );
    expect(prefs.getDouble('workout_text_size'), isNotNull);
    await tapVisible(tester, find.text('CLOSE'));
    await tapVisible(tester, find.text('Back to ride'));
    await host(tester, dialog: AudioCoachDialog(ttsSettings: tts));
    await tapVisible(tester, find.byType(Slider).first);
    expect(prefs.getDouble('workout_tts_volume'), .5);
    await tapVisible(tester, find.text('Enable Audio Coach'));
    expect(prefs.getBool('workout_tts_enabled'), isFalse);
    expect(find.byType(Slider), findsNothing);
    await tapVisible(tester, find.text('CLOSE'));
  });

  testWidgets(
    'system back returns to the expanded menu without touching a ride',
    (tester) async {
      controller.isPlaying = true;
      controller.workoutProgressSeconds = 300;
      await host(tester);
      await openGroup(tester, 'Voice coach');
      await tapVisible(tester, find.text('Voice coach'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutDialog), findsOneWidget);
      expect(find.text('On-screen messages'), findsOneWidget);
      expect(controller.isPlaying, isTrue);
      expect(controller.workoutProgressSeconds, 300);
      expect(controller.loaded, isNull);
      await tapVisible(tester, find.text('Back to ride'));
    },
  );

  testWidgets('Just ride is easy before starting and protects an active ride', (
    tester,
  ) async {
    await host(tester);
    await tapVisible(tester, find.text('Just ride'));
    expect(controller.loaded, contains('<FreeRide'));
    expect(find.text('Switch workouts?'), findsNothing);
    expect(controller.isPlaying, isFalse);
    await tapVisible(tester, find.text('Back to ride'));

    controller.loaded = null;
    controller.isPlaying = true;
    controller.workoutProgressSeconds = 300;
    await host(tester);
    await tapVisible(tester, find.text('Just ride'));
    expect(find.text('Switch workouts?'), findsOneWidget);
    await tapVisible(tester, find.text('Keep current ride'));
    expect(controller.loaded, isNull);
    expect(controller.isPlaying, isTrue);
    expect(find.byType(WorkoutDialog), findsOneWidget);
    await tapVisible(tester, find.text('Back to ride'));
  });

  testWidgets(
    'landing-page browsing and bundled library both return to the hub',
    (tester) async {
      await tester.runAsync(() => WorkoutLibrary.loadAssetWorkouts());
      await host(tester, browse: true);
      expect(find.byType(WorkoutDialog), findsNWidgets(2));
      expect(find.text('Import a workout file'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Close').last);
      expect(find.byType(WorkoutDialog), findsOneWidget);
      expect(find.text('Ride menu'), findsOneWidget);
      await tapVisible(tester, find.text('Choose a workout'));
      await tapVisible(tester, find.text('SmartSpin2k Library'));
      expect(find.text('Workout Library'), findsOneWidget);
      await tapVisible(tester, find.text('CLOSE'));
      expect(find.byType(WorkoutDialog), findsOneWidget);
      expect(find.text('Ride menu'), findsOneWidget);
      await tapVisible(tester, find.text('Back to ride'));
    },
  );

  testWidgets('imported-workout arrow stays above working selection controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_workouts',
      jsonEncode([
        for (var i = 0; i < 12; i++)
          {
            'name': i == 0
                ? WorkoutStorage.defaultWorkoutName
                : 'Imported ride $i',
            'content':
                '<workout_file><name>Test ride</name><workout/></workout_file>',
            'timestamp': i,
          },
      ]),
    );
    for (final scale in [1.0, 2.0]) {
      await host(tester, scale: scale);
      await tapVisible(tester, find.text('Choose a workout'));
      await tester.ensureVisible(find.text('Select All'));
      await tester.pumpAndSettle();
      final toolbar = find
          .ancestor(of: find.text('Select All'), matching: find.byType(Wrap))
          .first;
      final arrow = find.descendant(
        of: find.byType(WorkoutLibrary),
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      expect(arrow, findsOneWidget);
      expect(
        tester.getRect(arrow).bottom,
        lessThan(tester.getRect(toolbar).top),
      );
      await tester.tap(
        find.descendant(of: toolbar, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('DELETE'));
      expect(find.text('Delete 11 selected workouts?'), findsOneWidget);
      await tapVisible(tester, find.text('CANCEL'));
      await tapVisible(tester, find.byTooltip('Close').last);
      await tapVisible(tester, find.text('Back to ride'));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('FTP cancel discards edits and Apply returns the chosen value', (
    tester,
  ) async {
    for (final apply in [false, true]) {
      Object? result;
      await host(
        tester,
        dialog: const WorkoutFtpDialog(initialFtp: 200),
        onResult: (value) => result = value,
      );
      await tapVisible(tester, find.byType(Slider));
      await tapVisible(tester, find.text(apply ? 'Apply' : 'Cancel'));
      expect(result, apply ? 275.0 : null);
    }
  });

  testWidgets(
    'account disconnection requires confirmation and refreshes status',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('strava_access_token', 'test-token');
      await host(tester);
      await openGroup(tester, 'Connected apps');
      await tapVisible(tester, find.text('Connected apps'));
      await tapVisible(tester, find.text('Strava'));
      await tapVisible(tester, find.text('CANCEL'));
      expect(prefs.getString('strava_access_token'), 'test-token');
      await tapVisible(tester, find.text('Strava'));
      await tapVisible(tester, find.text('DISCONNECT'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(prefs.getString('strava_access_token'), isNull);
      expect(find.text('Connect with Strava'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Close').last);
    },
  );
}
