import 'package:flutter/material.dart';

/// Named actions keep familiar icons as a secondary cue, with a full tap target.
class WorkoutHeaderAction extends StatelessWidget {
  const WorkoutHeaderAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.badge,
    this.stacked = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? badge;
  final bool stacked;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: stacked
        ? TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(height: 3),
                FittedBox(fit: BoxFit.scaleDown, child: _label(10)),
              ],
            ),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: _label(12),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
  );

  Widget _label(double fontSize) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
      if (badge != null) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xffffd477),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge!,
            style: const TextStyle(
              color: Color(0xff080f21),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
        ),
      ],
    ],
  );
}
