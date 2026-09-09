import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'workout_lobby_choice.dart';
import 'workout_painter.dart';
import 'workout_parser.dart';
import 'workout_account_prompt.dart';
import 'intervals_today_card.dart';
import 'workout_coach_card.dart';
import 'workout_training_load.dart';
import 'workout_zone_breakdown.dart';

/// A pre-ride surface. Selection and setup never start the workout clock.
class WorkoutLobby extends StatefulWidget {
  const WorkoutLobby({
    super.key,
    required this.name,
    required this.segments,
    required this.endless,
    required this.ftp,
    required this.onStart,
    required this.onFtp,
    required this.onSelect,
    required this.onBrowse,
    this.loadChoices = WorkoutLobbyChoice.loadChoices,
  });

  final String name;
  final List<WorkoutSegment> segments;
  final bool endless;
  final double ftp;
  final VoidCallback? onStart;
  final ValueChanged<double> onFtp;
  final ValueChanged<WorkoutLobbyChoice> onSelect;
  final VoidCallback onBrowse;
  final Future<List<WorkoutLobbyChoice>> Function() loadChoices;

  @override
  State<WorkoutLobby> createState() => _WorkoutLobbyState();
}

class _WorkoutLobbyState extends State<WorkoutLobby> {
  static const _mint = Color(0xff72e4c1);
  static const _blue = Color(0xff8abaff);
  static const _muted = Color(0xffa4b5cc);
  late final _choices = widget.loadChoices();
  final _scroll = ScrollController();
  late double? _selectedTss = WorkoutTrainingLoad.estimate(
    widget.segments,
  )?.tss;

