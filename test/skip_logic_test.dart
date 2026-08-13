import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  Directory? tempDir;
  
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('ss2k_test');
    pathProviderChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'getApplicationDocumentsDirectory' || call.method == 'getTemporaryDirectory') {
        return tempDir!.path;
      }
      return null;
    });
  });

  tearDown(() async {
    pathProviderChannel.setMockMethodCallHandler(null);
    if (tempDir != null && await tempDir!.exists()) {
      await tempDir!.delete(recursive: true);
    }
  });

  test('Skip segment does not generate phantom trackpoints', () async {
    // 3 segments of 60 seconds each
    final workoutContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <author>Test</author>
    <name>Skip Test</name>
    <sportType>bike</sportType>
    <workout>
        <SteadyState Duration="60" Power="1.0" />
        <SteadyState Duration="60" Power="1.5" />
        <SteadyState Duration="60" Power="1.0" />
    </workout>
</workout_file>
''';

    final mockDevice = BluetoothDevice.fromId('00:00:00:00:00:00');
    final deviceData = DeviceDataManager.forDevice(mockDevice);
    deviceData.ftmsData = FtmsData();
    deviceData.ftmsData.watts = 100; // Mock power data
    
    final workoutController = WorkoutController(deviceData, mockDevice);
    
    // Load and start
    workoutController.loadWorkout(workoutContent);
    await workoutController.togglePlayPause();
    
    // Let it run for 2 seconds
    await Future.delayed(const Duration(milliseconds: 2100));
    
    int pointsBeforeSkip = workoutController.trackPoints.length;
    print('Points before skip: $pointsBeforeSkip');
    
    // We expect roughly 2 points (maybe 3 depending on timing alignment)
    expect(pointsBeforeSkip, greaterThanOrEqualTo(1));
    expect(pointsBeforeSkip, lessThanOrEqualTo(3));
    
    // SKIP current segment
    // Current time ~2s. Segment is 60s. Skipping advances time to 60s.
    workoutController.skipToNextSegment();
    
    // Check points immediately after skip
    // If bug exists, we would expect ~60 points (filling the gap)
    // If fixed, count should be unchanged or +1 max
    int pointsAfterSkip = workoutController.trackPoints.length;
    print('Points after skip: $pointsAfterSkip');
    
    expect(pointsAfterSkip - pointsBeforeSkip, lessThan(5), 
      reason: 'Should not generate many points (phantom points) when skipping');

    // Run for another 2 seconds
    await Future.delayed(const Duration(milliseconds: 2100));
    
    int pointsFinal = workoutController.trackPoints.length;
    print('Points final: $pointsFinal');
    
    // Should have added ~2 more points
    expect(pointsFinal - pointsAfterSkip, greaterThanOrEqualTo(1));
    expect(pointsFinal - pointsAfterSkip, lessThanOrEqualTo(3));
    
    workoutController.cleanup();
  });
}
