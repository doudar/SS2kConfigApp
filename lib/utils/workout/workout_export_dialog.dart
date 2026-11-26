import 'package:flutter/material.dart';
import '../../widgets/workout_dialog.dart';
import '../../widgets/workout_settings_theme.dart';
import '../../widgets/ride_drawing_field.dart';
import 'ride_map.dart';
import 'workout_uploads.dart';

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
    return WorkoutDialog(
      icon: Icons.flag_rounded,
      eyebrow: 'WRAP UP YOUR RIDE',
      title: const Text('Ready to finish?'),
      subtitle: 'You can save or upload your workout next.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkoutSettingsPanel(
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
          WorkoutDialogActions(
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
class WorkoutExportDialog extends StatefulWidget {
  const WorkoutExportDialog({
    super.key,
    required this.workoutName,
    required this.duration,
    required this.averagePower,
    required this.averageCadence,
    required this.stravaConnected,
    required this.intervalsConnected,
    this.initialChoice = const WorkoutExportChoice(
      uploadToStrava: true,
      uploadToIntervals: true,
    ),
  });

  final String workoutName;
  final String duration;
  final double? averagePower;
  final double? averageCadence;
  final bool stravaConnected;
  final bool intervalsConnected;
  final WorkoutExportChoice initialChoice;

  @override
  State<WorkoutExportDialog> createState() => _WorkoutExportDialogState();
}

class _WorkoutExportDialogState extends State<WorkoutExportDialog> {
  late RideDrawing _drawing = widget.initialChoice.mapSettings.drawing;
  late bool _strava =
      widget.stravaConnected && widget.initialChoice.uploadToStrava;
  late bool _intervals =
      widget.intervalsConnected && widget.initialChoice.uploadToIntervals;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String metric(double? value, String unit) =>
        value != null && value.isFinite ? '${value.round()} $unit' : '—';

    final summary = WorkoutSettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.workoutName,
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
              _RideMetric(Icons.timer_outlined, 'Ride time', widget.duration),
              _RideMetric(
                Icons.bolt_rounded,
                'Avg power',
                metric(widget.averagePower, 'W'),
              ),
              _RideMetric(
                Icons.rotate_right_rounded,
                'Avg cadence',
                metric(widget.averageCadence, 'rpm'),
              ),
            ],
          ),
        ],
      ),
    );
    final options = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideDrawingField(
          initialDrawing: _drawing,
          onChanged: (drawing) => setState(() => _drawing = drawing),
        ),
        if (widget.stravaConnected || widget.intervalsConnected) ...[
          const SizedBox(height: 18),
          const WorkoutSectionLabel('UPLOAD TO YOUR APPS'),
          const SizedBox(height: 6),
          const Text('Choose any or all. We will remember for next time.'),
          const SizedBox(height: 10),
          if (widget.stravaConnected)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Strava'),
              value: _strava,
              onChanged: (value) => setState(() => _strava = value!),
            ),
          if (widget.intervalsConnected)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Intervals.icu'),
              value: _intervals,
              onChanged: (value) => setState(() => _intervals = value!),
            ),
        ],
      ],
    );
    return WorkoutDialog(
      maxWidth: WorkoutSettingsTheme.browserWidth,
      icon: Icons.directions_bike_rounded,
      eyebrow: 'YOUR WORKOUT',
      title: const Text('Save your ride'),
      subtitle:
          'Save a FIT file on this device and send your ride to your apps.',
      content: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >=
              MediaQuery.textScalerOf(context).scale(640)) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: summary),
                const SizedBox(width: 24),
                Expanded(child: options),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [summary, const SizedBox(height: 22), options],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const WorkoutExportChoice(discard: true)),
          style: TextButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
          child: const Text('Discard workout'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            WorkoutExportChoice(
              mapSettings: widget.initialChoice.mapSettings.withDrawing(
                _drawing,
              ),
              uploadToStrava: _strava,
              uploadToIntervals: _intervals,
            ),
          ),
          icon: Icon(
            _strava || _intervals
                ? Icons.cloud_upload_outlined
                : Icons.download_rounded,
          ),
          label: Text(
            _strava || _intervals ? 'Save & upload' : 'Save FIT file',
          ),
        ),
      ],
    );
  }
}

class WorkoutExportProgressDialog extends StatelessWidget {
  const WorkoutExportProgressDialog({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => WorkoutDialog(
    icon: Icons.sync_rounded,
    eyebrow: 'WORKOUT FILE',
    title: const Text('One moment…'),
    content: Column(
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
  const WorkoutSavedDialog({
    super.key,
    required this.filePath,
    this.uploadResults = const {},
  });
  final String filePath;
  final Map<String, bool> uploadResults;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filename = filePath.split(RegExp(r'[/\\]')).last;
    return WorkoutDialog(
      icon: Icons.check_circle_outline_rounded,
      eyebrow: 'READY TO GO',
      title: const Text('Workout saved'),
      subtitle: 'Your FIT file is saved on this device and ready to share.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkoutSettingsPanel(
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
          for (final result in uploadResults.entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    result.value
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: result.value ? colors.primary : colors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.value
                          ? 'Uploaded to ${result.key}'
                          : 'Could not upload to ${result.key}. Your saved file is safe.',
                    ),
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
          WorkoutDialogActions(
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
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
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
