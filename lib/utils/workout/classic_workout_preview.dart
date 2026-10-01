import 'package:flutter/material.dart';
import 'arcade/arcade_route_preview.dart';
import 'workout_parser.dart';
import 'workout_visuals.dart';

/// Match Arcade: the preview sits above a full-width bottom transport row.
class ClassicWorkoutDock extends StatelessWidget {
  const ClassicWorkoutDock({
    super.key,
    required this.controls,
    required this.preview,
  });
  final Widget controls, preview;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [preview, controls],
    ),
  );
}

class ClassicWorkoutPreview extends StatelessWidget {
  const ClassicWorkoutPreview({
    super.key,
    required this.segments,
    required this.index,
    required this.seconds,
    required this.ftp,
    required this.endless,
  });

  final List<WorkoutSegment> segments;
  final int index;
  final double seconds, ftp;
  final bool endless;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    padding: const EdgeInsets.only(bottom: 7),
    decoration: BoxDecoration(
      color: WorkoutVisuals.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: ArcadeRoutePreview(
      segments: segments,
      index: index,
      seconds: seconds,
      ftp: ftp,
      endless: endless,
      compact: MediaQuery.sizeOf(context).height < 650,
      cleared: const {},
      workoutLabels: true,
    ),
  );
}

class WorkoutTraceLegend extends StatelessWidget {
  const WorkoutTraceLegend({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    child: Wrap(
      spacing: 18,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        _TraceLabel('POWER · W', WorkoutVisuals.power),
        _TraceLabel('CADENCE · RPM', WorkoutVisuals.cadence),
        _TraceLabel('HEART RATE · BPM', WorkoutVisuals.heartRate),
      ],
    ),
  );
}

class _TraceLabel extends StatelessWidget {
  const _TraceLabel(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 2, color: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          letterSpacing: .5,
          color: WorkoutVisuals.muted,
        ),
      ),
    ],
  );
}
