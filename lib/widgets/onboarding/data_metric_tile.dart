import 'package:flutter/material.dart';

/// A live power or cadence reading that turns green once a usable value has
/// been seen.
class DataMetricTile extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final bool detected;
  final IconData waitingIcon;

  const DataMetricTile({
    Key? key,
    required this.label,
    required this.value,
    required this.unit,
    required this.detected,
    required this.waitingIcon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = detected
        ? Colors.green
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: detected
            ? Colors.green.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: detected
              ? Colors.green.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.25),
          width: detected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: detected
                  ? Colors.green.shade700
                  : theme.colorScheme.onSurface,
              height: 1.0,
            ),
            child: Text('$value'),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              detected ? Icons.check_circle_rounded : waitingIcon,
              key: ValueKey(detected),
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detected ? 'Detected' : 'Waiting…',
            style: TextStyle(fontSize: 11, color: accent),
          ),
        ],
      ),
    );
  }
}
