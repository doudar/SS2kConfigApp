import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/bledata.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });

  test('Workout progress tracks real time despite timer lag', () async {
    final workoutContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<workout_file>
    <author>Test</author>
    <name>Test Workout</name>
    <sportType>bike</sportType>
    <workout>
        <SteadyState Duration="300" Power="1.0" />
    </workout>
</workout_file>
''';

    final mockDevice = BluetoothDevice.fromId('00:00:00:00:00:00');
    final bleData = BLEDataManager.forDevice(mockDevice);
    bleData.ftmsData = FtmsData();
    
    final workoutController = WorkoutController(bleData, mockDevice);
    
    // Load and start
    workoutController.loadWorkout(workoutContent);
    // Ensure initial state
    expect(workoutController.isPlaying, false);
    
    // Start workout
    await workoutController.togglePlayPause();
    expect(workoutController.isPlaying, true);

    // Wait for 2 seconds (real time)
    // In a test environment, Timer.periodic relies on the async zone.
    // We want to verify that after X seconds of wall clock, 
    // the controller reflects X seconds of progress.
    
    // We iterate a few times with small delays to allow some timer ticks to fire
    final startTime = DateTime.now();
    
    // Wait for approx 2 seconds
    await Future.delayed(const Duration(seconds: 29));
    
    // Check progress
    final double progress = workoutController.workoutProgressSeconds;
    final int elapsedReal = DateTime.now().difference(startTime).inSeconds;
    
    print('Progress: $progress, Real: $elapsedReal');
    
    // Allow small margin for execution overhead, but it should be close to 2.0
    // If it was lagging significantly (e.g. only counting ticks), we might see discrepancies if the test environment was slow.
    // But mainly we want to ensure it is advancing.
    
    expect(progress, greaterThan(28.8));
    
    workoutController.cleanup();
  });
}
