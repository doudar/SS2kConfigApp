import 'package:flutter/material.dart';

/// Classic's instrument panels use the same navy, mint and gold as Arcade.
abstract final class WorkoutVisuals {
  static const ink = Color(0xff080f21);
  static const panel = Color(0xff101b30);
  static const mint = Color(0xff74ffd3);
  static const gold = Color(0xffffd477);
  static const muted = Color(0xff93a5c3);
  static const power = Color(0xff77d9ff);
  static const cadence = Color(0xff74e5a2);
  static const heartRate = Color(0xffff8392);
}

class ClassicWorkoutSurface extends StatelessWidget {
  const ClassicWorkoutSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: WorkoutVisuals.mint,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: WorkoutVisuals.ink,
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WorkoutVisuals.ink, WorkoutVisuals.panel],
        ),
      ),
      child: child,
    ),
  );
}
