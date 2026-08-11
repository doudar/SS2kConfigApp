import 'package:flutter/material.dart';

class HomingProximityGauge extends StatelessWidget {
  const HomingProximityGauge({
    super.key,
    required this.progress,
    required this.title,
    required this.currentLabel,
    required this.targetLabel,
    required this.detailLabel,
  });

  final double progress;
  final String title;
  final String currentLabel;
  final String targetLabel;
  final String detailLabel;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.0, 1.0);
    final percentage = (normalized * 100).round();
    final theme = Theme.of(context);

    return Semantics(
      excludeSemantics: true,
      label:
          '$title. $currentLabel. $targetLabel. $percentage percent to target.',
      value: '$percentage%',
      child: Container(
        key: const Key('homing_proximity_gauge_container'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.error),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            if (detailLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(detailLabel, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: normalized),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeInOutCubic,
                builder: (context, animatedProgress, _) => CustomPaint(
                  painter: _GaugePainter(
                    progress: animatedProgress,
                    pointerColor: theme.colorScheme.primary,
                    outlineColor: theme.colorScheme.outlineVariant,
                    bubbleColor: theme.colorScheme.secondaryContainer,
                    bubbleTextColor: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(currentLabel, style: theme.textTheme.labelMedium),
                Text(
                  targetLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.progress,
    required this.pointerColor,
    required this.outlineColor,
    required this.bubbleColor,
    required this.bubbleTextColor,
  });

  final double progress;
  final Color pointerColor;
  final Color outlineColor;
  final Color bubbleColor;
  final Color bubbleTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 24.0;
    const horizontalInset = 18.0;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        horizontalInset,
        2,
        size.width - horizontalInset * 2,
        barHeight,
      ),
      const Radius.circular(barHeight / 2),
    );

    canvas.drawRRect(
      bar,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xff66bb3a),
            Color(0xffc9db32),
            Color(0xffffb52d),
            Color(0xffef3f37),
          ],
          stops: [0, 0.38, 0.7, 1],
        ).createShader(bar.outerRect),
    );
    canvas.drawRRect(
      bar,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final x = horizontalInset + progress * (size.width - horizontalInset * 2);
    final triangle = Path()
      ..moveTo(x, 13)
      ..lineTo(x - 7, 36)
      ..lineTo(x + 7, 36)
      ..close();
    canvas.drawPath(triangle, Paint()..color = pointerColor);
    canvas.drawCircle(Offset(x, 35), 3.5, Paint()..color = Colors.white);

    final bubbleCenter = Offset(x, 54);
    canvas.drawCircle(bubbleCenter, 16, Paint()..color = bubbleColor);
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${(progress * 100).round()}%',
        style: TextStyle(
          color: bubbleTextColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      bubbleCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      pointerColor != oldDelegate.pointerColor ||
      outlineColor != oldDelegate.outlineColor ||
      bubbleColor != oldDelegate.bubbleColor ||
      bubbleTextColor != oldDelegate.bubbleTextColor;
}
