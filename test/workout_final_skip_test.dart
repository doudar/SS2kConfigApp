import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/workout_controller.dart';
import 'package:ss2kconfigapp/utils/workout/workout_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'skipping a restored final interval preserves elapsed time and level',
    () async {
      SharedPreferences.setMockInitialValues({});
      await WorkoutStorage.saveWorkoutState(
        workoutContent:
            '<workout_file><name>Final skip</name><workout>'
            '<SteadyState Duration="1800" Power="0.7"/>'
            '</workout></workout_file>',
        progressPosition: 1 / 3,
        workoutProgressTime: 600,
        skippedTime: 150,
        isPlaying: false,
      );
      final data = DeviceData();
      final controller = WorkoutController(
        data,
        BluetoothDevice.fromId('00:00:00:00:F1:01'),
      );
      addTearDown(() {
        controller.cleanup();
        data.dispose();
      });
      // The controller restores local preferences asynchronously on construction.
      await Future<void>.delayed(Duration.zero);
      expect(controller.workoutProgressSeconds, 600);
      expect(controller.elapsedSeconds, 450);

      final game = ArcadeSession();
      void sync() => game.update(
        segments: controller.segments,
        seconds: controller.workoutProgressSeconds,
        riddenSeconds: controller.elapsedSeconds.toDouble(),
        playing: controller.isPlaying,
        watts: 140,
        target: 140,
        freshSignal: true,
      );
      controller.isPlaying = true;
      sync();
      expect(game.difficultyIndex, 0);
      controller.addListener(sync);
      addTearDown(() => controller.removeListener(sync));

      game.willSkip();
      controller.skipToNextSegment();

      expect(controller.isPlaying, isFalse);
      expect(controller.progressPosition, 1);
      expect(controller.workoutProgressSeconds, 1800);
      expect(controller.elapsedSeconds, 450);
      expect(controller.trackPoints, isEmpty);
      expect(game.riddenSeconds, 450);
      expect(game.difficultyIndex, 0);
      expect(game.score, 0);
      controller.skipToNextSegment();
      expect(controller.elapsedSeconds, 450);
      await Future<void>.delayed(Duration.zero);
    },
  );
}
