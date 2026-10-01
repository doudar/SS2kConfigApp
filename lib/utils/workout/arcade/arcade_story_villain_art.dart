import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_drones.dart';
import 'arcade_enemy_art.dart';
import 'arcade_golem_art.dart';

/// One episode villain across the cinematic, towing chase and distant skyline.
/// Positions use the combat artwork's chest origin; callers choose their scale.
class ArcadeStoryVillainArt {
  static double _bob(ArcadeDroneStyle style, double clock, bool running) {
    if (!running) return 0;
    return switch (style) {
      ArcadeDroneStyle.stormRay ||
      ArcadeDroneStyle.voidRegent => -5 + math.sin(clock * 2.5) * 3,
      ArcadeDroneStyle.duneScorpion => math.sin(clock * 8).abs() * -1.5,
      _ => math.sin(clock * 7).abs() * -2,
    };
  }

  static Offset head(
    ArcadeDroneStyle style,
    double clock, {
    bool running = false,
  }) =>
      Offset(0, switch (style) {
        ArcadeDroneStyle.duneScorpion => -14,
        ArcadeDroneStyle.stormRay => -25,
        ArcadeDroneStyle.bramble => -34,
        ArcadeDroneStyle.voidRegent => -35,
        _ => -41,
      }) +
      Offset(0, _bob(style, clock, running));

  /// Actual visible hand, pincer or tow eye; kept in sync with the body pose.
  static Offset towAnchor(
    ArcadeDroneStyle style,
    double clock, {
    bool running = false,
    double side = -1,
  }) {
    if (style == ArcadeDroneStyle.golem) {
      final breath = math.sin(clock * 2.6);
      return running
          ? ArcadeGolemArt.runningHand(clock, side)
          : Offset(
              side * (49 + breath * 2),
              24 - side * breath * 3 + breath * 1.3,
            );
    }
    final point = switch (style) {
      ArcadeDroneStyle.bramble => Offset(
        side * 43,
        18 + math.sin(clock * 1.8 + side) * 3,
      ),
      ArcadeDroneStyle.duneScorpion => Offset(side * 49, -13),
      ArcadeDroneStyle.frostWarden => Offset(side * 43, 24),
      ArcadeDroneStyle.stormRay => Offset(side * 25, 20),
      ArcadeDroneStyle.voidRegent => Offset(
        side * 43,
        18 + math.sin(clock * 2 + side) * 4,
      ),
      _ => Offset(side * 27, 12),
    };
    return point + Offset(0, _bob(style, clock, running));
  }

