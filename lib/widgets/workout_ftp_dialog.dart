import 'package:flutter/material.dart';
import 'workout_dialog.dart';

/// Classic and Arcade edit the same range and return only an applied value.
class WorkoutFtpDialog extends StatefulWidget {
  const WorkoutFtpDialog({super.key, required this.initialFtp});
  final double initialFtp;
  @override
  State<WorkoutFtpDialog> createState() => _WorkoutFtpDialogState();
}

class _WorkoutFtpDialogState extends State<WorkoutFtpDialog> {
  late double _ftp = widget.initialFtp.clamp(50.0, 500.0);
  @override
  Widget build(BuildContext context) => WorkoutDialog(
    title: const Text('Workout FTP'),
    icon: Icons.bolt_rounded,
    subtitle: 'Set the power used to scale your workout targets.',
    content: WorkoutSettingSlider(
      label: 'Functional threshold power',
      valueLabel: '${_ftp.round()} W',
      value: _ftp,
      min: 50,
      max: 500,
      divisions: 450,
      onChanged: (value) => setState(() => _ftp = value),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _ftp),
        child: const Text('Apply'),
      ),
    ],
  );
}
