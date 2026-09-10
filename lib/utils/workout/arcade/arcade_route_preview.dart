import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../workout_parser.dart';
import '../workout_painter.dart';
import '../workout_profile.dart';
import 'arcade_segment_profile.dart';
import 'arcade_world_painter.dart';

class ArcadeRoutePreview extends StatelessWidget {
  const ArcadeRoutePreview({
    super.key,
    required this.segments,
    required this.index,
    required this.seconds,
    required this.ftp,
    required this.endless,
    required this.compact,
    required this.cleared,
    this.workoutLabels = false,
  });
  final List<WorkoutSegment> segments;
  final int index;
  final double seconds;
  final double ftp;
  final bool endless;
  final bool compact;
  final Set<int> cleared;

  /// Reuse the interval strip in Classic without the expedition terminology.
  final bool workoutLabels;

  double _start(int i) =>
      segments.take(i).fold<double>(0, (sum, s) => sum + s.duration);
  String _description(int i) =>
      'Interval ${i + 1}: ${arcadeTargetLabel(segments[i], ftp)}, '
      '${arcadeIntervalDuration(segments[i].duration)}, ${arcadeTargetLabel(segments[i], ftp, percent: true)}'
      '${cleared.contains(i) ? ', secured' : ''}';

  Future<void> _details(
    BuildContext context,
    int from,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: arcadeInk,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: math.min(460, MediaQuery.sizeOf(context).height * .65),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'INTERVAL PLAN',
                style: TextStyle(
                  color: arcadeMint,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: segments.length - from,
                itemBuilder: (context, offset) {
                  final i = from + offset, segment = segments[i];
                  return ListTile(
                    leading: SizedBox(
                      width: 38,
                      height: 26,
                      child: CustomPaint(
                        painter: WorkoutPainter.preview([segment], peak: _peak),
                      ),
                    ),
                    title: Text(
                      '${i + 1}. ${arcadeTargetLabel(segment, ftp)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${arcadeTargetLabel(segment, ftp, percent: true)} · starts at ${arcadeIntervalDuration(_start(i))}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: Text(
                      arcadeIntervalDuration(segment.duration),
                      style: const TextStyle(color: arcadeGold),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  double get _peak => WorkoutPainter.profilePeak(segments);

  @override
  Widget build(BuildContext context) {
    final current = segments.isEmpty ? 0 : index.clamp(0, segments.length - 1);
    final start = math.max(0, current - 2);
    final end = math.min(segments.length, start + 24);
    final total = _start(segments.length);
    final currentStart = _start(current);
    final remaining = segments.isEmpty
        ? 0.0
        : math.max(0.0, currentStart + segments[current].duration - seconds);
    final progress = segments.isEmpty || segments[current].duration <= 0
        ? 0.0
        : ((seconds - currentStart) / segments[current].duration).clamp(
            0.0,
            1.0,
          );
    final peak = _peak;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth >= 700
              ? 3
              : constraints.maxWidth >= 500
              ? 2
              : 1;
          final upcoming = [
            for (
              var i = current + 1;
              i < segments.length && i <= current + count;
              i++
            )
              i,
          ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!endless && segments.isNotEmpty) ...[
                if (upcoming.isNotEmpty)
                  Row(
                    children: [
                      for (final i in upcoming)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: i == upcoming.last ? 0 : 14,
                            ),
                            child: InkWell(
                              onTap: () => _details(context, i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: compact ? 22 : 27,
                                      color: WorkoutPowerZone.forSegment(
                                        segments[i],
                                        0,
                                      ).color,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            i == current + 1
                                                ? 'NEXT · IN ${arcadeIntervalDuration(remaining)}'
                                                : 'THEN · ${i - current} AHEAD',
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 9,
                                              letterSpacing: .5,
                                            ),
                                          ),
                                          Text(
                                            '${arcadeTargetLabel(segments[i], ftp)} · ${arcadeIntervalDuration(segments[i].duration)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: i == current + 1
                                                  ? Colors.white
                                                  : Colors.white70,
                                              fontSize: compact ? 11 : 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (i == upcoming.last)
                                      const Icon(
                                        Icons.expand_less,
                                        size: 15,
                                        color: Colors.white38,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        seconds >= total
                            ? (workoutLabels
                                  ? 'WORKOUT COMPLETE'
                                  : 'ROUTE COMPLETE')
                            : 'FINISH IN ${arcadeIntervalDuration(remaining)}',
                        style: const TextStyle(
                          color: arcadeMint,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${workoutLabels ? 'INTERVAL' : 'ROUTE'} ${segments.isEmpty ? 0 : current + 1}/${segments.length}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Text(
                    endless
                        ? (workoutLabels ? 'FREE RIDE' : 'ENDLESS EXPEDITION')
                        : '${arcadeIntervalDuration(seconds)} / ${arcadeIntervalDuration(total)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: compact ? 16 : 23,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < end; i++)
                      Expanded(
                        flex: math.max(1, segments[i].duration),
                        child: Semantics(
                          label: _description(i),
                          button: true,
                          child: Tooltip(
                            message: _description(i),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _details(context, i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                child: CustomPaint(
                                  painter: WorkoutPainter.preview(
                                    [segments[i]],
                                    peak: peak,
                                    highlightCurrent: i == current,
                                    completed: i < current,
                                    progress: progress,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