  static void paint(
    Canvas c,
    Offset p,
    double clock, {
    required ArcadeDroneStyle style,
    bool speaking = false,
    bool running = false,
    double damage = 0,
  }) {
    if (style == ArcadeDroneStyle.golem) {
      ArcadeGolemArt.paint(
        c,
        p,
        clock,
        speaking: speaking,
        running: running,
        damage: damage,
      );
      return;
    }
    c.save();
    c.translate(p.dx, p.dy + _bob(style, clock, running));
    final walker =
        style == ArcadeDroneStyle.bramble ||
        style == ArcadeDroneStyle.frostWarden;
    if (walker && running) {
      // Replace the standing legs with opposite-phase planted/returning feet.
      final color = ArcadeEnemyArt.tint(style);
      final dark = Color.lerp(color, const Color(0xff10182f), .55)!;
      for (final side in [-1.0, 1.0]) {
        final phase = (clock * 1.5 + (side < 0 ? .5 : 0)) % 1;
        final swing = phase < .5
            ? 14 * (1 - phase * 4)
            : -14 * math.cos((phase - .5) * math.pi * 2);
        final lift = phase < .5
            ? 0.0
            : math.sin((phase - .5) * math.pi * 2) * 14;
        final hip = Offset(side * 8, 23);
        final foot = Offset(side * 7 + swing, 58 - lift);
        final knee = Offset.lerp(hip, foot, .5)! + const Offset(6, -2);
        final paint = Paint()
          ..color = dark
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round;
        c.drawLine(hip, knee, paint);
        c.drawLine(knee, foot, paint);
        c.drawLine(
          knee,
          foot,
          Paint()
            ..color = color
            ..strokeWidth = 4,
        );
        c.drawLine(
          foot - const Offset(5, 0),
          foot + const Offset(8, 0),
          Paint()
            ..color = color
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
      }
      c.save();
      c.clipRect(const Rect.fromLTWH(-80, -85, 160, 112));
      ArcadeEnemyArt.paint(c, style, clock, damage: damage);
      c.restore();
    } else {
      ArcadeEnemyArt.paint(c, style, clock, damage: damage, counter: speaking);
    }
    if (style == ArcadeDroneStyle.stormRay) {
      // A metal tow eye under each wing makes the cage's chain attachment clear.
      for (final side in [-1.0, 1.0]) {
        c.drawCircle(
          Offset(side * 25, 20),
          3,
          Paint()
            ..color = const Color(0xffe0d5f6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    if (speaking) {
      final h = head(style, clock);
      c.drawOval(
        Rect.fromCenter(
          center: h + const Offset(0, 10),
          width: 7,
          height: 2 + (math.sin(clock * 19) + 1) * 2,
        ),
        Paint()..color = const Color(0xff10182f),
      );
    }
    c.restore();
  }

  /// Tiny feet-origin outline, matching the original Golem's 18px height.
  static void outline(
    Canvas c,
    Offset feet,
    double clock, {
    required ArcadeDroneStyle style,
    Color color = const Color(0xffff5a65),
    double slope = 0,
  }) {
    if (style == ArcadeDroneStyle.golem) {
      ArcadeGolemArt.runningOutline(c, feet, clock, color, slope: slope);
      return;
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    c.save();
    c.translate(feet.dx, feet.dy);
    c.rotate(slope.clamp(-.5, .5));
    void shape(List<Offset> points) =>
        c.drawPath(Path()..addPolygon(points, true), stroke);
    switch (style) {
      case ArcadeDroneStyle.stormRay:
        final flap = math.sin(clock * 2) * 1.5;
        shape([
          const Offset(0, -15),
          Offset(-8, -16 + flap),
          Offset(-11, -7 + flap),
          const Offset(-3, -9),
          const Offset(0, -6),
          const Offset(3, -9),
          Offset(11, -7 + flap),
          Offset(8, -16 + flap),
        ]);
        c.drawPath(
          Path()
            ..moveTo(0, -6)
            ..quadraticBezierTo(math.sin(clock * 2) * 4, -3, 1, 0),
          stroke,
        );
      case ArcadeDroneStyle.duneScorpion:
        shape(const [
          Offset(-4, -9),
          Offset(3, -10),
          Offset(5, -5),
          Offset(1, -3),
          Offset(-4, -5),
        ]);
        c.drawPath(
          Path()
            ..moveTo(3, -7)
            ..lineTo(7, -12)
            ..lineTo(5, -17)
            ..lineTo(-1, -18)
            ..lineTo(-4, -14),
          stroke,
        );
        for (final side in [-1.0, 1.0]) {
          for (var i = 0; i < 3; i++) {
            c.drawLine(
              Offset(side * 3, -7.0 + i * 2),
              Offset(side * (7 + i), math.sin(clock * 5 + i) - 1),
              stroke,
            );
          }
          c.drawLine(Offset(side * 3, -9), Offset(side * 8, -12), stroke);
        }
      default:
        final isRegent = style == ArcadeDroneStyle.voidRegent;
        shape(const [
          Offset(-4, -12),
          Offset(4, -12),
          Offset(5, -6),
          Offset(0, -4),
          Offset(-5, -6),
        ]);
        shape([
          const Offset(-3, -12),
          Offset(-4, isRegent ? -18 : -16),
          const Offset(0, -16),
          const Offset(3, -18),
          const Offset(4, -12),
        ]);
        for (final side in [-1.0, 1.0]) {
          final stride = math.sin(clock * 8 + (side < 0 ? math.pi : 0)) * 3;
          c.drawLine(
            Offset(side * 2, -5),
            Offset(side * 2 + stride, isRegent ? -1 : 0),
            stroke,
          );
          c.drawLine(
            Offset(side * 4, -11),
            Offset(side * 7 - stride * .4, -5),
            stroke,
          );
          if (style == ArcadeDroneStyle.bramble) {
            c.drawLine(Offset(side * 2, -15), Offset(side * 6, -18), stroke);
          }
        }
    }
    c.restore();
  }
}
