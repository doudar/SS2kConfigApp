import 'dart:math';
import 'package:flutter/material.dart';
import 'workout/workout_constants.dart';
import 'constants.dart';

/// Optional font used by deterministic screenshot tests. Production renders
/// continue to use the platform's default font.
@visibleForTesting
String? debugPowerTablePainterFontFamily;

class PowerTablePainter extends CustomPainter {
  final List<List<double?>> powerTableData;
  final List<int> cadences;
  final List<Color> colors;
  final double maxResistance;
  final double? homingMin; // currently unused but preserved
  final double? homingMax;
  // false: Resistance(Y)/Watts(X), true: Watts(Y)/Resistance(X)
  final bool swapAxes;

  PowerTablePainter({
    required this.powerTableData,
    required this.cadences,
    required this.colors,
    required this.maxResistance,
    this.homingMin,
    this.homingMax,
    required this.swapAxes,
  });

  final leftPadding = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    _drawAxisLabels(canvas, size);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = WorkoutStroke.actualPowerLine;

    _drawGrid(canvas, size);

    for (int i = 0; i < powerTableData.length; i++) {
      paint.color = colors[i % colors.length];
      _drawPowerCurve(canvas, size, powerTableData[i], paint);
    }
  }

  void _drawAxisLabels(Canvas canvas, Size size) {
    final labelStyle = TextStyle(
      color: Colors.blueGrey.withValues(alpha: 0.2),
      fontSize: 28,
      fontWeight: FontWeight.w900,
      letterSpacing: 2.0,
      fontFamily: debugPowerTablePainterFontFamily,
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
        textPainter.paint(
          canvas,
          Offset(-textPainter.width / 2, -textPainter.height / 2),
        );
      } else {
        // X-axis (Horizontal): Center horizontally, near top
        double x =
            leftPadding +
            (size.width - leftPadding) / 2 -
            textPainter.width / 2;
        double y = 0;
        textPainter.paint(canvas, Offset(x, y));
      }
      canvas.restore();
    }

    if (!swapAxes) {
      drawLabel("RESISTANCE", true); // Y
      drawLabel("P O W E R", false); // X
    } else {
      drawLabel("P O W E R", true); // Y
      drawLabel("RESISTANCE", false); // X
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.withValues(alpha: WorkoutOpacity.gridLines)
      ..strokeWidth = WorkoutStroke.border;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    double minRes = 0;
    double maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE),
    );
    double range = maxRes - minRes;

    if (!swapAxes) {
      // Resistance on Y axis
      for (
        double resistance = minRes;
        resistance <= maxRes;
        resistance += range / 5
      ) {
        final y = size.height - ((resistance - minRes) * size.height / range);
        canvas.drawLine(
          Offset(leftPadding, y),
          Offset(size.width, y),
          gridPaint,
        );
        // Round resistance to nearest whole number for labels
        textPainter.text = TextSpan(
          text: resistance.round().toString(),
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: WorkoutFontSizes.small,
            fontFamily: debugPowerTablePainterFontFamily,
          ),
        );
        textPainter.layout();
        final double labelX = leftPadding + 4;
        textPainter.paint(canvas, Offset(labelX, y - textPainter.height / 2));
      }
      for (double watts = 0; watts <= MIN_POWER_RANGE; watts += 100) {
        final x =
            leftPadding +
            (watts * (size.width - leftPadding) / MIN_POWER_RANGE);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        if (watts > 0) {
          textPainter.text = TextSpan(
            text: '${watts.toInt()}w',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: WorkoutFontSizes.small,
              fontFamily: debugPowerTablePainterFontFamily,
            ),
          );
          textPainter.layout();
          double labelX = x - textPainter.width / 2;
          labelX = max(0.0, min(size.width - textPainter.width, labelX));
          textPainter.paint(canvas, Offset(labelX, -5));
        }
      }
    } else {
      // Watts on Y axis
      for (
        double watts = 0;
        watts <= MIN_POWER_RANGE;
        watts += MIN_POWER_RANGE / 5
      ) {
        final y = size.height - (watts * size.height / MIN_POWER_RANGE);
        canvas.drawLine(
          Offset(leftPadding, y),
          Offset(size.width, y),
          gridPaint,
        );
        textPainter.text = TextSpan(
          text: '${watts.toInt()}w',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: WorkoutFontSizes.small,
            fontFamily: debugPowerTablePainterFontFamily,
          ),
        );
        textPainter.layout();
        final double labelX = leftPadding + 4;
        textPainter.paint(canvas, Offset(labelX, y - textPainter.height / 2));
      }
      for (
        double resistance = minRes;
        resistance <= maxRes;
        resistance += range / 5
      ) {
        final x =
            leftPadding +
            ((resistance - minRes) * (size.width - leftPadding) / range);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        if (resistance > minRes) {
          textPainter.text = TextSpan(
            text: resistance.round().toString(),
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: WorkoutFontSizes.small,
              fontFamily: debugPowerTablePainterFontFamily,
            ),
          );
          textPainter.layout();
          double labelX = x - textPainter.width / 2;
          labelX = max(0.0, min(size.width - textPainter.width, labelX));
          textPainter.paint(canvas, Offset(labelX, -5));
        }
      }
    }
  }

  void _drawPowerCurve(
    Canvas canvas,
    Size size,
    List<double?> data,
    Paint paint,
  ) {
    final path = Path();
    bool isFirstPoint = true;
    Offset? lastValidPoint;

    double minRes = 0;
    double maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE),
    );
    double range = maxRes - minRes;

    for (int i = 0; i < data.length && i * 30 <= MIN_POWER_RANGE; i++) {
      if (data[i] != null) {
        double powerValue = i * 30;
        double resistanceValue = data[i]!;
        double x;
        double y;
        if (!swapAxes) {
          x =
              leftPadding +
              (powerValue * (size.width - leftPadding) / MIN_POWER_RANGE);
          y = size.height - ((resistanceValue - minRes) * size.height / range);
        } else {
          x =
              leftPadding +
              ((resistanceValue - minRes) * (size.width - leftPadding) / range);
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

  @override
  bool shouldRepaint(covariant PowerTablePainter oldDelegate) {
    return !identical(powerTableData, oldDelegate.powerTableData) ||
        maxResistance != oldDelegate.maxResistance ||
        homingMin != oldDelegate.homingMin ||
        homingMax != oldDelegate.homingMax ||
        swapAxes != oldDelegate.swapAxes;
  }
}

/// Lightweight live layer for the current position, trail, and pulsing axes.
///
/// The animation is supplied directly to [CustomPainter], so a tick schedules
/// only a repaint of this layer. It does not rebuild widgets or repaint the
/// cached grid and power curves beneath it.
class PowerTableOverlayPainter extends CustomPainter {
  PowerTableOverlayPainter({
    required Listenable repaint,
    required this.animation,
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
    this.drawAxisEffects = true,
    this.drawPosition = true,
  }) : super(repaint: repaint);

  final Animation<double> animation;
  final List<Color> colors;
  final double maxResistance;
  final double? homingMin;
  final double? homingMax;
  final double Function() currentWatts;
  final double Function() currentResistance;
  final int Function() currentCadence;
  final List<Map<String, double>> positionHistory;
  final double tableDivisor;
  final bool swapAxes;
  final bool drawAxisEffects;
  final bool drawPosition;

  static const double leftPadding = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    final watts = currentWatts();
    final resistance = currentResistance();
    final cadence = currentCadence();
    if (drawAxisEffects) {
      _drawAxisEffects(canvas, size, watts, resistance);
    }
    if (drawPosition) {
      _drawPositionHistory(canvas, size, cadence);
      if (watts > 0 && watts <= MIN_POWER_RANGE) {
        _drawCurrentPosition(canvas, size, watts, resistance, cadence);
      }
    }
  }

  void _drawAxisEffects(
    Canvas canvas,
    Size size,
    double watts,
    double resistance,
  ) {
    const minRes = 0.0;
    final maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE),
    );
    final range = maxRes - minRes;
    final scaledResistance = resistance / tableDivisor;

    final xValue = swapAxes ? scaledResistance - minRes : watts;
    final yValue = swapAxes ? watts : scaledResistance - minRes;
    final xMax = swapAxes ? range : MIN_POWER_RANGE;
    final yMax = swapAxes ? MIN_POWER_RANGE : range;
    final yRatio = yMax == 0 ? 0.0 : (yValue / yMax).clamp(0.0, 1.0);
    final xRatio = xMax == 0 ? 0.0 : (xValue / xMax).clamp(0.0, 1.0);

    const barThickness = 20.0;
    const flameColors = <Color>[
      Colors.blueAccent,
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.yellowAccent,
      Colors.orangeAccent,
      Colors.deepOrangeAccent,
      Colors.redAccent,
    ];

    if (yRatio > 0) {
      final barHeight = size.height * yRatio;
      _paintAnimatedBar(
        canvas,
        Rect.fromLTRB(
          2,
          size.height - barHeight,
          2 + barThickness,
          size.height,
        ),
        flameColors,
        isVertical: true,
        ratio: yRatio,
      );
    }

    if (xRatio > 0) {
      final barWidth = (size.width - leftPadding) * xRatio;
      _paintAnimatedBar(
        canvas,
        Rect.fromLTRB(
          leftPadding,
          -15,
          leftPadding + barWidth,
          -15 + barThickness,
        ),
        flameColors,
        isVertical: false,
        ratio: xRatio,
      );
    }
  }

  void _paintAnimatedBar(
    Canvas canvas,
    Rect rect,
    List<Color> colors, {
    required bool isVertical,
    required double ratio,
  }) {
    final totalExtent = isVertical ? rect.height / ratio : rect.width / ratio;
    final gradientRect = isVertical
        ? Rect.fromLTRB(
            rect.left,
            rect.bottom - totalExtent,
            rect.right,
            rect.bottom,
          )
        : Rect.fromLTRB(
            rect.left,
            rect.top,
            rect.left + totalExtent,
            rect.bottom,
          );
    final pulse = 0.1 * sin(animation.value * 2 * pi);
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: isVertical ? Alignment.bottomCenter : Alignment.centerLeft,
        end: isVertical ? Alignment.topCenter : Alignment.centerRight,
        colors: colors
            .map(
              (color) => color.withValues(alpha: (0.8 + pulse).clamp(0.0, 1.0)),
            )
            .toList(),
      ).createShader(gradientRect);
    canvas.drawRect(rect, barPaint);

    final peakPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final peak = isVertical
        ? Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 2)
        : Rect.fromLTRB(rect.right - 2, rect.top, rect.right, rect.bottom);
    canvas.drawRect(peak, peakPaint);
  }

  void _drawPositionHistory(Canvas canvas, Size size, int cadence) {
    for (int i = 0; i < positionHistory.length; i++) {
      final position = positionHistory[i];
      final opacity = (i + 1) / positionHistory.length;
      final paint = Paint()
        ..color = _getCadenceColor(cadence).withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.fill;

      double minRes = 0;
      double maxRes = max(
        MIN_RESISTANCE_RANGE,
        homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE),
      );
      double range = maxRes - minRes;
      double x;
      double y;
      if (!swapAxes) {
        x =
            leftPadding +
            (position['x']! *
                (size.width - leftPadding) /
                MIN_POWER_RANGE); // watts
        y =
            size.height -
            ((position['y']! - minRes) * size.height / range); // resistance
      } else {
        x =
            leftPadding +
            ((position['y']! - minRes) *
                (size.width - leftPadding) /
                range); // resistance
        y =
            size.height -
            (position['x']! * size.height / MIN_POWER_RANGE); // watts
      }
      canvas.drawCircle(Offset(x, y), 6, paint);
    }
  }

  void _drawCurrentPosition(
    Canvas canvas,
    Size size,
    double watts,
    double resistance,
    int cadence,
  ) {
    double minRes = 0;
    double maxRes = max(
      MIN_RESISTANCE_RANGE,
      homingMax ?? max(maxResistance, MIN_RESISTANCE_RANGE),
    );
    double range = maxRes - minRes;
    double scaledResistance = resistance / tableDivisor;
    double x;
    double y;
    if (!swapAxes) {
      x = leftPadding + (watts * (size.width - leftPadding) / MIN_POWER_RANGE);
      y = size.height - ((scaledResistance - minRes) * size.height / range);
    } else {
      x =
          leftPadding +
          ((scaledResistance - minRes) * (size.width - leftPadding) / range);
      y = size.height - (watts * size.height / MIN_POWER_RANGE);
    }
    final paint = Paint()
      ..color = _getCadenceColor(cadence)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 6, paint);
  }

  Color _getCadenceColor(int cadence) {
    if (cadence < 62) return colors[0];
    if (cadence > 107) return colors[colors.length - 1];
    return colors[((cadence - 60) / 5).round()];
  }

  @override
  bool shouldRepaint(covariant PowerTableOverlayPainter oldDelegate) {
    return maxResistance != oldDelegate.maxResistance ||
        homingMin != oldDelegate.homingMin ||
        homingMax != oldDelegate.homingMax ||
        tableDivisor != oldDelegate.tableDivisor ||
        swapAxes != oldDelegate.swapAxes ||
        drawAxisEffects != oldDelegate.drawAxisEffects ||
        drawPosition != oldDelegate.drawPosition ||
        !identical(positionHistory, oldDelegate.positionHistory);
  }
}
