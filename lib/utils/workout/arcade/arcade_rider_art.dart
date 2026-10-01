import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_pedaling.dart';
import 'arcade_rider_appearance.dart';

/// Detailed vector rider shared by the road and live customization preview.
/// Retains the cadence-driven pose and far-leg occlusion behind the wheels.
class ArcadeRiderArt {
  static const arcadeMint = Color(0xff74ffd3);
  static void _line(Canvas c, Offset a, Offset b, Color color, double width) {
    c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  static void paint(
    Canvas c,
    Offset p, {
    required ArcadeRiderAppearance rider,
    double pedalPhase = 0,
    bool onTarget = false,
    bool moving = false,
    double animation = 0,
  }) {
    c.save();
    c.translate(p.dx, p.dy);
    c.drawOval(
      const Rect.fromLTWH(-36, 6, 73, 17),
      Paint()..color = Colors.black.withValues(alpha: .45),
    );
    final rear = const Offset(-24, 0),
        front = const Offset(26, -7),
        crank = ArcadePedalPose.crank;
    final pose = ArcadePedalPose(pedalPhase);
    // The rider's left leg, shoe and crank sit behind both wheels and frame.
    _leg(
      c,
      pose.hip,
      pose.farKnee,
      pose.farPedal,
      Color.lerp(rider.shorts, Colors.black, .28)!,
      Color.lerp(rider.skin, Colors.black, .24)!,
    );
    _line(c, crank, pose.farPedal, const Color(0xff9aaac3), 2.5);
    _shoe(c, pose.farPedal, Color.lerp(rider.shoes, Colors.black, .2)!);
    for (final wheel in [rear, front]) {
      c.drawCircle(wheel, 16, Paint()..color = const Color(0xff080d1a));
      c.drawCircle(
        wheel,
        15,
        Paint()
          ..color = onTarget ? arcadeMint : const Color(0xff96a8c4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final spin = pedalPhase * 2;
      for (var i = 0; i < 3; i++) {
        final angle = spin + i * math.pi / 3;
        final d = Offset(math.cos(angle), math.sin(angle)) * 13;
        _line(c, wheel - d, wheel + d, Colors.white24, 1);
      }
    }
    const seat = Offset(-12, -25), stem = Offset(15, -30);
    for (final pair in [
      [rear, seat],
      [seat, crank],
      [crank, rear],
      [crank, stem],
      [stem, seat],
      [stem, front],
    ]) {
      _line(c, pair[0], pair[1], const Color(0xff152036), 5);
      _line(c, pair[0], pair[1], rider.bike, 3);
      _line(
        c,
        pair[0] + const Offset(0, -1),
        pair[1] + const Offset(0, -1),
        Color.lerp(rider.bike, Colors.white, .4)!,
        .7,
      );
    }
    // Disc brakes and a frame-mounted bottle give the small bike real detail.
    for (final wheel in [rear, front]) {
      c.drawCircle(
        wheel,
        4,
        Paint()
          ..color = const Color(0xff889ab8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      c.drawCircle(wheel, 1.6, Paint()..color = Colors.white70);
    }
    _line(
      c,
      const Offset(3, -12),
      const Offset(8, -22),
      const Color(0xff10182f),
      5,
    );
    _line(c, const Offset(3, -13), const Offset(7, -21), rider.shoes, 3);
    _line(c, seat, seat + const Offset(0, -7), const Color(0xffb5c5dc), 2);
    _line(c, stem, const Offset(18, -37), Colors.white, 3);
    _line(c, const Offset(11, -37), const Offset(22, -37), Colors.white, 3);
    _line(
      c,
      seat + const Offset(-6, -9),
      seat + const Offset(5, -9),
      Colors.white,
      4,
    );
    c.drawCircle(crank, 5, Paint()..color = const Color(0xff26384b));
    c.drawCircle(
      crank,
      4,
      Paint()
        ..color = arcadeMint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _line(c, crank, pose.nearPedal, Colors.white, 2.5);
    _leg(c, pose.hip, pose.nearKnee, pose.nearPedal, rider.shorts, rider.skin);
    _shoe(c, pose.nearPedal, rider.shoes);
    final jersey = Path()
      ..addPolygon([
        pose.hip + const Offset(-7, 0),
        const Offset(-6, -58),
        const Offset(2, -63),
        const Offset(10, -55),
        pose.hip + const Offset(7, -1),
      ], true);
    c.drawPath(jersey, Paint()..color = rider.jersey);
    c.drawPath(
      jersey,
      Paint()
        ..color = Color.lerp(rider.jersey, Colors.black, .35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _line(
      c,
      const Offset(3, -56),
      const Offset(-4, -41),
      Color.lerp(rider.jersey, Colors.white, .6)!,
      1.2,
    );
    _line(c, const Offset(-12, -45), const Offset(-3, -41), rider.helmet, 2.5);
    _line(c, const Offset(3, -59), const Offset(8, -64), rider.skin, 5);
    _line(c, const Offset(3, -55), const Offset(14, -41), rider.skin, 4);
    _line(c, const Offset(3, -55), const Offset(8, -49), rider.jersey, 6);
    _line(c, const Offset(14, -41), const Offset(21, -37), rider.skin, 4);
    _line(c, const Offset(18, -38), const Offset(22, -37), rider.shoes, 5);
    head(c, const Offset(10, -68), rider);
    if (onTarget && moving) {
      for (var i = 0; i < 4; i++) {
        final t = (animation * .7 + i / 4) % 1;
        c.drawCircle(
          Offset(-40 - t * 45, 6 + i * 4),
          (1 - t) * 3,
          Paint()..color = arcadeMint.withValues(alpha: 1 - t),
        );
      }
    }
    c.restore();
  }

  static void _leg(
    Canvas c,
    Offset hip,
    Offset knee,
    Offset pedal,
    Color shorts,
    Color shin,
  ) {
    _line(c, hip, knee, Color.lerp(shorts, Colors.black, .5)!, 8);
    _line(c, hip, knee, shorts, 6);
    _line(
      c,
      Offset.lerp(hip, knee, .65)!,
      Offset.lerp(hip, knee, .82)!,
      Color.lerp(shorts, Colors.white, .4)!,
      6,
    );
    c.drawCircle(knee, 2.8, Paint()..color = shin);
    _line(c, knee, pedal, shin, 4);
    _line(
      c,
      Offset.lerp(knee, pedal, .7)!,
      pedal,
      const Color(0xffe5edfa),
      4.5,
    );
  }

  static void head(
    Canvas c,
    Offset center,
    ArcadeRiderAppearance rider, {
    double scale = 1,
    bool speaking = false,
    double clock = 0,
  }) {
    const ink = Color(0xff152036);
    c.save();
    c.translate(center.dx, center.dy);
    c.scale(scale);
    c.drawOval(
      const Rect.fromLTWH(-8, -8, 17, 19),
      Paint()..color = rider.skin,
    );
    c.drawArc(
      const Rect.fromLTWH(-8, -8, 17, 19),
      math.pi / 2,
      math.pi,
      false,
      Paint()
        ..color = Color.lerp(rider.skin, Colors.black, .2)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawPath(
      Path()
        ..addPolygon(const [Offset(7, -2), Offset(12, 2), Offset(7, 4)], true),
      Paint()..color = rider.skin,
    );
    // Hair remains visible below the helmet in every style.
    switch (rider.hairStyle) {
      case ArcadeHairStyle.short:
        c.drawPath(
          Path()..addPolygon(const [
            Offset(-9, -6),
            Offset(0, -7),
            Offset(-3, 1),
            Offset(-6, 5),
            Offset(-9, 1),
          ], true),
          Paint()..color = rider.hair,
        );
      case ArcadeHairStyle.curls:
        for (var i = 0; i < 4; i++) {
          c.drawCircle(
            Offset(-7 - (i.isOdd ? 2 : 0), -5 + i * 3),
            3.2,
            Paint()..color = rider.hair,
          );
        }
      case ArcadeHairStyle.ponytail:
        _line(c, const Offset(-6, -4), const Offset(-11, 1), rider.hair, 7);
        c.drawPath(
          Path()
            ..moveTo(-10, 0)
            ..quadraticBezierTo(-22, 2, -16, 15)
            ..quadraticBezierTo(-11, 8, -7, 2)
            ..close(),
          Paint()..color = rider.hair,
        );
        _line(c, const Offset(-12, 1), const Offset(-10, 4), rider.helmet, 2);
    }
    c.drawCircle(
      const Offset(-2, 2),
      2.4,
      Paint()..color = Color.lerp(rider.skin, Colors.white, .12)!,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, -5, 10, 5),
        const Radius.circular(2),
      ),
      Paint()..color = ink,
    );
    _line(
      c,
      const Offset(3, -4),
      const Offset(9, -4),
      const Color(0xff94e9ff),
      1.4,
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(6, 6),
        width: 3,
        height: speaking ? 1.5 + (math.sin(clock * 18) + 1) : 1,
      ),
      Paint()..color = ink,
    );
    final helmet = Path()
      ..addPolygon(const [
        Offset(-11, -6),
        Offset(-9, -12),
        Offset(-1, -16),
        Offset(9, -14),
        Offset(14, -7),
        Offset(6, -6),
        Offset(-3, -8),
      ], true);
    c.drawPath(helmet, Paint()..color = rider.helmet);
    c.drawPath(
      helmet,
      Paint()
        ..color = Color.lerp(rider.helmet, Colors.black, .4)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    _line(
      c,
      const Offset(-7, -11),
      const Offset(0, -14),
      Color.lerp(rider.helmet, Colors.white, .5)!,
      1.2,
    );
    for (var i = 0; i < 3; i++) {
      _line(
        c,
        Offset(-5 + i * 5, -11),
        Offset(-3 + i * 5, -9),
        ink.withValues(alpha: .65),
        2,
      );
    }
    c.restore();
  }

  static void _shoe(Canvas c, Offset pedal, Color color) {
    _line(
      c,
      pedal + const Offset(-3, 1),
      pedal + const Offset(5, 1),
      color,
      3.5,
    );
    _line(
      c,
      pedal + const Offset(-3, 3),
      pedal + const Offset(6, 3),
      const Color(0xff152036),
      1.5,
    );
  }
}
