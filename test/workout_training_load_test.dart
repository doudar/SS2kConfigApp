import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_training_load.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';
import 'package:ss2kconfigapp/utils/workout/workout_storage.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';

void main() {
  test('library, selection and recommendation share normalized-power TSS', () {
    const content =
        '<workout_file><workout>'
        '<SteadyState Duration="1800" Power="0.5"/>'
        '<SteadyState Duration="1800" Power="1.0"/>'
        '</workout></workout_file>';
    final choice = WorkoutLobbyChoice(content: content, source: 'TEST');
    final load = WorkoutTrainingLoad.estimate(choice.workout.segments)!;
    // Variable power carries more load than the old average-power calculation.
    expect(load.tss, greaterThan(56.25));
    expect(choice.estimatedTss, load.tss);
    expect(CoachCandidate.fromChoice(choice)!.tss, load.tss);
    expect(
      WorkoutStorage.buildWorkoutSummary(content),
      contains(WorkoutTrainingLoad.label(load.tss)),
    );
  });

  test('self-paced rides have unknown TSS, including scheduled free rides', () {
    for (final seconds in [0, 1800]) {
      final choice = WorkoutLobbyChoice(
        source: 'TEST',
        content:
            '<workout_file><workout><FreeRide Duration="$seconds"/></workout></workout_file>',
      );
      expect(choice.estimatedTss, isNull);
      expect(WorkoutTrainingLoad.label(choice.estimatedTss), 'TSS —');
    }
  });
}
