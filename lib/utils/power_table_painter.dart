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
  final double animationValue;

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
    this.animationValue = 0.0,
  });

  final leftPadding = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    _drawAxisEffects(canvas, size);
    _drawAxisLabels(canvas, size);

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

  void _drawAxisEffects(Canvas canvas, Size size) {
    double minRes = 0;
    double maxRes = max(MIN_RESISTANCE_RANGE, homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE));
    double range = maxRes - minRes;

    double xValue = 0.0;
    double yValue = 0.0;
    double xMax = 0.0;
    double yMax = 0.0;

    double scaledResistance = currentResistance / tableDivisor;

    if (!swapAxes) {
      // Y is Resistance, X is Watts
      yValue = scaledResistance - minRes;
      yMax = range;
      xValue = currentWatts;
      xMax = MIN_POWER_RANGE;
    } else {
      // Y is Watts, X is Resistance
      yValue = currentWatts;
      yMax = MIN_POWER_RANGE;
      xValue = scaledResistance - minRes;
      xMax = range;
    }

    // Normalize 0..1
    double yRatio = (yMax == 0) ? 0 : (yValue / yMax).clamp(0.0, 1.0);
    double xRatio = (xMax == 0) ? 0 : (xValue / xMax).clamp(0.0, 1.0);

    // Visual styles
    final double barThickness = 20.0;
    final List<Color> flameColors = [
      Colors.blueAccent,
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.yellowAccent,
      Colors.orangeAccent,
      Colors.deepOrangeAccent,
      Colors.redAccent,
    ];

    // --- Vertical Axis (Y) ---
    // Draw from bottom up
    if (yRatio > 0) {
      double barHeight = size.height * yRatio;
      Rect yFillRect = Rect.fromLTRB(
        2, // x
        size.height - barHeight, // top
        2 + barThickness, // right
        size.height // bottom
      );
      _paintAnimatedBar(canvas, yFillRect, flameColors, isVertical: true, ratio: yRatio);
    }

    // --- Horizontal Axis (X) ---
    // Draw from left to right
    if (xRatio > 0) {
      double barWidth = (size.width - leftPadding) * xRatio;
      Rect xFillRect = Rect.fromLTRB(
        leftPadding, // left
        -15, // top (above labels)
        leftPadding + barWidth, // right
        -15 + barThickness // bottom
      );
      _paintAnimatedBar(canvas, xFillRect, flameColors, isVertical: false, ratio: xRatio);
    }
  }

  void _paintAnimatedBar(Canvas canvas, Rect rect, List<Color> colors,
      {required bool isVertical, required double ratio}) {
    final Paint barPaint = Paint()..style = PaintingStyle.fill;

    double totalExtent = isVertical ? (rect.height / ratio) : (rect.width / ratio);
    
    // Create a Rect that represents the full range of the axis for gradient mapping
    Rect gradientRect;
    Alignment beginAlignment; // Start of axis (Low value)
    Alignment endAlignment;   // End of axis (High value)

    if (isVertical) {
       // Vertical: Axis starts at Bottom (High Y) and goes to Top (Low Y)
       gradientRect = Rect.fromLTRB(rect.left, rect.bottom - totalExtent, rect.right, rect.bottom);
       beginAlignment = Alignment.bottomCenter;
       endAlignment = Alignment.topCenter;
    } else {
       // Horizontal: Axis starts at Left and goes to Right
       gradientRect = Rect.fromLTRB(rect.left, rect.top, rect.left + totalExtent, rect.bottom);
       beginAlignment = Alignment.centerLeft;
       endAlignment = Alignment.centerRight;
    }

    // Pulse effect
    double pulse = 0.1 * sin(animationValue * 2 * pi); // -0.1 to 0.1
    
    barPaint.shader = LinearGradient(
      begin: beginAlignment,
      end: endAlignment,
      colors: colors.map((c) => c.withOpacity((0.8 + pulse).clamp(0.0, 1.0))).toList(),
    ).createShader(gradientRect);

    canvas.drawRect(rect, barPaint);
    
    // Draw a "Peak" indicator
    Paint peakPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2);
      
    if (isVertical) {
       canvas.drawRect(Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 2), peakPaint);
    } else {
       canvas.drawRect(Rect.fromLTRB(rect.right - 2, rect.top, rect.right, rect.bottom), peakPaint);
    }
  }

  void _drawAxisLabels(Canvas canvas, Size size) {
    final labelStyle = TextStyle(
      color: Colors.blueGrey.withOpacity(0.2),
      fontSize: 28,
      fontWeight: FontWeight.w900,
      letterSpacing: 2.0,
    );

    void drawLabel(String text, bool isVertical) {
      final textSpan = TextSpan(text: text, style: labelStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.save();
      if (isVertical) {
        // Y-axis (Vertical): Center vertically, stick to left edge
        canvas.translate(10, size.height / 2);
        canvas.rotate(-pi / 2);
        textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      } else {
        // X-axis (Horizontal): Center horizontally, near top
        double x = leftPadding + (size.width - leftPadding) / 2 - textPainter.width / 2;
        double y = 0;
        textPainter.paint(canvas, Offset(x, y));
      }
      canvas.restore();
    }

    if (!swapAxes) {
      drawLabel("RESISTANCE", true); // Y
      drawLabel("P O W E R", false);    // X
    } else {
      drawLabel("P O W E R", true);     // Y
      drawLabel("RESISTANCE", false); // X
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
        final double labelX = leftPadding + 4;
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
        final double labelX = leftPadding + 4;
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