  @override
  void didUpdateWidget(covariant WorkoutLobby oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments) {
      _selectedTss = WorkoutTrainingLoad.estimate(widget.segments)?.tss;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _duration(List<WorkoutSegment> segments) =>
      segments.fold(0, (sum, segment) => sum + math.max(0, segment.duration));

  String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Widget _label(String text, {Color color = _mint}) => Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    ),
  );

  Widget _card(Widget child, {Color accent = _mint}) => Container(
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
    child: child,
  );

  Widget _profile(List<WorkoutSegment> segments, {double height = 88}) {
    final duration = _duration(segments);
    if (duration == 0) return const SizedBox.shrink();
    return Semantics(
      label: 'Workout power profile, ${_time(duration)} total',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(painter: WorkoutPainter.preview(segments)),
        ),
      ),
    );
  }

  String get _firstInterval {
    final segment = widget.segments.first;
    if (segment.type == SegmentType.freeRide)
      return 'First interval · Free ride';
    if (segment.type == SegmentType.maxEffort)
      return 'First interval · Max effort';
    final start = (segment.getPowerAtTime(0) * widget.ftp).round();
    final end = (segment.getPowerAtTime(segment.duration) * widget.ftp).round();
    return 'First interval · ${segment.isRamp ? '$start→$end' : '$start'} W · ${_time(segment.duration)}';
  }

  Future<void> _editFtp() async {
    var ftp = widget.ftp.clamp(50.0, 500.0);
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Workout FTP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${ftp.round()} W',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Slider(
                value: ftp,
                min: 50,
                max: 500,
                divisions: 450,
                label: '${ftp.round()} W',
                onChanged: (value) => update(() => ftp = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ftp),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) widget.onFtp(result);
  }

  Widget _selected() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SELECTED WORKOUT'),
        const SizedBox(height: 10),
        Text(
          widget.segments.isEmpty ? 'Choose your next ride' : widget.name,
          style: const TextStyle(
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (widget.segments.isNotEmpty) ...[
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              Text(
                widget.endless
                    ? 'Open-ended'
                    : '${_time(_duration(widget.segments))} duration',
                style: const TextStyle(color: _muted),
              ),
              if (!widget.endless)
                Text(
                  '${widget.segments.length} intervals',
                  style: const TextStyle(color: _muted),
                ),
              Text(
                WorkoutTrainingLoad.label(_selectedTss),
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (widget.endless)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Row(
                children: [
                  Icon(Icons.all_inclusive, color: _mint, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Settle in. Ride as long as you like.',
                      style: TextStyle(color: _muted),
                    ),
                  ),
                ],
              ),
            )
          else
            _profile(widget.segments),
          const SizedBox(height: 16),
          Text(
            _firstInterval,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _editFtp,
          icon: const Icon(Icons.tune, size: 18),
          label: Text('FTP ${widget.ftp.round()} W · Adjust'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('workout-lobby-start'),
            style: FilledButton.styleFrom(
              backgroundColor: _mint,
              foregroundColor: const Color(0xff08231f),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            ),
            onPressed: widget.segments.isEmpty ? null : widget.onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('START WORKOUT'),
          ),
        ),
      ],
    ),
  );

  Widget _welcome() => WorkoutCoachCard(
    ftp: widget.ftp,
    onSelect: widget.onSelect,
    onBrowse: widget.onBrowse,
  );

  Widget _shelf(double width) => FutureBuilder<List<WorkoutLobbyChoice>>(
    future: _choices,
    builder: (context, snapshot) {
      final choices = (snapshot.data ?? const <WorkoutLobbyChoice>[])
          .where((choice) => choice.name != widget.name)
          .toList();
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
      }
      if (choices.isEmpty) {
        return const Text(
          'Find your next session in the workout library.',
          style: TextStyle(color: _muted),
        );
      }
      final columns = width >= 900
          ? 3
          : width >= 580
          ? 2
          : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final choice in choices)
            SizedBox(
              width: (width - (columns - 1) * 12) / columns,
              child: Material(
                color: const Color(0xff121e33),
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onSelect(choice),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(choice.source, color: _blue),
                        const SizedBox(height: 10),
                        Text(
                          choice.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _profile(choice.workout.segments, height: 36),
                        const SizedBox(height: 12),
                        Text(
                          WorkoutTrainingLoad.label(choice.estimatedTss),
                          style: const TextStyle(fontSize: 12, color: _blue),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                choice.workout.segments.any(
                                      (s) =>
                                          s.type == SegmentType.freeRide &&
                                          s.duration <= 0,
                                    )
                                    ? 'Open-ended'
                                    : '${_time(_duration(choice.workout.segments))} ride',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: _mint,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _mint,
        brightness: Brightness.dark,
      ),
    ),
    child: Material(
      color: const Color(0xff080f21),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(
              1120.0,
              math.max(0.0, constraints.maxWidth - 32),
            );
            return SingleChildScrollView(
              key: const ValueKey('workout-lobby'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IntervalsTodayCard(
                        ftp: widget.ftp,
                        onSelect: widget.onSelect,
                      ),
                      if (width >= 760)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _welcome()),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  _selected(),
                                  WorkoutZoneBreakdown(
                                    segments: widget.segments,
                                    ftp: widget.ftp,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _selected(),
                        const SizedBox(height: 16),
                        _welcome(),
                        WorkoutZoneBreakdown(
                          segments: widget.segments,
                          ftp: widget.ftp,
                        ),
                      ],
                      const WorkoutAccountPrompt(),
                      const SizedBox(height: 26),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          _label('CHOOSE ANOTHER WORKOUT'),
                          TextButton.icon(
                            onPressed: () => widget.onSelect(
                              WorkoutLobbyChoice(
                                content:
                                    '<workout_file><name>Free Ride</name><workout><FreeRide Duration="0"/></workout></workout_file>',
                                source: 'FREE RIDE',
                              ),
                            ),
                            icon: const Icon(Icons.all_inclusive, size: 18),
                            label: const Text('Choose free ride'),
                          ),
                          TextButton.icon(
                            onPressed: widget.onBrowse,
                            icon: const Icon(
                              Icons.folder_open_rounded,
                              size: 18,
                            ),
                            label: const Text('Browse workouts'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _shelf(width),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
