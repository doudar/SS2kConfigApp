import 'package:flutter/material.dart';
import 'workout_visuals.dart';

/// The same transport row in Classic and Arcade, below the interval preview.
class WorkoutPlaybackBar extends StatelessWidget {
  const WorkoutPlaybackBar({
    super.key,
    required this.playing,
    required this.hasProgress,
    required this.freeRide,
    required this.ftp,
    required this.onPlayPause,
    required this.onStop,
    required this.onSkip,
    required this.onFtp,
    this.finished = false,
  });

  final bool playing, hasProgress, freeRide, finished;
  final double ftp;
  final VoidCallback? onPlayPause;
  final VoidCallback onStop, onSkip, onFtp;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Stop Workout',
          onPressed: playing || hasProgress ? onStop : null,
          icon: const Icon(Icons.stop_circle_outlined),
          color: const Color(0xffff9d9d),
        ),
        Expanded(
          child: FilledButton.icon(
            onPressed: onPlayPause,
            style: FilledButton.styleFrom(
              backgroundColor: WorkoutVisuals.mint,
              foregroundColor: WorkoutVisuals.ink,
            ),
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            label: Text(
              playing
                  ? 'PAUSE'
                  : hasProgress && !finished
                  ? 'RESUME'
                  : 'PLAY',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Skip Segment',
          onPressed: playing && !freeRide ? onSkip : null,
          icon: const Icon(Icons.skip_next),
        ),
        TextButton(
          onPressed: onFtp,
          child: Text(
            'FTP ${ftp.round()}',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
