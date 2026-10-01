import 'dart:math';
import 'package:flutter/material.dart';
import 'workout_parser.dart';
import 'workout_constants.dart';
import 'workout_profile.dart';
import 'workout_visuals.dart';

/// Optional font used by deterministic screenshot tests. Production renders
/// continue to use the platform's default font.
@visibleForTesting
String? debugWorkoutPainterFontFamily;

class WorkoutPainter extends CustomPainter {
  final List<WorkoutSegment> segments;
  final double maxPower;
  final double totalDuration;
  final double ftpValue;
  final double currentProgress;
  final Map<int, double> actualPowerPoints;
  final double? currentPower;
  final int? currentHr;
  final int? currentCadence;
  final List<double>? powerPointsList; // One sample per workout second.
  final List<double>? hrPointsList;
  final List<double>? cadencePointsList;
  final bool showLabels;
  final double pulseValue; // 0.0 to 1.0 for pulse animation
  final bool highlightCurrent;
  final bool completed;

  /// Limits vertical magnification in the live view, equally for targets and
  /// measured power. Thumbnail proportions remain independent of watt units.
  final double? maxPixelsPerWatt;

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
    this.powerPointsList,
    this.hrPointsList,
    this.cadencePointsList,
    this.showLabels = true, // Default to showing labels
    this.pulseValue = 0.0,
    this.highlightCurrent = false,
    this.completed = false,
    this.maxPixelsPerWatt,
  });

  /// All thumbnail and lobby profiles use the same scale and rendering.
  /// A one-second placeholder keeps an unlimited free ride visible.
  factory WorkoutPainter.preview(
    List<WorkoutSegment> segments, {
    double? peak,
    double progress = 0,
    bool highlightCurrent = false,
    bool completed = false,
  }) => WorkoutPainter(
    segments: segments,
    maxPower: peak ?? profilePeak(segments),
    totalDuration: segments.fold<double>(
      0,
      (sum, s) => sum + max(1, s.duration),
    ),
    ftpValue: 1,
    currentProgress: progress,
    actualPowerPoints: const {},
    showLabels: false,
    highlightCurrent: highlightCurrent,
    completed: completed,
  );

  static double profilePeak(List<WorkoutSegment> segments) =>
      segments.fold<double>(
        1,
        (peak, s) => max(
          peak,
          max(workoutSegmentPower(s, 0), workoutSegmentPower(s, 1)),
        ),
      );

  double get _peak => max(1, maxPower.isFinite ? maxPower : 1);

  // Leave the same small amount of headroom in thumbnails and live graphs.
  double _heightScale(Size size) {
    final scale =
        max(0, size.height - min(8, size.height * .2)) / (_peak * ftpValue);
    final limit = maxPixelsPerWatt;
    return limit != null && limit.isFinite && limit > 0
        ? min(scale, limit)
        : scale;
  }

  double powerY(double watts, Size size) =>
      size.height - watts * _heightScale(size);

  /// Public geometry lets interaction and tests use the actual painted ramp.
  Path segmentOutline(WorkoutSegment segment, Rect bounds, Size size) {
    double y(double t) {
      final power = segment.type == SegmentType.freeRide
          ? .5
          : workoutSegmentPower(segment, t);
      return size.height - max(0, power) * ftpValue * _heightScale(size);
    }

    return Path()
      ..moveTo(bounds.left, size.height)
      ..lineTo(bounds.left, y(0))
      ..lineTo(bounds.right, y(1))
      ..lineTo(bounds.right, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty ||
        size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !totalDuration.isFinite ||
        totalDuration <= 0 ||
        !ftpValue.isFinite ||
        ftpValue <= 0)
      return;
    final heightScale = _heightScale(size);
    if (!heightScale.isFinite || heightScale <= 0) return;
    final widthScale = size.width / totalDuration;
    final currentPixel =
        (currentProgress.isFinite ? currentProgress : 0).clamp(0.0, 1.0) *
        size.width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Grids sit behind the translucent profile; compact previews stay clean.
    if (showLabels) {
      _drawPowerGrid(canvas, size, heightScale);
    }
    double currentX = 0;
    for (final segment in segments) {
      final segmentWidth = max(1, segment.duration) * widthScale;
      final end = currentX + segmentWidth;
      final isActive =
          (highlightCurrent || currentPower != null) &&
          currentPixel >= currentX &&
          currentPixel < end;
      final bounds = Rect.fromLTWH(currentX, 0, segmentWidth, size.height);
      final path = segmentOutline(segment, bounds, size);
      double y(double t) =>
          size.height -
          (segment.type == SegmentType.freeRide
                  ? .5
                  : max(0, workoutSegmentPower(segment, t))) *
              ftpValue *
              heightScale;
      final stops = workoutZoneStops(segment);
      for (var i = 0; i < stops.length - 1; i++) {
        final from = stops[i], to = stops[i + 1];
        final color = WorkoutPowerZone.forSegment(
          segment,
          (from + to) / 2,
        ).color;
        final left = currentX + from * segmentWidth;
        final right = currentX + to * segmentWidth;
        final portion = Path()
          ..moveTo(left, size.height)
          ..lineTo(left, y(from))
          ..lineTo(right, y(to))
          ..lineTo(right, size.height)
          ..close();
        canvas.drawPath(
          portion,
          Paint()
            ..color = color.withValues(
              alpha: completed
                  ? .16
                  : .40 + (isActive ? pulseValue.clamp(0.0, 1.0) * .10 : 0),
            ),
        );
        canvas.drawLine(
          Offset(left, y(from)),
          Offset(right, y(to)),
          Paint()
            ..color = color.withValues(alpha: completed ? .4 : 1)
            ..strokeWidth = 2,
        );
      }

      if (isActive) {
        canvas.save();
        canvas.clipPath(path);
        canvas.drawRect(
          Rect.fromLTRB(currentX, 0, currentPixel, size.height),
          Paint()..color = Colors.white.withValues(alpha: .15),
        );
        canvas.drawLine(
          Offset(currentPixel, 0),
          Offset(currentPixel, size.height),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.5,
        );
        canvas.restore();
      }
      if (currentPower != null && showLabels && segmentWidth >= 32) {
        _drawPowerLabels(
          canvas,
          currentX,
          segmentWidth,
          size.height,
          segment,
          heightScale,
        );
      }
      if ((segment.cadence != null || segment.cadenceLow != null) &&
          showLabels &&
          segmentWidth >= 56) {
        _drawCadenceIndicator(
          canvas,
          currentX,
          segmentWidth,
          size.height,
          segment,
        );
      }
      currentX = end;
    }
    canvas.restore();
    if (showLabels) _drawTimeGrid(canvas, size, widthScale);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _drawTracerLines(canvas, size, heightScale, widthScale);
    canvas.restore();
  }

  void _drawTracerLines(
    Canvas canvas,
    Size size,
    double heightScale,
    double widthScale,
  ) {
    Iterable<MapEntry<int, double>> samples(List<double> points) sync* {
      for (var i = 0; i < points.length; i++) {
        yield MapEntry(i, points[i]);
      }
    }

    void trace({
      required Iterable<MapEntry<int, double>> points,
      required Color color,
      required double Function(double) y,
      required double? current,
      bool zeroIsGap = false,
    }) {
      final path = Path();
      var connected = false;
      var hasPoints = false;
      for (final point in points) {
        final value = point.value;
        if (!value.isFinite || value < 0 || (zeroIsGap && value == 0)) {
          connected = false;
          continue;
        }
        final x = point.key * widthScale;
        if (connected) {
          path.lineTo(x, y(value));
        } else {
          path.moveTo(x, y(value));
          connected = true;
        }
        hasPoints = true;
      }
      // A narrow dark halo separates readings from the coloured target tops.
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
        path,
        stroke
          ..color = WorkoutVisuals.ink.withValues(alpha: .65)
          ..strokeWidth = WorkoutStroke.actualPowerLine + 2,
      );
      canvas.drawPath(
        path,
        stroke
          ..color = color
          ..strokeWidth = WorkoutStroke.actualPowerLine,
      );
      if (!hasPoints ||
          current == null ||
          !current.isFinite ||
          current < 0 ||
          (zeroIsGap && current == 0))
        return;
      final center = Offset(
        (currentProgress.isFinite ? currentProgress : 0).clamp(0.0, 1.0) *
            size.width,
        y(current).clamp(0.0, size.height),
      );
      canvas.drawCircle(
        center,
        6,
        Paint()..color = color.withValues(alpha: .16),
      );
      canvas.drawCircle(
        center,
        WorkoutSizes.actualPowerDotRadius * 1.5,
        Paint()..color = color,
      );
    }

    trace(
      points: powerPointsList != null && powerPointsList!.isNotEmpty
          ? samples(powerPointsList!)
          : actualPowerPoints.entries,
      color: WorkoutVisuals.power,
      y: (power) => powerY(power, size),
      current: currentPower,
    );
    trace(
      points: samples(cadencePointsList ?? const []),
      color: WorkoutVisuals.cadence,
      y: (cadence) => size.height * (1 - (cadence - 20) / 110),
      current: currentCadence?.toDouble(),
      zeroIsGap: true,
    );
    trace(
      points: samples(hrPointsList ?? const []),
      color: WorkoutVisuals.heartRate,
      y: (hr) => size.height * (1 - (hr - 30) / 200),
      current: currentHr?.toDouble(),
      zeroIsGap: true,
    );
  }

  void _drawPowerGrid(Canvas canvas, Size size, double heightScale) {
    // Add left padding for power labels
    const double leftPadding = 35.0; // Space for power labels

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.withValues(alpha: WorkoutOpacity.gridLines)
      ..strokeWidth = WorkoutStroke.border;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    final topWatts = size.height / heightScale;
    if (!topWatts.isFinite) return;
    final interval = max(
      WorkoutGrid.powerLineInterval,
      (topWatts / (10 * WorkoutGrid.powerLineInterval)).ceil() *
          WorkoutGrid.powerLineInterval,
    );
    // Label the entire visible watt scale, including the extra headroom.
    for (var power = 0.0; power <= topWatts; power += interval) {
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
            color: WorkoutVisuals.muted,
            fontSize: WorkoutFontSizes.small,
            fontFamily: debugWorkoutPainterFontFamily,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            leftPadding - textPainter.width - 4,
            y - textPainter.height / 2,
          ),
        );
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
    for (
      var time = 0.0;
      time <= totalDuration;
      time += WorkoutGrid.timeLineInterval
    ) {
      final x = time * widthScale;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Draw time labels
      if (showLabels) {
        textPainter.text = TextSpan(
          text: '${(time / 60).round()}min',
          style: TextStyle(
            color: WorkoutVisuals.muted,
            fontSize: WorkoutFontSizes.small,
            fontFamily: debugWorkoutPainterFontFamily,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height + 5),
        );
      }
    }
  }

  void _drawCadenceIndicator(
    Canvas canvas,
    double x,
    double width,
    double height,
    WorkoutSegment segment,
  ) {
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

    final cadenceText =
        segment.cadence ?? '${segment.cadenceLow}-${segment.cadenceHigh}';

    textPainter.text = TextSpan(
      text: '$cadenceText rpm',
      style: TextStyle(
        color: Colors.purple,
        fontSize: WorkoutFontSizes.small,
        fontWeight: FontWeight.bold,
        fontFamily: debugWorkoutPainterFontFamily,
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

  Color _getSegmentColor(WorkoutSegment segment) =>
      WorkoutPowerZone.forSegment(segment).color;

  void _drawPowerLabels(
    Canvas canvas,
    double x,
    double width,
    double height,
    WorkoutSegment segment,
    double heightScale,
  ) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    final color = _getSegmentColor(
      segment,
    ).withValues(alpha: 1.0); // Full opacity for text
    final style = TextStyle(
      color: color,
      fontSize: WorkoutFontSizes.small,
      fontWeight: FontWeight.bold,
      fontFamily: debugWorkoutPainterFontFamily,
    );

    if (segment.isRamp) {
      // For ramp segments, show both start and end power
      final startPower = segment.type == SegmentType.cooldown
          ? segment.powerHigh
          : segment.powerLow;
      final endPower = segment.type == SegmentType.cooldown
          ? segment.powerLow
          : segment.powerHigh;

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
