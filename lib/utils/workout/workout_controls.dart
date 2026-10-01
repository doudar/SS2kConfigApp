import 'package:flutter/material.dart';
import '../../widgets/workout_ftp_dialog.dart';
import 'workout_playback_bar.dart';
import 'workout_controller.dart';
import 'sounds.dart';

class WorkoutControls extends StatelessWidget {
  final WorkoutController workoutController;
  final VoidCallback onStopWorkout;
  final VoidCallback? onSkipSegment;

  const WorkoutControls({
    super.key,
    required this.workoutController,
    required this.onStopWorkout,
    this.onSkipSegment,
  });

  @override
  Widget build(BuildContext context) {
    return WorkoutPlaybackBar(
      playing: workoutController.isPlaying,
      hasProgress: workoutController.workoutProgressSeconds > 0,
      finished: workoutController.progressPosition >= 1,
      freeRide: workoutController.isFreeRide,
      ftp: workoutController.ftpValue,
      onPlayPause: workoutController.segments.isEmpty
          ? null
          : () {
              if (!workoutController.isPlaying)
                workoutSoundGenerator.playButtonSound();
              workoutController.togglePlayPause();
            },
      onStop: onStopWorkout,
      onSkip: onSkipSegment ?? workoutController.skipToNextSegment,
      onFtp: () async {
        final ftp = await showDialog<double>(
          context: context,
          builder: (_) =>
              WorkoutFtpDialog(initialFtp: workoutController.ftpValue),
        );
        if (ftp != null && context.mounted)
          await workoutController.updateFTP(ftp);
      },
    );
  }
}
