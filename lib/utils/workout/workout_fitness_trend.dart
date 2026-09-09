import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'workout_coach_recovery.dart';

/// A small chart of the existing wellness snapshot; never fetches data itself.
class WorkoutFitnessTrend extends StatefulWidget {
  const WorkoutFitnessTrend({
    super.key,
    required this.history,
    required this.now,
  });
  final List<CoachWellness> history;
  final DateTime now;

  static List<CoachWellness> visibleHistory(
    List<CoachWellness> history,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final byDay = {
      for (final row in history)
        if (row.hasFitness &&
            !row.day.isAfter(today) &&
            !row.day.isBefore(
              DateTime(today.year, today.month, today.day - 28),
            ))
          row.day: row,
    };
    return byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  State<WorkoutFitnessTrend> createState() => _WorkoutFitnessTrendState();
}

class _WorkoutFitnessTrendState extends State<WorkoutFitnessTrend> {
  DateTime? _selected;
  static const colors = [
    Color(0xff50c9ff),
    Color(0xffbe9aff),
    Color(0xff72e4c1),
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final rows = WorkoutFitnessTrend.visibleHistory(widget.history, widget.now);
    final byDay = {for (final row in rows) row.day: row};
    if (rows.isEmpty) return const SizedBox.shrink();
    final selected = byDay[_selected] ?? rows.last;
    final localizations = MaterialLocalizations.of(context);
    String date(DateTime day) => localizations.formatShortMonthDay(day);
    final values = [selected.fitness!, selected.fatigueLoad!, selected.form!];
    String number(double value, {bool signed = false}) {
      final rounded = value.round();
      return '${signed && rounded > 0 ? '+' : ''}$rounded';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Intervals.icu · ${selected.day == today ? 'Today' : date(selected.day)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xffb7c8dd),
                  ),
                ),
              ),
              if (_selected != null)
                InkWell(
                  onTap: () => setState(() => _selected = null),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text('Latest', style: TextStyle(fontSize: 11)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(
                    width: math.min(
                      constraints.maxWidth,
                      math.max(88, (constraints.maxWidth - 24) / 3),
                    ),
                    child: Semantics(
                      label:
                          '${['Fitness', 'Fatigue', 'Form'][i]} ${number(values[i], signed: i == 2)}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ['Fitness', 'Fatigue', 'Form'][i],
                            style: TextStyle(color: colors[i], fontSize: 12),
                          ),
                          Text(
                            number(values[i], signed: i == 2),
                            style: TextStyle(
                              color: colors[i],
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (rows.length >= 2) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                void inspect(double x) {
                  final fraction =
                      ((x - 30) / math.max(1, constraints.maxWidth - 36)).clamp(
                        0.0,
                        1.0,
                      );
                  final target =
                      _day(rows.first.day) +
                      fraction * (_day(rows.last.day) - _day(rows.first.day));
                  final nearest = rows.reduce(
                    (a, b) =>
                        (_day(a.day) - target).abs() <=
                            (_day(b.day) - target).abs()
                        ? a
                        : b,
                  );
                  if (_selected != nearest.day)
                    setState(() => _selected = nearest.day);
                }

                return Semantics(
                  label:
                      'Fitness, fatigue and form trend from ${date(rows.first.day)} to ${date(rows.last.day)}. Tap or hover to inspect a day.',
                  child: MouseRegion(
                    onHover: (event) => inspect(event.localPosition.dx),
                    child: GestureDetector(
                      onTapDown: (event) => inspect(event.localPosition.dx),
                      onHorizontalDragUpdate: (event) =>
                          inspect(event.localPosition.dx),
                      child: SizedBox(
                        height: 105,
                        width: double.infinity,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: const ValueKey('fitness-trend-chart'),
                            painter: _FitnessPainter(
                              rows,
                              selected.day,
                              colors,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date(rows.first.day),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xffb7c8dd),
                  ),
                ),
                Text(
                  date(rows.last.day),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xffb7c8dd),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

int _day(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

class _FitnessPainter extends CustomPainter {
  const _FitnessPainter(this.rows, this.selected, this.colors);
  final List<CoachWellness> rows;
  final DateTime selected;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final values = rows.expand((r) => [r.fitness!, r.fatigueLoad!, r.form!]);
    final low = (math.min(0.0, values.reduce(math.min)) / 10).floor() * 10.0;
    final high = math.max(
      low + 10,
      (values.reduce(math.max) / 10).ceil() * 10.0,
    );
    final area = Rect.fromLTRB(30, 6, size.width - 6, size.height - 6);
    if (area.width <= 0) return;
    double x(CoachWellness r) =>
        area.left +
        (_day(r.day) - _day(rows.first.day)) /
            math.max(1, _day(rows.last.day) - _day(rows.first.day)) *
            area.width;
    double y(double value) =>
        area.bottom - (value - low) / (high - low) * area.height;
    for (final value in {low, 0.0, high}) {
      canvas.drawLine(
        Offset(area.left, y(value)),
        Offset(area.right, y(value)),
        Paint()..color = Colors.white.withValues(alpha: value == 0 ? .25 : .1),
      );
      final label = TextPainter(
        text: TextSpan(
          text: value.round().toString(),
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'Roboto',
            color: Color(0xffb7c8dd),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(area.left - label.width - 5, y(value) - label.height / 2),
      );
    }
    final chosen = rows.firstWhere((r) => r.day == selected);
    canvas.drawLine(
      Offset(x(chosen), area.top),
      Offset(x(chosen), area.bottom),
      Paint()..color = Colors.white.withValues(alpha: .2),
    );
    for (var series = 0; series < 3; series++) {
      double value(CoachWellness r) =>
          [r.fitness!, r.fatigueLoad!, r.form!][series];
      final path = Path();
      for (var i = 0; i < rows.length; i++) {
        final point = Offset(x(rows[i]), y(value(rows[i])));
        // Leave gaps for unreported days instead of inventing continuous data.
        if (i == 0 || _day(rows[i].day) - _day(rows[i - 1].day) > 1) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(
          point,
          rows[i].day == selected ? 3 : 1.5,
          Paint()..color = colors[series],
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[series]
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FitnessPainter oldDelegate) =>
      oldDelegate.rows != rows || oldDelegate.selected != selected;
}
