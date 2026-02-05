import 'package:flutter/material.dart';
import 'workout_constants.dart';
import 'workout_controller.dart';
import 'sounds.dart';

class WorkoutControls extends StatefulWidget {
  final WorkoutController workoutController;
  final VoidCallback onStopWorkout;

  const WorkoutControls({
    Key? key,
    required this.workoutController,
    required this.onStopWorkout,
  }) : super(key: key);

  @override
  State<WorkoutControls> createState() => _WorkoutControlsState();
}

class _WorkoutControlsState extends State<WorkoutControls> {
  static const int minFTP = 50;
  static const int maxFTP = 500;
  static const int ftpStep = 1;
  late int _selectedFTP;
  late final FixedExtentScrollController _ftpScrollController;

  @override
  void initState() {
    super.initState();
    _selectedFTP = widget.workoutController.ftpValue.round();
    _ftpScrollController = FixedExtentScrollController(
      initialItem: (_selectedFTP - minFTP) ~/ ftpStep,
    );
  }

  @override
  void dispose() {
    _ftpScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: EdgeInsets.symmetric(vertical: WorkoutPadding.small),
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  offset: const Offset(0, 6),
                  blurRadius: 8,
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey[800]!,
                  Colors.black,
                ],
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.workoutController.isPlaying)
                  IconButton(
                    icon: const Icon(Icons.stop_circle),
                    iconSize: 42,
                    color: Colors.redAccent,
                    tooltip: 'Stop Workout',
                    onPressed: widget.onStopWorkout,
                  ),
                IconButton(
                  icon: Icon(widget.workoutController.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  iconSize: 56,
                  color: Colors.greenAccent,
                  tooltip: widget.workoutController.isPlaying ? 'Pause' : 'Play',
                  onPressed: () {
                    if (!widget.workoutController.isPlaying) {
                      workoutSoundGenerator.playButtonSound();
                    }
                    widget.workoutController.togglePlayPause();
                  },
                ),
                if (widget.workoutController.isPlaying)
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 42,
                    color: Colors.white,
                    tooltip: 'Skip Segment',
                    onPressed: widget.workoutController.skipToNextSegment,
                  ),
              ],
            ),
          ),
          Positioned(
            right: WorkoutPadding.standard,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('FTP: '),
                Container(
                  width: 80,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ListWheelScrollView.useDelegate(
                    controller: _ftpScrollController,
                    useMagnifier: true,
                    magnification: 1.3,
                    clipBehavior: Clip.none,
                    overAndUnderCenterOpacity: .2,
                    itemExtent: 40,
                    perspective: 0.01,
                    diameterRatio: 2,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedFTP = minFTP + (index * ftpStep);
                        widget.workoutController.updateFTP(_selectedFTP.toDouble());
                      });
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: ((maxFTP - minFTP) ~/ ftpStep) + 1,
                      builder: (context, index) {
                        final value = minFTP + (index * ftpStep);
                        return Container(
                          alignment: Alignment.center,
                          child: Text(
                            value.toString(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: value == _selectedFTP ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Text('W'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
