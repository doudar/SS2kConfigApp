import 'package:flutter/material.dart';

/// The same named entry point on both workout landing pages.
class WorkoutMenuButton extends StatelessWidget {
  const WorkoutMenuButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.menu_rounded),
        label: const Text('Ride menu'),
      ),
    ),
  );
}
