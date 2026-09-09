import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/intervals_service.dart';
import 'workout_coach.dart';
import 'workout_coach_repository.dart';
import 'workout_lobby_choice.dart';
import 'workout_painter.dart';
import 'workout_fitness_trend.dart';
import 'workout_training_load.dart';

class WorkoutCoachCard extends StatefulWidget {
  const WorkoutCoachCard({
    super.key,
    required this.ftp,
    required this.onSelect,
    required this.onBrowse,
    this.load = WorkoutCoachRepository.load,
    this.saveGoal = WorkoutCoachRepository.saveGoal,
    this.reconnect = IntervalsService.authenticate,
  });
  final double ftp;
  final ValueChanged<WorkoutLobbyChoice> onSelect;
  final VoidCallback onBrowse;
  final Future<CoachData> Function(double, {bool refreshRemote}) load;
  final Future<void> Function(CoachGoal) saveGoal;
  final Future<void> Function(BuildContext) reconnect;
  @override
  State<WorkoutCoachCard> createState() => _WorkoutCoachCardState();
}

class _WorkoutCoachCardState extends State<WorkoutCoachCard>
    with WidgetsBindingObserver {
  CoachData? _data;
  CoachGoal? _goal;
  bool _failed = false;
  bool _refreshing = true, _reconnecting = false;
  int _revision = 0;
  Timer? _dayTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    IntervalsService.connectionChanges.addListener(_accountChanged);
    WorkoutCoachRepository.changes.addListener(_refresh);
    unawaited(_refresh());
    _scheduleDay();
  }

  Future<void> _accountChanged() async {
    setState(() => _data = null);
    try {
      await WorkoutCoachRepository.invalidateRemoteAttempt();
    } catch (_) {}
    if (mounted) unawaited(_refresh());
  }

  void _scheduleDay() {
    _dayTimer?.cancel();
    final now = DateTime.now();
    _dayTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        unawaited(_refresh());
        _scheduleDay();
      },
    );
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    if (mounted) setState(() => _refreshing = true);
    try {
      // The first result uses local files and cached data. Network refresh is
      // separate, so it cannot hold up the card or any workout controls.
      final local = await widget.load(widget.ftp, refreshRemote: false);
      if (!mounted || revision != _revision) return;
      setState(() {
        _data = local;
        _goal ??= local.goal;
        _failed = false;
      });
      final refreshed = await widget.load(widget.ftp, refreshRemote: true);
      if (!mounted || revision != _revision) return;
      setState(() => _data = refreshed);
    } catch (_) {
      if (mounted && revision == _revision && _data == null)
        setState(() => _failed = true);
    } finally {
      if (mounted && revision == _revision) setState(() => _refreshing = false);
    }
  }

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      await widget.reconnect(context);
      await WorkoutCoachRepository.invalidateRemoteAttempt();
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not reconnect to Intervals.icu. Please try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  void didUpdateWidget(covariant WorkoutCoachCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ftp != widget.ftp) unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      _scheduleDay();
    }
  }

  Future<void> _setGoal(CoachGoal goal) async {
    setState(() => _goal = goal);
    try {
      await widget.saveGoal(goal);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your goal is set for this visit, but could not be saved.',
            ),
          ),
        );
    }
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    IntervalsService.connectionChanges.removeListener(_accountChanged);
    WorkoutCoachRepository.changes.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xff8abaff);
    const muted = Color(0xffb7c8dd);
    final data = _data;
    final now = DateTime.now();
    final trendHistory = WorkoutFitnessTrend.visibleHistory(
      data?.wellness ?? const [],
      now,
    );
    final hasGraph = trendHistory.length >= 2;
    final today = DateTime(now.year, now.month, now.day);
    final hasCurrentFitness = trendHistory.any((row) => row.day == today);
    final showReconnect =
        !_refreshing &&
        data != null &&
        (data.needsReconnect ||
            (data.account != 'local' && !hasCurrentFitness));
    final advice = data == null
        ? null
        : WorkoutCoach.recommend(
            history: data.history,
            candidates: data.candidates,
            now: now,
            goal: _goal ?? data.goal,
            incomplete: data.incomplete,
            wellness: data.wellness,
          );
    final candidate = advice?.candidate;
    return Container(
      key: const ValueKey('workout-coach-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: .12), const Color(0xff10182e)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR NEXT SESSION',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CoachGoal>(
            key: ValueKey(_goal),
            initialValue: _goal ?? CoachGoal.consistent,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Your fitness goal',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final goal in CoachGoal.values)
                DropdownMenuItem(
                  value: goal,
                  child: Text(goal.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (goal) {
              if (goal != null) unawaited(_setGoal(goal));
            },
          ),
          const SizedBox(height: 16),
          Text(
            advice?.title ??
                (_failed
                    ? 'Choose a ride that feels right'
                    : 'Finding your next ride…'),
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            advice?.reason ??
                (_failed
                    ? 'Ride suggestions are unavailable right now. Your workout library is ready.'
                    : 'Looking at your recent rides and available workouts.'),
            style: const TextStyle(color: muted, height: 1.4),
          ),
          if (advice != null) ...[
            if (data?.wellness != null)
              WorkoutFitnessTrend(history: trendHistory, now: now),
            if (!hasGraph) ...[
              const SizedBox(height: 12),
              Text(
                '${advice.rides} completed ${advice.rides == 1 ? 'ride' : 'rides'} in the last 7 days',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (advice.recoveryNote != null) ...[
                const SizedBox(height: 8),
                Text(
                  advice.recoveryNote!,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ],
          if (advice?.rest == true) ...[
            const SizedBox(height: 24),
            const Icon(Icons.spa_outlined, size: 48, color: accent),
            const SizedBox(height: 12),
            const Text(
              'Recovery is part of getting stronger. Come back refreshed.',
              style: TextStyle(color: muted, height: 1.5),
            ),
          ] else if (candidate != null) ...[
            const SizedBox(height: 16),
            Text(
              candidate.choice.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${candidate.choice.source} · ${(candidate.seconds / 60).round()} min · ${candidate.intensity <= .65
                  ? 'Easy effort'
                  : candidate.intensity <= .8
                  ? 'Steady effort'
                  : 'Challenging effort'} · ${WorkoutTrainingLoad.label(candidate.tss)}',
              style: const TextStyle(color: accent, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'Suggested workout power profile',
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: WorkoutPainter.preview(
                      candidate.choice.workout.segments,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (candidate != null && advice?.rest != true)
                FilledButton.icon(
                  onPressed: () => widget.onSelect(candidate.choice),
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: const Text('Load suggested ride'),
                ),
              TextButton.icon(
                onPressed: widget.onBrowse,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Explore workouts'),
              ),
            ],
          ),
          if (data != null) ...[
            // The graph already identifies Intervals.icu. Keep only actionable
            // sync/account messages alongside it, rather than repeating sources.
            if (!showReconnect &&
                (!hasGraph || data.incomplete || data.needsReconnect)) ...[
              const SizedBox(height: 8),
              Text(
                data.note,
                style: const TextStyle(color: muted, fontSize: 11, height: 1.4),
              ),
            ],
            if (showReconnect)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: .25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCurrentFitness
                          ? 'Include your ride history'
                          : 'Connect your fitness data',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasCurrentFitness
                          ? 'Reconnect Intervals.icu to review activity access, so workout suggestions can account for your completed rides.'
                          : 'Intervals.icu is connected, but today’s Fitness, Fatigue and Form are unavailable. Your connection may need wellness access. Reconnect and allow it to help tailor workout load and recovery days to your fitness.',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (!data.needsReconnect && !hasCurrentFitness) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'If access is already enabled, check that your data has synced in Intervals.icu.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _reconnecting ? null : _reconnect,
                      icon: const Icon(Icons.link, size: 18),
                      label: Text(
                        _reconnecting
                            ? 'Connecting…'
                            : 'Reconnect Intervals.icu',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
