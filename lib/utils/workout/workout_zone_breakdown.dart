import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'workout_profile.dart';
import 'workout_parser.dart';

/// Uses the app's seven training zones. Ramps are counted
/// second by second; unprescribed efforts are never assigned a power zone.
class WorkoutZoneTime {
  static final limits = WorkoutPowerZone.values
      .take(6)
      .map((zone) => zone.upper)
      .toList(growable: false);
  final seconds = List<int>.filled(8, 0);
  bool openEnded = false;
  int get total => seconds.fold(0, (a, b) => a + b);
  WorkoutZoneTime(List<WorkoutSegment> segments) {
    for (final segment in segments) {
      if (segment.duration <= 0) {
        openEnded = true;
        continue;
      }
      if (segment.type == SegmentType.freeRide ||
          segment.type == SegmentType.maxEffort ||
          segment.duration > 86400) {
        seconds[7] += segment.duration;
      } else if (!segment.isRamp) {
        seconds[WorkoutPowerZone.forSegment(segment).index] += segment.duration;
      } else {
        for (var t = 0; t < segment.duration; t++) {
          seconds[WorkoutPowerZone.forSegment(
            segment,
            t / segment.duration,
          ).index]++;
        }
      }
    }
  }
}

class WorkoutZoneBreakdown extends StatefulWidget {
  const WorkoutZoneBreakdown({
    super.key,
    required this.segments,
    required this.ftp,
  });
  final List<WorkoutSegment> segments;
  final double ftp;
  @override
  State<WorkoutZoneBreakdown> createState() => _WorkoutZoneBreakdownState();
}

class _WorkoutZoneBreakdownState extends State<WorkoutZoneBreakdown> {
  late WorkoutZoneTime _time = WorkoutZoneTime(widget.segments);
  static final labels = WorkoutPowerZone.values
      .map((zone) => zone.label)
      .toList(growable: false);
  static final colors = WorkoutPowerZone.values
      .map((zone) => zone.color)
      .toList(growable: false);
  @override
  void didUpdateWidget(covariant WorkoutZoneBreakdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments)
      _time = WorkoutZoneTime(widget.segments);
  }

  String duration(int seconds) => seconds % 60 == 0
      ? '${seconds ~/ 60} min'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  String range(int zone) {
    if (zone == 7) return 'No fixed power target';
    final lower = zone == 0
        ? 0
        : (WorkoutZoneTime.limits[zone - 1] * widget.ftp).floor() + 1;
    return zone == 6
        ? '$lower+ W'
        : '$lower–${(WorkoutZoneTime.limits[zone] * widget.ftp).floor()} W';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const SizedBox.shrink();
    final active = [
      for (var i = 0; i < 8; i++)
        if (_time.seconds[i] > 0) i,
    ];
    return Container(
      key: const ValueKey('workout-zone-breakdown'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff121e33),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xff2c435a)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TIME IN ZONES',
            style: TextStyle(
              color: Color(0xff72e4c1),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _time.openEnded
                ? 'Your effort is open-ended; these are the planned portions.'
                : 'Selected workout · based on FTP ${widget.ftp.round()} W',
            style: const TextStyle(color: Color(0xffa4b5cc), fontSize: 12),
          ),
          if (_time.total > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final i in active)
                      Expanded(
                        flex: _time.seconds[i],
                        child: ColoredBox(
                          color: colors[i],
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 390 ? 2 : 1;
                return Wrap(
                  spacing: 20,
                  runSpacing: 14,
                  children: [
                    for (final i in active)
                      SizedBox(
                        width: math.max(
                          0,
                          (constraints.maxWidth - (columns - 1) * 20) / columns,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 7,
                              height: 30,
                              margin: const EdgeInsets.only(right: 9, top: 2),
                              decoration: BoxDecoration(
                                color: colors[i],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${labels[i]} · ${duration(_time.seconds[i])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    range(i),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xffa4b5cc),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              'No fixed power targets for this ride.',
              style: TextStyle(color: Color(0xffa4b5cc)),
            ),
          ],
        ],
      ),
    );
  }
}
