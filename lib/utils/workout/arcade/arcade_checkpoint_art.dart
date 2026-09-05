import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A gate spanning the road, painted in the world's reflected coordinates.
class ArcadeCheckpointArt {
  static void paint(
    Canvas canvas, {
    required Offset farFoot,
    required Offset nearFoot,
    required Color color,
    required String title,
    required String target,
    required bool finish,
  }) {
    const ink = Color(0xff10182f);
    final stroke = Paint()..strokeCap = StrokeCap.round;
    void line(Offset a, Offset b, Color tint, double width) {
      canvas.drawLine(
        a,
        b,
        stroke
          ..color = tint
          ..strokeWidth = width,
      );
    }

    // A checkered timing strip follows the same plane as the road surface.
    for (var i = 0; i < 12; i++) {
      line(
        Offset.lerp(farFoot, nearFoot, i / 12)!,
        Offset.lerp(farFoot, nearFoot, (i + 1) / 12)!,
        i.isEven ? Colors.white.withValues(alpha: .8) : ink,
        4,
      );
    }
    const rise = Offset(0, -94);
    final farTop = farFoot + rise, nearTop = nearFoot + rise;
    for (final foot in [farFoot, nearFoot]) {
      final top = foot + rise;
      canvas.drawOval(
        Rect.fromCenter(center: foot, width: 18, height: 9),
        Paint()..color = ink,
      );
      line(foot, top, ink, 11);
      line(foot, top, const Color(0xff778599), 7);
      line(foot + const Offset(-2, -4), top, color, 2);
      canvas.drawCircle(top, 6, Paint()..color = ink);
      canvas.drawCircle(top, 3, Paint()..color = color);
    }
    line(farTop, nearTop, ink, 9);

    // Undo the world reflection before drawing text. The sign's baseline
    // follows the isometric crossbar while the letters stay readable.
    final center = Offset.lerp(farTop, nearTop, .5)!;
    final crossbar = nearTop - farTop;
    final width = crossbar.distance;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(-1, 1);
    canvas.rotate(math.atan2(crossbar.dy, -crossbar.dx));
    final panel = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: width, height: 32),
      const Radius.circular(4),
    );
    canvas.drawRRect(panel, Paint()..color = ink);
    canvas.drawRRect(
      panel,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final side in [-1.0, 1.0]) {
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 2; col++) {
          if ((row + col).isOdd) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              side * (width / 2 - 8) + col * 3 - 3,
              -6 + row * 3,
              3,
              3,
            ),
            Paint()..color = finish ? Colors.white : color,
          );
        }
      }
    }
    void label(String text, double y, double fontSize, Color tint) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: tint,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: width - 25);
      painter.paint(canvas, Offset(-painter.width / 2, y));
      painter.dispose();
    }

    label(title, -12, 10, color);
    label(target, 2, 8, Colors.white);
    canvas.restore();
  }
}
