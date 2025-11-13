import 'dart:math';
import 'package:flutter/material.dart';
import 'workout/workout_constants.dart';
import 'constants.dart';

class PowerTablePainter extends CustomPainter {
  final List<List<double?>> powerTableData;
  final List<int> cadences;
  final List<Color> colors;
  final double maxResistance;
  final double? homingMin; // currently unused but preserved
  final double? homingMax;
  final double currentWatts;
  final double currentResistance;
  final int currentCadence;
  final List<Map<String, double>> positionHistory; // stores {'x': watts, 'y': rawResistance}
  final double tableDivisor;
  final bool swapAxes; // false: Resistance(Y)/Watts(X), true: Watts(Y)/Resistance(X)

  PowerTablePainter({
    required this.powerTableData,
    required this.cadences,
    required this.colors,
    required this.maxResistance,
    this.homingMin,
    this.homingMax,
    required this.currentWatts,
    required this.currentResistance,
    required this.currentCadence,
    required this.positionHistory,
    required this.tableDivisor,
    required this.swapAxes,
  });

  final leftPadding = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = WorkoutStroke.actualPowerLine;

    _drawGrid(canvas, size);

    for (int i = 0; i < powerTableData.length; i++) {
      paint.color = colors[i % colors.length];
      _drawPowerCurve(canvas, size, powerTableData[i], paint);
    }

    _drawPositionHistory(canvas, size);

    if (currentWatts > 0 && currentWatts <= MIN_POWER_RANGE) {
      _drawCurrentPosition(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.withOpacity(WorkoutOpacity.gridLines)
      ..strokeWidth = WorkoutStroke.border;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    double minRes = 0;
    double maxRes = max(MIN_RESISTANCE_RANGE, homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE));
    double range = maxRes - minRes;

    if (!swapAxes) {
      // Resistance on Y axis
      for (double resistance = minRes; resistance <= maxRes; resistance += range / 5) {
        final y = size.height - ((resistance - minRes) * size.height / range);
        canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
        // Round resistance to nearest whole number for labels
        textPainter.text = TextSpan(
          text: resistance.round().toString(),
          style: TextStyle(color: Colors.grey[600], fontSize: WorkoutFontSizes.small),
        );
        textPainter.layout();
        final double labelX = max(0.0, leftPadding - textPainter.width - 4);
        textPainter.paint(canvas, Offset(labelX, y - textPainter.height / 2));
      }
      for (double watts = 0; watts <= MIN_POWER_RANGE; watts += 100) {
        final x = leftPadding + (watts * (size.width - leftPadding) / MIN_POWER_RANGE);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        if (watts > 0) {
          textPainter.text = TextSpan(
            text: '${watts.toInt()}w',
            style: TextStyle(color: Colors.grey[600], fontSize: WorkoutFontSizes.small),
          );
          textPainter.layout();
          double labelX = x - textPainter.width / 2;
          labelX = max(0.0, min(size.width - textPainter.width, labelX));
          textPainter.paint(canvas, Offset(labelX, -5));
        }
      }
    } else {
      // Watts on Y axis
      for (double watts = 0; watts <= MIN_POWER_RANGE; watts += MIN_POWER_RANGE / 5) {
        final y = size.height - (watts * size.height / MIN_POWER_RANGE);
        canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
        textPainter.text = TextSpan(
          text: '${watts.toInt()}w',
          style: TextStyle(color: Colors.grey[600], fontSize: WorkoutFontSizes.small),
        );
        textPainter.layout();
        final double labelX = max(0.0, leftPadding - textPainter.width - 4);
        textPainter.paint(canvas, Offset(labelX, y - textPainter.height / 2));
      }
      for (double resistance = minRes; resistance <= maxRes; resistance += range / 5) {
        final x = leftPadding + ((resistance - minRes) * (size.width - leftPadding) / range);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        if (resistance > minRes) {
          textPainter.text = TextSpan(
            text: resistance.round().toString(),
            style: TextStyle(color: Colors.grey[600], fontSize: WorkoutFontSizes.small),
          );
          textPainter.layout();
          double labelX = x - textPainter.width / 2;
          labelX = max(0.0, min(size.width - textPainter.width, labelX));
          textPainter.paint(canvas, Offset(labelX, -5));
        }
      }
    }
  }

  void _drawPowerCurve(Canvas canvas, Size size, List<double?> data, Paint paint) {
    final path = Path();
    bool isFirstPoint = true;
    Offset? lastValidPoint;

    double minRes = 0;
    double maxRes = max(MIN_RESISTANCE_RANGE, homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE));
    double range = maxRes - minRes;

    for (int i = 0; i < data.length && i * 30 <= MIN_POWER_RANGE; i++) {
      if (data[i] != null) {
        double powerValue = i * 30;
        double resistanceValue = data[i]!;
        double x;
        double y;
        if (!swapAxes) {
          x = leftPadding + (powerValue * (size.width - leftPadding) / MIN_POWER_RANGE);
          y = size.height - ((resistanceValue - minRes) * size.height / range);
        } else {
          x = leftPadding + ((resistanceValue - minRes) * (size.width - leftPadding) / range);
          y = size.height - (powerValue * size.height / MIN_POWER_RANGE);
        }
        if (x >= leftPadding && x <= size.width && y >= 0 && y <= size.height) {
          if (isFirstPoint) {
            path.moveTo(x, y);
            isFirstPoint = false;
          } else {
            if (lastValidPoint != null && lastValidPoint != Offset(x, y)) {
              path.moveTo(lastValidPoint.dx, lastValidPoint.dy);
            }
            path.lineTo(x, y);
          }
          lastValidPoint = Offset(x, y);
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawPositionHistory(Canvas canvas, Size size) {
    for (int i = 0; i < positionHistory.length; i++) {
      final position = positionHistory[i];
      final opacity = (i + 1) / positionHistory.length;
      final paint = Paint()
        ..color = _getCadenceColor(currentCadence).withOpacity(opacity * 0.3)
        ..style = PaintingStyle.fill;

      double minRes = 0;
      double maxRes = max(MIN_RESISTANCE_RANGE, homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE));
      double range = maxRes - minRes;
      double x;
      double y;
      if (!swapAxes) {
        x = leftPadding + (position['x']! * (size.width - leftPadding) / MIN_POWER_RANGE); // watts
        y = size.height - ((position['y']! - minRes) * size.height / range); // resistance
      } else {
        x = leftPadding + ((position['y']! - minRes) * (size.width - leftPadding) / range); // resistance
        y = size.height - (position['x']! * size.height / MIN_POWER_RANGE); // watts
      }
      canvas.drawCircle(Offset(x, y), 6, paint);
    }
  }

  void _drawCurrentPosition(Canvas canvas, Size size) {
    double minRes = 0;
    double maxRes = max(MIN_RESISTANCE_RANGE, homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE));
    double range = maxRes - minRes;
    double scaledResistance = currentResistance / tableDivisor;
    double x;
    double y;
    if (!swapAxes) {
      x = leftPadding + (currentWatts * (size.width - leftPadding) / MIN_POWER_RANGE);
      y = size.height - ((scaledResistance - minRes) * size.height / range);
    } else {
      x = leftPadding + ((scaledResistance - minRes) * (size.width - leftPadding) / range);
      y = size.height - (currentWatts * size.height / MIN_POWER_RANGE);
    }
    final paint = Paint()
      ..color = _getCadenceColor(currentCadence)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 6, paint);
  }

  Color _getCadenceColor(int cadence) {
    if (cadence < 62) return colors[0];
    if (cadence > 107) return colors[colors.length - 1];
    return colors[((cadence - 60) / 5).round()];
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
