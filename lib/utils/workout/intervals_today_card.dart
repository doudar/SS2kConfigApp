import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/intervals_service.dart';
import '../../services/intervals_workout_converter.dart';
import 'workout_lobby_choice.dart';
import 'workout_painter.dart';
import 'workout_training_load.dart';

/// Features today's plan without replacing or starting the selected workout.
class IntervalsTodayCard extends StatefulWidget {
  const IntervalsTodayCard({
    super.key,
    required this.ftp,
    required this.onSelect,
    this.isConnected = IntervalsService.isAuthenticated,
    this.loadToday = IntervalsService.getTodaysWorkout,
  });

  final double ftp;
  final ValueChanged<WorkoutLobbyChoice> onSelect;
  final Future<bool> Function() isConnected;
  final Future<Map<String, dynamic>?> Function() loadToday;

  @override
  State<IntervalsTodayCard> createState() => _IntervalsTodayCardState();
}

class _IntervalsTodayCardState extends State<IntervalsTodayCard>
    with WidgetsBindingObserver {
  static const _accent = Color(0xff8abaff);
  WorkoutLobbyChoice? _choice;
  bool _connected = false, _loading = false, _failed = false;
  bool _foreground = true;
  int _revision = 0;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    IntervalsService.connectionChanges.addListener(_reload);
    unawaited(_reload());
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    _midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (_foreground) unawaited(_reload());
        _scheduleMidnight();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_reload());
      _scheduleMidnight();
    }
  }

  Future<void> _reload() async {
    final revision = ++_revision;
    // A new date/account must never leave the previous plan actionable.
    setState(() {
      _choice = null;
      _loading = true;
      _failed = false;
    });
    try {
      final connected = await widget.isConnected();
      if (!mounted || revision != _revision) return;
      setState(() => _connected = connected);
      if (!connected) return;
      final event = await widget.loadToday().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted || revision != _revision) return;
      if (event != null) {
        final content = IntervalsWorkoutConverter.convertEventToZwo(event);
        if (content == null) throw const FormatException('No workout data');
        final choice = WorkoutLobbyChoice(
          content: content,
          source: 'TODAY · INTERVALS.ICU',
        );
        if (choice.workout.segments.isEmpty)
          throw const FormatException('Empty workout');
        setState(() => _choice = choice);
      }
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _failed = true);
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    IntervalsService.connectionChanges.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_connected) return const SizedBox.shrink();
    final choice = _choice;
    final duration =
        choice?.workout.segments.fold<int>(
          0,
          (sum, s) => sum + math.max(0, s.duration),
        ) ??
        0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        key: const ValueKey('intervals-today-card'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xff203b57), Color(0xff121e33)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _accent.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TODAY’S RIDE · INTERVALS.ICU',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) ...[
              const Text('Checking today’s plan…'),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (choice != null) ...[
              Text(
                choice.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                duration == 0
                    ? 'Open-ended ride'
                    : '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')} · ${choice.workout.segments.length} ${choice.workout.segments.length == 1 ? 'interval' : 'intervals'}',
                style: const TextStyle(color: Color(0xffc3cde0)),
              ),
              if (duration > 0) ...[
                const SizedBox(height: 8),
                Text(
                  WorkoutTrainingLoad.label(choice.estimatedTss),
                  style: const TextStyle(color: _accent),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Today’s planned workout power profile',
                  child: SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: WorkoutPainter.preview(
                          choice.workout.segments,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => widget.onSelect(choice),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Load today’s ride'),
              ),
            ] else ...[
              Text(
                _failed
                    ? 'Today’s ride couldn’t be loaded.'
                    : 'No planned ride available for today.',
                style: const TextStyle(color: Color(0xffc3cde0)),
              ),
              const SizedBox(height: 4),
              const Text(
                'You can still choose a workout below.',
                style: TextStyle(color: Color(0xffa4b5cc), fontSize: 12),
              ),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
