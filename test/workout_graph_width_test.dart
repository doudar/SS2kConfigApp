import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_constants.dart';

void main() {
  test('short workouts occupy the full graph viewport', () {
    expect(
      calculateWorkoutGraphWidth(
        viewportWidth: 393,
        workoutDurationSeconds: 3 * 60,
        visibleMinutes: 10,
      ),
      393,
    );
  });

  test('long workouts retain duration-based graph widths', () {
    expect(
      calculateWorkoutGraphWidth(
        viewportWidth: 393,
        workoutDurationSeconds: 30 * 60,
        visibleMinutes: 10,
      ),
      1179,
    );
  });
}
