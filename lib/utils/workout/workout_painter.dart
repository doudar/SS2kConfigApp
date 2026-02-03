import 'dart:math';
import 'package:flutter/material.dart';
import 'workout_parser.dart';
import 'workout_constants.dart';

class WorkoutPainter extends CustomPainter {
  final List<WorkoutSegment> segments;
  final double maxPower;
  final double totalDuration;
  final double ftpValue;
  final double currentProgress;
  final Map<int, double> actualPowerPoints;
  final double? currentPower;
  final List<double>? powerPointsList;  // New parameter for interpolated points
  final bool showLabels; // New parameter to control label visibility

  WorkoutPainter({
    required this.segments,
    required this.maxPower,
    required this.totalDuration,
    required this.ftpValue,
    required this.currentProgress,
    required this.actualPowerPoints,
    this.currentPower,
    this.powerPointsList,  // Add this parameter
    this.showLabels = true, // Default to showing labels
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill;

    double currentX = 0;
    // Scale height based on max power in watts
    final heightScale = size.height / (maxPower * ftpValue);
    final widthScale = size.width / totalDuration;

    // Draw segments
    for (var segment in segments) {
      paint.color = _getSegmentColor(segment);
      final segmentWidth = segment.duration * widthScale;
      
      if (segment.isRamp) {
        // Draw ramp segment
        final path = Path();
        
        // For cooldowns, start at powerHigh and end at powerLow
        // For all other ramps, start at powerLow and end at powerHigh
        final startPower = segment.type == SegmentType.cooldown ? segment.powerHigh : segment.powerLow;
        final endPower = segment.type == SegmentType.cooldown ? segment.powerLow : segment.powerHigh;
        
        final startHeight = size.height - (startPower * ftpValue * heightScale);
        final endHeight = size.height - (endPower * ftpValue * heightScale);
        
        path.moveTo(currentX, size.height);
        path.lineTo(currentX, startHeight);
        path.lineTo(currentX + segmentWidth, endHeight);
        path.lineTo(currentX + segmentWidth, size.height);
        path.close();
        
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
        canvas.drawRect(rect, paint);
      }

      // Draw segment border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color.fromARGB(65, 0, 0, 0).withValues(alpha: WorkoutOpacity.segmentBorder)
        ..strokeWidth = WorkoutStroke.border;
      
      canvas.drawRect(
        Rect.fromLTWH(currentX, 0, segmentWidth, size.height),
        borderPaint,
      );

      // Draw power labels during active workout (when currentPower is provided)
      if (currentPower != null && showLabels) {
        _drawPowerLabels(canvas, currentX, segmentWidth, size.height, segment, heightScale);
      }

      // Draw cadence indicator if present
      if ((segment.cadence != null || segment.cadenceLow != null) && showLabels) {
        _drawCadenceIndicator(canvas, currentX, segmentWidth, size.height, segment);
      }

      currentX += segmentWidth;
    }

    // Draw power grid lines and labels
    _drawPowerGrid(canvas, size, heightScale);
    
    // Draw time grid lines and labels
    _drawTimeGrid(canvas, size, widthScale);

    // Draw actual power trail
    _drawActualPowerTrail(canvas, size, heightScale, widthScale);
  }

  void _drawActualPowerTrail(Canvas canvas, Size size, double heightScale, double widthScale) {
    if (powerPointsList == null || powerPointsList!.isEmpty) return;

    final powerPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = WorkoutStroke.actualPowerLine
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool isFirstPoint = true;

    // Draw interpolated power points
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

    // Draw the power trail
    canvas.drawPath(path, powerPaint);

    // Draw current power dot if available
    if (currentPower != null) {
      final dotPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      final x = currentProgress * size.width;
      final y = size.height - (currentPower! * heightScale);
      
      canvas.drawCircle(
        Offset(x, y),
        WorkoutSizes.actualPowerDotRadius * 1.5,
        dotPaint,
      );
    }
  }

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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
