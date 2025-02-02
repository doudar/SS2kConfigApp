import 'dart:math';
import 'package:flutter/material.dart';
import 'workout/workout_constants.dart';
import 'constants.dart';

class PowerTablePainter extends CustomPainter {
  final List<List<double?>> powerTableData;
  final List<int> cadences;
  final List<Color> colors;
  final double maxResistance;
  final double minResistance;
  final double? homingMin;
  final double? homingMax;
  final double currentWatts;
  final double currentResistance;
  final int currentCadence;
  final List<Map<String, double>> positionHistory;

  PowerTablePainter({
    required this.powerTableData,
    required this.cadences,
    required this.colors,
    required this.maxResistance,
    required this.minResistance,
    this.homingMin,
    this.homingMax,
    required this.currentWatts,
    required this.currentResistance,
    required this.currentCadence,
    required this.positionHistory,
  });

  @override

  final leftPadding = 20.0;
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = WorkoutStroke.actualPowerLine;

    // Draw grid and labels first
    _drawGrid(canvas, size);

    // Draw power curves for each cadence
    for (int i = 0; i < powerTableData.length; i++) {
      paint.color = colors[i % colors.length];
      _drawPowerCurve(canvas, size, powerTableData[i], paint);
    }

    // Draw position history (trail)
    _drawPositionHistory(canvas, size);

    // Draw current position dot
    if (currentWatts > 0 && currentWatts <= 1000) {
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

    // Use the calculated min resistance value
    double minRes = minResistance;
    double maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE)
    );
    double range = maxRes - minRes;

    // Draw horizontal resistance lines
    for (double resistance = minRes; resistance <= maxRes; resistance += range / 5) {
      final y = size.height - ((resistance - minRes) * size.height / range);
      
      // Draw grid line
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width, y),
        gridPaint,
      );

      // Draw resistance label
      textPainter.text = TextSpan(
        text: resistance.toStringAsFixed(1),
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: WorkoutFontSizes.small,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(leftPadding - textPainter.width - 4, y - textPainter.height / 2),
      );
    }

    // Draw vertical watts lines
    for (double watts = 0; watts <= MIN_POWER_RANGE; watts += 100) {
      final x = leftPadding + (watts * (size.width - leftPadding) / MIN_POWER_RANGE);
      
      // Draw grid line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );

      // Draw watts label (skip 0W to avoid overlap with resistance label)
      if (watts > 0) {
        textPainter.text = TextSpan(
          text: '${watts.toInt()}w',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: WorkoutFontSizes.small,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, -5),
        );
      }
    }
  }

  void _drawPowerCurve(Canvas canvas, Size size, List<double?> data, Paint paint) {
    
    final path = Path();
    bool isFirstPoint = true;
    Offset? lastValidPoint;

    double minRes = minResistance;
    double maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE)
    );
    double range = maxRes - minRes;

    for (int i = 0; i < data.length && i * 30 <= MIN_POWER_RANGE; i++) {
      if (data[i] != null) {
        final x = leftPadding + (i * 30 * (size.width - leftPadding) / MIN_POWER_RANGE);
        final y = size.height - ((data[i]! - minRes) * size.height / range);

        // Check if point is within graph boundaries
        if (x >= leftPadding && x <= size.width && y >= 0 && y <= size.height) {
          if (isFirstPoint) {
            path.moveTo(x, y);
            isFirstPoint = false;
          } else {
            // If we have a last valid point and it's not the previous point,
            // we need to move to it before drawing the line
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

      final x = leftPadding + (position['x']! * (size.width - leftPadding) / MIN_POWER_RANGE);
      double minRes = minResistance;
      double maxRes = max(
        MIN_RESISTANCE_RANGE,
        homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE)
      );
      double range = maxRes - minRes;
      final y = size.height - ((position['y']! - minRes) * size.height / range);

      canvas.drawCircle(
        Offset(x, y),
        6,
        paint,
      );
    }
  }

  void _drawCurrentPosition(Canvas canvas, Size size) {
    
    final x = leftPadding + (currentWatts * (size.width - leftPadding) / MIN_POWER_RANGE);
    double minRes = minResistance;
    double maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE)
    );
    double range = maxRes - minRes;
    final y = size.height - ((currentResistance/100 - minRes) * size.height / range);

    final paint = Paint()
      ..color = _getCadenceColor(currentCadence)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(x, y),
      6,
      paint,
    );
  }

  Color _getCadenceColor(int cadence) {
    if (cadence < 60) {
      return Colors.red;
    } else if (cadence < 80) {
      double t = (cadence - 60) / 20.0;
      return Color.lerp(Colors.red, Colors.orange, t)!;
    } else if (cadence <= 100) {
      double t = (cadence - 80) / 20.0;
      return Color.lerp(Colors.orange, Colors.green, t)!;
    } else {
      double t = (cadence - 100) / 20.0;
      return Color.lerp(Colors.green, Colors.red, t.clamp(0.0, 1.0))!;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
