import 'package:flutter/material.dart';
import '../utils/workout/sounds.dart';

class WorkoutSoundEffectsToggle extends StatefulWidget {
  const WorkoutSoundEffectsToggle({super.key});

  @override
  State<WorkoutSoundEffectsToggle> createState() =>
      _WorkoutSoundEffectsToggleState();
}

class _WorkoutSoundEffectsToggleState extends State<WorkoutSoundEffectsToggle> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await workoutSoundGenerator.getEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: const Icon(Icons.volume_up_rounded),
    title: const Text('Sound effects'),
    subtitle: const Text('Workout clicks, interval chimes and finish fanfare'),
    value: _enabled ?? false,
    onChanged: _enabled == null
        ? null
        : (value) {
            setState(() => _enabled = value);
            workoutSoundGenerator.setEnabled(value);
          },
  );
}
