import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Split into rear and front layers so the crew remain inside the falling cage.
class ArcadeCageArt {
  static void paint(Canvas c, Offset base, Color tint, {required bool front}) {
    const ink = Color(0xff151827);
    const steel = Color(0xffa2819b);
    const armor = Color(0xff49364e);
    final stroke = Paint()..strokeCap = StrokeCap.round;
    void line(Offset a, Offset b, Color color, double width) {
      c.drawLine(
        a,
        b,
        stroke
          ..color = color
          ..strokeWidth = width,
      );
    }

    void plate(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      c.drawPath(path, Paint()..color = color);
      c.drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    c.save();
    c.translate(base.dx, base.dy);
    if (!front) {
      // Recessed back wall, visible through the open bars.
      c.drawRect(
        const Rect.fromLTWH(-37, -60, 83, 58),
        Paint()..color = ink.withValues(alpha: .28),
      );
      for (var i = 0; i < 6; i++) {
        final x = -35.0 + i * 16;
        line(Offset(x, -58), Offset(x, -2), steel.withValues(alpha: .38), 1.5);
      }
      line(const Offset(-37, -60), const Offset(47, -60), steel, 4);
      line(const Offset(-37, -2), const Offset(47, -2), armor, 5);
      c.restore();
      return;
    }

    // Angled right wall and a forged, beveled roof give the trap depth.
    plate(const [
      Offset(44, -50),
      Offset(53, -59),
      Offset(53, -2),
      Offset(44, 7),
    ], armor);
    for (var y = -43.0; y < -5; y += 12) {
      line(Offset(48, y), Offset(50, y - 2), steel, 2);
    }
    plate(const [
      Offset(-47, -51),
      Offset(-37, -63),
      Offset(43, -63),
      Offset(53, -51),
    ], steel);
    plate(const [
      Offset(-47, -51),
      Offset(53, -51),
      Offset(44, -43),
      Offset(-44, -43),
    ], armor);
    line(
      const Offset(-35, -60),
      const Offset(40, -60),
      tint.withValues(alpha: .8),
      2,
    );
    // Bars are spaced around the crew's faces, with a bright edge on each rod.
    for (final x in [-44.0, -16.0, 15.0, 44.0]) {
      line(Offset(x, -45), Offset(x, 5), ink, 6);
      line(Offset(x - 1, -45), Offset(x - 1, 5), steel, 2);
    }
    line(const Offset(-44, -12), const Offset(44, -12), armor, 4);

    // Heavy skids, hazard stripes and riveted corners.
    plate(const [
      Offset(-48, 0),
      Offset(47, 0),
      Offset(53, -5),
      Offset(53, 6),
      Offset(44, 12),
      Offset(-48, 12),
    ], armor);
    line(const Offset(-45, 2), const Offset(44, 2), steel, 2);
    for (var i = 0; i < 10; i++) {
      final x = -40.0 + i * 8;
      line(Offset(x, 6), Offset(x + 3, 9), i.isEven ? tint : ink, 3);
    }
    for (final x in [-42.0, 42.0]) {
      for (final y in [-48.0, 7.0]) {
        c.drawCircle(Offset(x, y), 2, Paint()..color = steel);
        c.drawCircle(
          Offset(x - .5, y - .5),
          .65,
          Paint()..color = Colors.white,
        );
      }
    }
    // Sprocket-shaped lock, hanging low enough to leave faces visible.
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, -20, 8, 11),
        const Radius.circular(4),
      ),
      Paint()
        ..color = steel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 4; i++) {
      c.save();
      c.translate(0, -10);
      c.rotate(i * math.pi / 4);
      c.drawRect(const Rect.fromLTWH(-3, -9, 6, 18), Paint()..color = steel);
      c.restore();
    }
    c.drawCircle(const Offset(0, -10), 6.5, Paint()..color = ink);
    c.drawCircle(const Offset(0, -11), 2, Paint()..color = tint);
    line(const Offset(0, -10), const Offset(0, -6), tint, 2);
    c.drawCircle(
      const Offset(51, -23),
      4,
      Paint()
        ..color = steel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.restore();
  }

  static void chain(Canvas c, Offset from, Offset to, Color tint) {
    for (var i = 0; i < 7; i++) {
      final p = Offset.lerp(from, to, i / 6)!;
      c.drawOval(
        Rect.fromCenter(center: p, width: 6, height: i.isEven ? 4 : 2),
        Paint()
          ..color = tint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }
}
