import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_file_exporter.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:fit_tool/fit_tool.dart';
import 'package:flutter/services.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  Directory? tempDir;

  setUp(() async {
    // Set up shared preferences mock
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('ss2k_test');
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDir!.path;
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempDir != null && await tempDir!.exists()) {
      await tempDir!.delete(recursive: true);
    }
  });

  test('Generate 1-hour ERG workout FIT file', () async {
    // Create a constant power workout XML content
    final workoutContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <author>Test</author>
    <name>2 Hour 300W Test</name>
    <description>2 hour constant power test at 300W</description>
    <sportType>bike</sportType>
    <workout>
        <SteadyState Duration="7200" Power="1.0" />
    </workout>
</workout_file>
''';

    // Create mock BLE device and data
    final mockDevice = BluetoothDevice.fromId('00:00:00:00:00:00');
    final deviceData = DeviceDataManager.forDevice(mockDevice);

    // Initialize FTMS data
    deviceData.ftmsData = FtmsData();

    // Create workout controller with 300W FTP
    final workoutController = WorkoutController(deviceData, mockDevice);
    workoutController.updateFTP(300.0); // Set FTP to 300W for 1.0 power = 300W

    // Load and start the workout
    workoutController.loadWorkout(workoutContent);
    await workoutController.togglePlayPause(); // Start the workout

    final startTime = DateTime.now();

    // Simulate the workout data - one data point per second for 2 hours
    for (var i = 0; i < 1200; i++) {
      // Update mock BLE data
      deviceData.ftmsData.watts = 300;
      deviceData.ftmsData.cadence = 90;
      deviceData.ftmsData.heartRate = 170;

      // Create track point with proper timestamp
      final currentTime = startTime.add(Duration(seconds: i));
      workoutController.trackPoints.add(
        TrackPoint(
          timestamp: currentTime,
          power: 300,
          cadence: 90,
          heartRate: 170,
          lat: 0,
          lon: 0,
          elevation: 0,
          speed: 8.33, // ~30 km/h
        ),
      );

      // Update progress (using total duration from workout XML)
      workoutController.progressPosition = i / 7200;

      // Only wait a small amount to keep test runtime reasonable
      if (i % 60 == 0) {
        // Update every minute in test time
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    // Stop the workout
    await workoutController.stopWorkout();

    // Export to GPX
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final gpxFileName = 'workout_${timestamp}.gpx';
    final workoutsDir = Directory(path.join(Directory.current.path, 'test'));
    if (!await workoutsDir.exists()) {
      await workoutsDir.create(recursive: true);
    }

    final gpxFile = File(path.join(workoutsDir.path, gpxFileName));
    final exportTrackPoints = await workoutController.getExportTrackPoints();
    final gpxContent = await GpxFileExporter.generateGpxContent(
      '2 Hour 300W Test',
      exportTrackPoints,
    );
    await gpxFile.writeAsString(gpxContent);

    // Convert GPX to FIT
    final fitFileName = gpxFileName.replaceAll('.gpx', '.fit');
    final fitFile = File(path.join(workoutsDir.path, fitFileName));
    await GpxToFitConverter.convertAndCleanup(gpxFile.path);

    // Success - both files were generated
    print('Test completed successfully:');
    print('GPX file: ${gpxFile.path}');
    print('FIT file: ${fitFile.path}');

    // Cleanup
    workoutController.cleanup();
  });

  test('Workout timing resists drift with delayed ticks', () async {
    final workoutContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <author>Test</author>
    <name>Drift Check</name>
    <description>Short workout for drift testing</description>
    <sportType>bike</sportType>
    <workout>
        <SteadyState Duration="300" Power="1.0" />
    </workout>
</workout_file>
''';

    final mockDevice = BluetoothDevice.fromId('00:00:00:00:00:00');
    final deviceData = DeviceDataManager.forDevice(mockDevice);
    deviceData.ftmsData = FtmsData();

    final workoutController = WorkoutController(deviceData, mockDevice);
    await workoutController.updateFTP(250.0);
    workoutController.loadWorkout(workoutContent);

    // Start workout
    await workoutController.togglePlayPause();

    final startWall = DateTime.now();
    final random = Random(42);

    // Let the timer run with intentionally jittery delays to simulate slow hardware
    for (int i = 0; i < 25; i++) {
      deviceData.ftmsData
        ..watts = 250
        ..cadence = 85
        ..heartRate = 150;

      // Mix short and longer delays (50ms-1200ms) to force missed timer ticks
      final delayMs = 50 + random.nextInt(1150);
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    // Allow final timer tick
    await Future.delayed(const Duration(milliseconds: 200));
    await workoutController.stopWorkout();

    final wallElapsed = DateTime.now().difference(startWall).inSeconds;
    final controllerElapsed = workoutController.elapsedSeconds;

    // Controller elapsed time should closely follow wall time even with delayed ticks
    final elapsedWithinTolerance =
        controllerElapsed >= wallElapsed - 1 &&
        controllerElapsed <= wallElapsed + 1;
    expect(elapsedWithinTolerance, isTrue);

    // Track points should exist for essentially every elapsed second
    expect(workoutController.trackPoints.length >= controllerElapsed, isTrue);

    // Export and validate FIT elapsed time matches controller time
    final fileTimestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final gpxFileName = 'drift_${fileTimestamp}.gpx';
    final workoutsDir = await Directory.systemTemp.createTemp(
      'ss2k_drift_test',
    );

    final gpxFile = File(path.join(workoutsDir.path, gpxFileName));
    final gpxContent = await GpxFileExporter.generateGpxContent(
      'Drift Check',
      workoutController.trackPoints,
    );
    await gpxFile.writeAsString(gpxContent);

    final fitPath = await GpxToFitConverter.convertAndCleanup(gpxFile.path);
    final fitFileHandle = File(fitPath);
    final fitBytes = await fitFileHandle.readAsBytes();
    final fitFile = FitFile.fromBytes(fitBytes);
    final session = fitFile.records
        .map((r) => r.message)
        .whereType<SessionMessage>()
        .first;
    final activity = fitFile.records
        .map((r) => r.message)
        .whereType<ActivityMessage>()
        .first;

    final fitElapsedSeconds = (session.totalElapsedTime ?? 0);
    final activityElapsedSeconds = (activity.totalTimerTime ?? 0);

    expect((fitElapsedSeconds - controllerElapsed).abs() <= 1, isTrue);
    expect((activityElapsedSeconds - controllerElapsed).abs() <= 1, isTrue);

    await fitFileHandle.delete();
    await workoutsDir.delete(recursive: true);

    workoutController.cleanup();
  });
}
