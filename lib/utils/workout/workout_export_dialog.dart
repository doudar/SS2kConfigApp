import 'package:flutter/material.dart';

class WorkoutEndDialog extends StatelessWidget {
  const WorkoutEndDialog({
    super.key,
    required this.workoutName,
    required this.duration,
    required this.playing,
    this.remaining,
  });

  final String workoutName;
  final String duration;
  final String? remaining;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ExportShell(
      icon: Icons.flag_rounded,
      eyebrow: 'WRAP UP YOUR RIDE',
      title: 'Ready to finish?',
      subtitle: 'You can save or upload your workout next.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outline.withValues(alpha: .15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workoutName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 28,
                  runSpacing: 16,
                  children: [
                    _RideMetric(Icons.timer_outlined, 'Ride time', duration),
                    if (remaining != null)
                      _RideMetric(
                        Icons.timelapse_rounded,
                        'Remaining',
                        remaining!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 12,
            overflowSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(playing ? 'Keep riding' : 'Back to workout'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.flag_rounded, size: 18),
                label: const Text('End workout'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Presentation shared by the Classic and Arcade workout export flows.
class WorkoutExportDialog extends StatelessWidget {
  const WorkoutExportDialog({
    super.key,
    required this.workoutName,
    required this.duration,
    required this.averagePower,
    required this.averageCadence,
    required this.stravaConnected,
    required this.intervalsConnected,
  });

  final String workoutName;
  final String duration;
  final double? averagePower;
  final double? averageCadence;
  final bool stravaConnected;
  final bool intervalsConnected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String metric(double? value, String unit) =>
        value != null && value.isFinite ? '${value.round()} $unit' : '—';
    void choose(String destination) => Navigator.of(context).pop(destination);
    return _ExportShell(
      icon: Icons.directions_bike_rounded,
      eyebrow: 'YOUR WORKOUT',
      title: 'Save your ride',
      subtitle: 'Keep the effort. Take it with you.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outline.withValues(alpha: .15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workoutName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 22,
                  runSpacing: 16,
                  children: [
                    _RideMetric(Icons.timer_outlined, 'Ride time', duration),
                    _RideMetric(
                      Icons.bolt_rounded,
                      'Avg power',
                      metric(averagePower, 'W'),
                    ),
                    _RideMetric(
                      Icons.rotate_right_rounded,
                      'Avg cadence',
                      metric(averageCadence, 'rpm'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _ExportDestination(
            icon: Icons.download_rounded,
            title: 'Save FIT file',
            subtitle: 'Keep a copy on this device',
            primary: true,
            onTap: () => choose('save'),
          ),
          if (stravaConnected || intervalsConnected) ...[
            const SizedBox(height: 22),
            Text(
              'UPLOAD TO A CONNECTED APP',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (stravaConnected)
              _ExportDestination(
                icon: Icons.landscape_rounded,
                title: 'Strava',
                subtitle: 'Upload this ride to your activities',
                onTap: () => choose('strava'),
              ),
            if (stravaConnected && intervalsConnected)
              const SizedBox(height: 10),
            if (intervalsConnected)
              _ExportDestination(
                icon: Icons.stacked_line_chart_rounded,
                title: 'Intervals.icu',
                subtitle: 'Upload this ride to your training calendar',
                onTap: () => choose('intervals'),
              ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => choose('discard'),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
              ),
              child: const Text('Discard workout'),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutExportProgressDialog extends StatelessWidget {
  const WorkoutExportProgressDialog({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => _ExportShell(
    icon: Icons.sync_rounded,
    eyebrow: 'WORKOUT FILE',
    title: 'One moment…',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          child: LinearProgressIndicator(minHeight: 5),
        ),
        const SizedBox(height: 18),
        Semantics(liveRegion: true, child: Text(message)),
      ],
    ),
  );
}

class WorkoutSavedDialog extends StatelessWidget {
  const WorkoutSavedDialog({super.key, required this.filePath});
  final String filePath;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filename = filePath.split(RegExp(r'[/\\]')).last;
    return _ExportShell(
      icon: Icons.check_circle_outline_rounded,
      eyebrow: 'READY TO GO',
      title: 'Workout saved',
      subtitle: 'Your FIT file is ready to share.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: .035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outline.withValues(alpha: .15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'FIT ACTIVITY',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  filename,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('Saved location', style: TextStyle(fontSize: 13)),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  filePath,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OverflowBar(
            spacing: 12,
            overflowSpacing: 10,
            alignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Done'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share file'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExportShell extends StatelessWidget {
  const _ExportShell({
    required this.icon,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      constraints: const BoxConstraints(maxWidth: 520),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: colors.outline.withValues(alpha: .18)),
      ),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.primary.withValues(alpha: .12),
                    colors.surface,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: colors.primary, size: 25),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          eyebrow,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Semantics(
                    namesRoute: true,
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _RideMetric extends StatelessWidget {
  const _RideMetric(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ExportDestination extends StatelessWidget {
  const _ExportDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = primary ? colors.onPrimary : colors.onSurface;
    return Material(
      color: primary ? colors.primary : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: primary
              ? colors.primary
              : colors.outline.withValues(alpha: .25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 25,
                  color: primary ? foreground : colors.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: primary
                              ? foreground.withValues(alpha: .9)
                              : colors.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
