import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_metric_row.dart';
import 'package:ss2kconfigapp/utils/workout/workout_metrics.dart';

// Cover for the target clamp from both ends: the controller must hand the
// clamped value to the model, and the Target tile must render whatever the
// model holds. A malformed import must never show a hold the trainer was
// never asked for.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  Directory? tempDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    tempDirectory = await Directory.systemTemp.createTemp('clamp_display');
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDirectory!.path;
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    final directory = tempDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  // Runs the real parser and the real ramp math, so it also catches a clamp
  // undone anywhere between the ZWO attribute and the model.
  test('out-of-range workout segments reach the model clamped', () async {
    final deviceData = DeviceData();
    final controller = WorkoutController(
      deviceData,
      BluetoothDevice.fromId('00:00:00:00:00:92'),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.updateFTP(250);
    controller.loadWorkout(_clampRepro);

    // Segment 1: Power="-0.2" at FTP 250 asks for -50 W. The lane sends 0.
    await controller.togglePlayPause();
    expect(deviceData.ftmsData.targetERG, 0);

    // skipToNextSegment moves the progress clock; the 100 ms tick is what
    // recomputes the target, so give it a real one.
    controller.skipToNextSegment();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(deviceData.ftmsData.targetERG, 0x7fff,
        reason: 'Power="200" at FTP 250 asks for 50000 W');

    controller.skipToNextSegment();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(deviceData.ftmsData.targetERG, 150,
        reason: 'an in-range target must pass through untouched');

    await controller.stopWorkout();
    expect(deviceData.ftmsData.targetERG, 0, reason: 'stop releases the hold');

    controller.cleanup();
    deviceData.dispose();
  });

  testWidgets('Target tile renders the stored target', (tester) async {
    final deviceData = DeviceData();

    Future<void> showTarget(int requestedWatts) async {
      deviceData.setWorkoutTargetPower(requestedWatts);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutMetrics(
              deviceData: deviceData,
              fadeAnimation: const AlwaysStoppedAnimation<double>(1.0),
              elapsedTime: 0,
              timeToNextSegment: 0,
              totalDuration: 180,
              workoutProgressSeconds: 0,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    String targetTile() => tester
        .widgetList<MetricBox>(find.byType(MetricBox))
        .firstWhere((box) => box.metric.label == 'Target')
        .metric
        .value;

    await showTarget(-50);
    expect(targetTile(), '0');

    await showTarget(50000);
    expect(targetTile(), '32767');

    await showTarget(150);
    expect(targetTile(), '150');

    deviceData.dispose();
  });
}

const _clampRepro = '''
<workout_file>
  <name>Clamp Repro</name>
  <workout>
    <SteadyState Duration="60" Power="-0.2" />
    <SteadyState Duration="60" Power="200" />
    <SteadyState Duration="60" Power="0.6" />
  </workout>
</workout_file>
''';
