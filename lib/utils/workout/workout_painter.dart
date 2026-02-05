import 'dart:math';
import 'package:flutter/material.dart';
import 'workout_parser.dart';
import 'workout_constants.dart';

class WorkoutPainter extends CustomPainter {
  static final Random _random = Random();
  final List<WorkoutSegment> segments;
  final double maxPower;
  final double totalDuration;
  final double ftpValue;
  final double currentProgress;
  final Map<int, double> actualPowerPoints;
  final double? currentPower;
  final int? currentHr;
  final int? currentCadence;
  final List<double>? powerPointsList;  // New parameter for interpolated points
  final List<double>? hrPointsList;
  final List<double>? cadencePointsList;
  final bool showLabels; // New parameter to control label visibility
  final double pulseValue; // 0.0 to 1.0 for pulse animation

  WorkoutPainter({
    required this.segments,
    required this.maxPower,
    required this.totalDuration,
    required this.ftpValue,
    required this.currentProgress,
    required this.actualPowerPoints,
    this.currentPower,
    this.currentHr,
    this.currentCadence,
    this.powerPointsList,  // Add this parameter
    this.hrPointsList,
    this.cadencePointsList,
    this.showLabels = true, // Default to showing labels
    this.pulseValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;

    double currentX = 0;
    // Scale height based on max power in watts
    final heightScale = size.height / (maxPower * ftpValue);
    final widthScale = size.width / totalDuration;

    // Draw segments
    for (var segment in segments) {
      final baseColor = _getSegmentColor(segment);
      final segmentWidth = segment.duration * widthScale;

      // Determine if this segment is active
      // currentProgress (0-1) * totalDuration = currentTime
      // currentX = segmentStartTime * widthScale
      // segmentStartTime = currentX / widthScale
      // or we can just compare pixels:
      final currentPixel = currentProgress * totalDuration * widthScale;
      final bool isActive =
          currentPixel >= currentX && currentPixel < currentX + segmentWidth;

      // Create gradient colors for 3D effect
      Color topColor = _lighten(baseColor, 0.2);
      Color bottomColor = _darken(baseColor, 0.1);

      if (isActive && currentPower != null) {
        // Apply pulse effect to active segment
        // Pulse brightness up slightly on 'beat'
        final brightnessBoost = pulseValue * 0.20; // +0% to +20% lightness
        topColor = _lighten(topColor, brightnessBoost);
        bottomColor = _lighten(bottomColor, brightnessBoost);
      }

      if (segment.isRamp) {
        // Draw ramp segment
        final path = Path();

        // For cooldowns, start at powerHigh and end at powerLow
        // For all other ramps, start at powerLow and end at powerHigh
        final startPower =
            segment.type == SegmentType.cooldown ? segment.powerHigh : segment.powerLow;
        final endPower =
            segment.type == SegmentType.cooldown ? segment.powerLow : segment.powerHigh;

        final startHeight = size.height - (startPower * ftpValue * heightScale);
        final endHeight = size.height - (endPower * ftpValue * heightScale);

        path.moveTo(currentX, size.height);
        path.lineTo(currentX, startHeight);
        path.lineTo(currentX + segmentWidth, endHeight);
        path.lineTo(currentX + segmentWidth, size.height);
        path.close();

        // Apply gradient shader
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ).createShader(path.getBounds());

        canvas.drawPath(path, paint);
      } else {
        // Draw steady state segment
        final segmentHeight = segment.powerLow * ftpValue * heightScale;
        final rect = Rect.fromLTWH(
          currentX,
          size.height - segmentHeight,
          segmentWidth,
          segmentHeight,
        );

        // Apply gradient shader
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ).createShader(rect);

        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: const Radius.circular(8.0),
            topRight: const Radius.circular(8.0),
          ),
          paint,
        );
      }

      // Draw segment border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color.fromARGB(65, 0, 0, 0)
            .withValues(alpha: WorkoutOpacity.segmentBorder)
        ..strokeWidth = WorkoutStroke.border;

      canvas.drawRect(
        Rect.fromLTWH(currentX, 0, segmentWidth, size.height),
        borderPaint,
      );

      // Draw power labels during active workout (when currentPower is provided)
      if (currentPower != null && showLabels) {
        _drawPowerLabels(
            canvas, currentX, segmentWidth, size.height, segment, heightScale);
      }

      // Draw cadence indicator if present
      if ((segment.cadence != null || segment.cadenceLow != null) && showLabels) {
        _drawCadenceIndicator(
            canvas, currentX, segmentWidth, size.height, segment);
      }

      currentX += segmentWidth;
    }

    // Draw power grid lines and labels
    _drawPowerGrid(canvas, size, heightScale);
    
    // Draw time grid lines and labels
    _drawTimeGrid(canvas, size, widthScale);

    // Draw tracer lines (Power, HR, Cadence)
    _drawTracerLines(canvas, size, heightScale, widthScale);
  }

  void _drawValueLabel(Canvas canvas, Offset center, String text, Color color) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.text = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 10.0,
      ),
    );
    
    // Calculate layout
    textPainter.layout();
    
    // Draw background rounded rect (pill shape)
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
      
    final padding = 4.0;
    final rect = Rect.fromCenter(
      center: center, 
      width: textPainter.width + (padding * 2), 
      height: textPainter.height + (padding * 1), // slightly less vertical padding
    );
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10.0)), 
      bgPaint
    );
    
    // Center the text on the point
    textPainter.paint(
        canvas, 
        Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2)
    );
  }

  void _drawTracerLines(Canvas canvas, Size size, double heightScale, double widthScale) {
    // 1. Draw Power (Bright Blue)
    if (powerPointsList != null && powerPointsList!.isNotEmpty) {
      final powerPaint = Paint()
        ..color = Colors.lightBlueAccent // Bright Blue
        ..strokeWidth = WorkoutStroke.actualPowerLine
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool isFirstPoint = true;

      for (int i = 0; i < powerPointsList!.length; i++) {
        final watts = powerPointsList![i];
        final x = i * widthScale;
        final y = size.height - (watts * heightScale);

        if (isFirstPoint) {
          path.moveTo(x, y);
          isFirstPoint = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, powerPaint);

      // Dot or Text
      if (currentPower != null) {
        final x = currentProgress * size.width;
        final y = size.height - (currentPower! * heightScale);
        final center = Offset(x, y);

        if (showLabels) {
          _drawValueLabel(canvas, center, '${currentPower!.round()}', Colors.lightBlueAccent);
        } else {
          final dotPaint = Paint()
            ..color = Colors.lightBlueAccent
            ..style = PaintingStyle.fill;
          canvas.drawCircle(center, WorkoutSizes.actualPowerDotRadius * 1.5, dotPaint);
        }
      }
    }

    // 2. Draw Cadence (Green, Scale 20-130)
    if (cadencePointsList != null && cadencePointsList!.isNotEmpty) {
      final cadencePaint = Paint()
        ..color = Colors.green
        ..strokeWidth = WorkoutStroke.actualPowerLine
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool isFirstPoint = true;
      
      // Map 20-130 to full height? Or just map it relative to chart?
      // Usually tracers are overlaid on the full chart area.
      // 20 -> Bottom (size.height), 130 -> Top (0)
      double mapCadenceToY(double val) {
         // Scale 20-130
         double minVal = 20;
         double maxVal = 130;
         double normalized = (val - minVal) / (maxVal - minVal);
         // Clamp? Usually good idea, but user said Scale is 20-130.
         // Let's not clamp tightly but allow going off chart? 
         // Better clamp visual to chart bounds so it doesn't draw over widgets.
         // But for now, simple linear map.
         return size.height - (normalized * size.height);
      }

      for (int i = 0; i < cadencePointsList!.length; i++) {
        final val = cadencePointsList![i];
        if (val == 0) continue; // Skip 0 points? User said HR if 0 don't display. Assuming consistent behavior.

        final x = i * widthScale;
        final y = mapCadenceToY(val);

        if (isFirstPoint) {
          path.moveTo(x, y);
          isFirstPoint = false; 
        } else {
             path.lineTo(x, y);
        }
      }
      // Re-doing loop to handle gaps better if needed.
      // Actually simpler: just iterate and draw.
      path.reset();
      isFirstPoint = true;
      for(int i=0; i<cadencePointsList!.length; i++) {
          final val = cadencePointsList![i];
          
          final x = i * widthScale;
          final y = mapCadenceToY(val);
          
          if (isFirstPoint) {
             path.moveTo(x, y);
             isFirstPoint = false;
          } else {
             path.lineTo(x, y);
          }
      }
      
      canvas.drawPath(path, cadencePaint);

      // Dot or Text
      if (currentCadence != null && currentCadence! > 0) {
         final x = currentProgress * size.width;
         final y = mapCadenceToY(currentCadence!.toDouble());
         final center = Offset(x, y);

         if (showLabels) {
           _drawValueLabel(canvas, center, '$currentCadence', Colors.green);
         } else {
           final dotPaint = Paint()
            ..color = Colors.green
            ..style = PaintingStyle.fill;
           canvas.drawCircle(center, WorkoutSizes.actualPowerDotRadius * 1.5, dotPaint);
         }
      }
    }

    // 3. Draw HR (Red, Scale 30-230)
    if (hrPointsList != null && hrPointsList!.isNotEmpty) {
      final hrPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = WorkoutStroke.actualPowerLine
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool hasPoints = false;
      
      double mapHrToY(double val) {
         double minVal = 30;
         double maxVal = 230;
         double normalized = (val - minVal) / (maxVal - minVal);
         return size.height - (normalized * size.height);
      }
      
      for (int i = 0; i < hrPointsList!.length; i++) {
        final val = hrPointsList![i];
        if (val <= 0) {
            hasPoints = false; // Break continuity
            continue; 
        }

        final x = i * widthScale;
        final y = mapHrToY(val);

        if (!hasPoints) {
          path.moveTo(x, y);
          hasPoints = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, hrPaint);

      // Dot or Text
      if (currentHr != null && currentHr! > 0) {
         final x = currentProgress * size.width;
         final y = mapHrToY(currentHr!.toDouble());
         final center = Offset(x, y);

         if (showLabels) {
           _drawValueLabel(canvas, center, '$currentHr', Colors.red);
         } else {
           final dotPaint = Paint()
            ..color = Colors.red
            ..style = PaintingStyle.fill;
           canvas.drawCircle(center, WorkoutSizes.actualPowerDotRadius * 1.5, dotPaint);
         }
      }
    }
  }

  // Renamed/Removed old method signature
  // void _drawActualPowerTrail(...)

  void _drawPowerGrid(Canvas canvas, Size size, double heightScale) {
    // Add left padding for power labels
    const double leftPadding = 35.0;  // Space for power labels
    
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.withValues(alpha: WorkoutOpacity.gridLines)
      ..strokeWidth = WorkoutStroke.border;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    // Draw horizontal power lines at intervals
    for (var power = 0.0; power <= maxPower * ftpValue; power += WorkoutGrid.powerLineInterval) {
      final y = size.height - (power * heightScale);
      
      // Draw grid line starting after the label space
      canvas.drawLine(
        Offset(showLabels ? leftPadding : 0, y),
        Offset(size.width, y),
        gridPaint,
      );

      // Draw power labels in the reserved space
      if (showLabels) {
        textPainter.text = TextSpan(
          text: '${power.round()}w',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: WorkoutFontSizes.small,
          ),
        );
        textPainter.layout();
        textPainter.paint(
            canvas,
            Offset(leftPadding - textPainter.width - 4,
                y - textPainter.height / 2));
      }
    }
  }

  void _drawTimeGrid(Canvas canvas, Size size, double widthScale) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.withValues(alpha: WorkoutOpacity.gridLines)
      ..strokeWidth = WorkoutStroke.border;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw vertical time lines at intervals
    for (var time = 0.0; time <= totalDuration; time += WorkoutGrid.timeLineInterval) {
      final x = time * widthScale;
      
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );

      // Draw time labels
      if (showLabels) {
        textPainter.text = TextSpan(
          text: '${(time / 60).round()}min',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: WorkoutFontSizes.small,
          ),
        );
        textPainter.layout();
        textPainter.paint(
            canvas, Offset(x - textPainter.width / 2, size.height + 5));
      }
    }
  }

  void _drawCadenceIndicator(Canvas canvas, double x, double width, double height, WorkoutSegment segment) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.purple
      ..strokeWidth = WorkoutStroke.cadenceIndicator;

    final path = Path();
    
    path.moveTo(x + width / 2, height - WorkoutSizes.cadenceIndicatorHeight);
    path.lineTo(x + width / 2, height);
    
    canvas.drawPath(path, paint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final cadenceText = segment.cadence ?? 
                       '${segment.cadenceLow}-${segment.cadenceHigh}';
    
    textPainter.text = TextSpan(
      text: '$cadenceText rpm',
      style: TextStyle(
        color: Colors.purple,
        fontSize: WorkoutFontSizes.small,
        fontWeight: FontWeight.bold,
      ),
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        x + width / 2 - textPainter.width / 2,
        height - WorkoutSizes.cadenceIndicatorHeight - textPainter.height - 2,
      ),
    );
  }

  Color _getSegmentColor(WorkoutSegment segment) {
    // Always use consistent colors for warmup and cooldown
    if (segment.type == SegmentType.warmup) {
      return Colors.green.withValues(alpha: WorkoutOpacity.segmentColor);
    }
    if (segment.type == SegmentType.cooldown) {
      return Colors.blue.withValues(alpha: WorkoutOpacity.segmentColor);
    }

    // For other segments, determine color based on power as % of FTP
    double powerPercentage = segment.powerLow;
    if (segment.isRamp) {
      // For ramps, use the average power
      powerPercentage = (segment.powerLow + segment.powerHigh) / 2;
    }

    // Color based on power zones
    if (powerPercentage <= WorkoutZones.recovery) {
      return Colors.blue.withValues(alpha: WorkoutOpacity.segmentColor);
    } else if (powerPercentage <= WorkoutZones.endurance) {
      return Colors.green.withValues(alpha: WorkoutOpacity.segmentColor);
    } else if (powerPercentage <= WorkoutZones.tempo) {
      return Colors.yellow.withValues(alpha: WorkoutOpacity.segmentColor);
    } else if (powerPercentage <= WorkoutZones.threshold) {
      return Colors.orange.withValues(alpha: WorkoutOpacity.segmentColor);
    } else if (powerPercentage <= WorkoutZones.vo2max) {
      return Colors.deepOrange.withValues(alpha: WorkoutOpacity.segmentColor);
    } else if (powerPercentage <= WorkoutZones.anaerobic) {
      return Colors.red.withValues(alpha: WorkoutOpacity.segmentColor);
    } else {
      return Colors.purple.withValues(alpha: WorkoutOpacity.segmentColor);
    }
  }

  void _drawPowerLabels(Canvas canvas, double x, double width, double height, WorkoutSegment segment, double heightScale) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final color = _getSegmentColor(segment).withValues(alpha: 1.0); // Full opacity for text
    final style = TextStyle(
      color: color,
      fontSize: WorkoutFontSizes.small,
      fontWeight: FontWeight.bold,
    );

    if (segment.isRamp) {
      // For ramp segments, show both start and end power
      final startPower = segment.type == SegmentType.cooldown ? segment.powerHigh : segment.powerLow;
      final endPower = segment.type == SegmentType.cooldown ? segment.powerLow : segment.powerHigh;
      
      // Calculate positions above the power levels
      final startY = height - ((startPower * ftpValue + 20) * heightScale);
      final endY = height - ((endPower * ftpValue + 12) * heightScale);
      
      // Calculate slope angle
      final slopeAngle = atan2(endY - startY, width);
      
      // Start power label
      textPainter.text = TextSpan(
        text: '${(startPower * ftpValue).round()}w',
        style: style,
      );
      textPainter.layout();
      
      canvas.save();
      canvas.translate(x + 4, startY);
      canvas.rotate(slopeAngle);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();

      // End power label
      textPainter.text = TextSpan(
        text: '${(endPower * ftpValue).round()}w',
        style: style,
      );
      textPainter.layout();
      
      canvas.save();
      canvas.translate(x + width - textPainter.width - 4, endY);
      canvas.rotate(slopeAngle);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      // For steady state segments, show single power value 20 watts above
      final yPos = height - ((segment.powerLow * ftpValue + 20) * heightScale);
      
      textPainter.text = TextSpan(
        text: '${(segment.powerLow * ftpValue).round()}w',
        style: style,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + (width - textPainter.width) / 2, yPos),
      );
    }
  }

  Color _lighten(Color color, [double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }

  Color _darken(Color color, [double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
