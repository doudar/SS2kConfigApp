import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_file_exporter.dart';
import 'package:ss2kconfigapp/utils/workout/gpx_to_fit.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';

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
    final workoutsDir = await Directory.systemTemp.createTemp('erg_workout');
    try {
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

      expect(await fitFile.exists(), isTrue);
    } finally {
      workoutController.cleanup();
      await workoutsDir.delete(recursive: true);
    }
  });

  test(
    'Workout timing accumulates virtual timer intervals without gaps',
    () async {
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

      final mockDevice = BluetoothDevice.fromId('00:00:00:00:00:01');
      final deviceData = DeviceDataManager.forDevice(mockDevice);
      deviceData.ftmsData = FtmsData()
        ..watts = 250
        ..cadence = 85
        ..heartRate = 150;

      final workoutController = WorkoutController(deviceData, mockDevice);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      workoutController.loadWorkout(workoutContent);

      const blockedIntervals = [
        Duration(milliseconds: 50),
        Duration(milliseconds: 1200),
        Duration(milliseconds: 375),
        Duration(milliseconds: 950),
        Duration(milliseconds: 25),
      ];
      const timerInterval = Duration(milliseconds: 100);

      fakeAsync((async) {
        withClock(async.getClock(DateTime.utc(2026, 1, 1)), () {
          workoutController.isPlaying = true;
          workoutController.startProgress();

          for (final blockedInterval in blockedIntervals) {
            async.elapseBlocking(blockedInterval);
            async.elapse(timerInterval);
          }
        });
      });

      final expectedProgress =
          blockedIntervals.fold<double>(
            0,
            (total, interval) => total + interval.inMicroseconds / 1000000,
          ) +
          (blockedIntervals.length * timerInterval.inMicroseconds / 1000000);

      expect(
        workoutController.workoutProgressSeconds,
        closeTo(expectedProgress, 0.001),
      );
      expect(
        workoutController.trackPoints.length,
        workoutController.workoutProgressSeconds.floor(),
      );
      for (var i = 1; i < workoutController.trackPoints.length; i++) {
        expect(
          workoutController.trackPoints[i].timestamp.difference(
            workoutController.trackPoints[i - 1].timestamp,
          ),
          const Duration(seconds: 1),
        );
      }

      workoutController.cleanup();
    },
  );
}
