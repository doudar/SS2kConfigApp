import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/workout/workout_visuals.dart';

/// A compact dial showing the normalized position of the stepper motor.
///
/// A null [progress] means that the travel limits are not known yet. In that
/// state the dial stays neutral and does not draw a needle at an invented
/// position.
class StepperTravelGauge extends StatelessWidget {
  const StepperTravelGauge({super.key, this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final normalized = value != null && value.isFinite
        ? value.clamp(0.0, 1.0).toDouble()
        : null;
    final formatted = normalized == null
        ? null
        : (normalized * 100).toStringAsFixed(1);
    return _RoundGauge(
      progress: normalized,
      label: 'TRAVEL',
      semanticLabel: 'Stepper travel',
      semanticValue: formatted == null
          ? 'Unavailable'
          : '$formatted percent of stepper travel',
      centerText: formatted == null ? '—' : '$formatted%',
      keyPrefix: 'stepper_travel_gauge',
      warnNearLimit: true,
    );
  }
}

/// Uses the app's incline display range of -30% to +30%, with zero at the top.
/// The needle clamps to the dial, but the center retains the reported value.
class TargetInclineGauge extends StatelessWidget {
  const TargetInclineGauge({super.key, this.incline});

  final double? incline;

  @override
  Widget build(BuildContext context) {
    final value = incline;
    final known = value != null && value.isFinite;
    // Avoid displaying negative zero after rounding a very small descent.
    final formatted = known
        ? (value.abs() < .05 ? 0.0 : value).toStringAsFixed(1)
        : null;
    return _RoundGauge(
      progress: known ? ((value + 30) / 60).clamp(0.0, 1.0) : null,
      label: 'TARGET INCLINE',
      semanticLabel: 'Target incline',
      semanticValue: formatted == null ? 'Unavailable' : '$formatted percent',
      centerText: formatted == null ? '—' : '$formatted%',
      keyPrefix: 'target_incline_gauge',
    );
  }
}

class _RoundGauge extends StatelessWidget {
  const _RoundGauge({
    required this.progress,
    required this.label,
    required this.semanticLabel,
    required this.semanticValue,
    required this.keyPrefix,
    this.centerText,
    this.warnNearLimit = false,
  });

  final double? progress;
  final String label;
  final String semanticLabel;
  final String semanticValue;
  final String keyPrefix;
  final String? centerText;
  final bool warnNearLimit;

  static const _dialSize = 100.0;
  static const _nearLimitColor = Color(0xffff6b6b);

  @override
  Widget build(BuildContext context) {
    final normalized = progress;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final bezelColor = warnNearLimit && normalized != null && normalized >= .9
        ? _nearLimitColor
        : WorkoutVisuals.muted;

    return Semantics(
      container: true,
      label: semanticLabel,
      value: semanticValue,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WorkoutVisuals.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox.square(
              dimension: _dialSize,
              child: DecoratedBox(
                key: Key('${keyPrefix}_bezel'),
                decoration: BoxDecoration(
                  color: WorkoutVisuals.panel,
                  shape: BoxShape.circle,
                  border: Border.all(color: bezelColor, width: 3),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _AnimatedDial(
                      progress: normalized,
                      reducedMotion: reducedMotion,
                      keyPrefix: keyPrefix,
                      insetNeedle: centerText != null,
                    ),
                    if (centerText != null)
                      Center(
                        child: SizedBox(
                          width: 64,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              centerText!,
                              style: const TextStyle(
                                color: WorkoutVisuals.mint,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDial extends StatelessWidget {
  const _AnimatedDial({
    required this.progress,
    required this.reducedMotion,
    required this.keyPrefix,
    required this.insetNeedle,
  });

  final double? progress;
  final bool reducedMotion;
  final String keyPrefix;
  final bool insetNeedle;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    if (value == null) {
      return CustomPaint(
        key: Key('${keyPrefix}_dial'),
        painter: const _StepperTravelGaugePainter(),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) => CustomPaint(
        key: Key('${keyPrefix}_dial'),
        painter: _StepperTravelGaugePainter(
          progress: animatedValue,
          insetNeedle: insetNeedle,
        ),
      ),
    );
  }
}

class _StepperTravelGaugePainter extends CustomPainter {
  const _StepperTravelGaugePainter({this.progress, this.insetNeedle = false});

  final double? progress;
  final bool insetNeedle;

  // Sweep across the upper half of the dial so the travel endpoints read as
  // 0 at the left and 100 at the right.
  static const _startAngle = math.pi;
  static const _sweepAngle = math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      arcRect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = WorkoutVisuals.muted.withValues(alpha: .25)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5,
    );

    final value = progress;
    if (value != null) {
      canvas.drawArc(
        arcRect,
        _startAngle,
        _sweepAngle * value,
        false,
        Paint()
          ..color = WorkoutVisuals.power
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5,
      );
    }

    _drawTicks(canvas, center, radius);
    if (value == null) return;

    final angle = _startAngle + _sweepAngle * value;
    final needleLength = insetNeedle ? radius + 1 : radius - 5;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final needleEnd =
        center +
        Offset(math.cos(angle) * needleLength, math.sin(angle) * needleLength);
    canvas.drawLine(
      insetNeedle ? center + direction * (radius - 8) : center,
      needleEnd,
      Paint()
        ..color = WorkoutVisuals.mint
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3,
    );
    if (!insetNeedle) {
      canvas.drawCircle(center, 5, Paint()..color = WorkoutVisuals.mint);
      canvas.drawCircle(center, 2, Paint()..color = WorkoutVisuals.panel);
    }
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    for (var index = 0; index <= 10; index++) {
      final fraction = index / 10;
      final angle = _startAngle + _sweepAngle * fraction;
      final isMajor = index == 0 || index == 5 || index == 10;
      final outerRadius = radius + 5;
      final innerRadius = radius - (isMajor ? 5 : 2.5);
      final start =
          center +
          Offset(math.cos(angle) * innerRadius, math.sin(angle) * innerRadius);
      final end =
          center +
          Offset(math.cos(angle) * outerRadius, math.sin(angle) * outerRadius);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = WorkoutVisuals.muted.withValues(alpha: isMajor ? .75 : .42)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = isMajor ? 2 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StepperTravelGaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.insetNeedle != insetNeedle;
}
