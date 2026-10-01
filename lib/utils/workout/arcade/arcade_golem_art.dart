import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared forge monster. Fixed geometry and bounded particles keep ride-time
/// animation inexpensive; all movement follows the existing scene clock.
class ArcadeGolemArt {
  static const _ink = Color(0xff151827);
  static const _steel = Color(0xffa2819b);
  static const _armor = Color(0xff673e59);
  static const _ember = Color(0xffff9760);

  // Opposite legs are half a stride apart. The planted foot pushes backward
  // along the ground; only the returning foot lifts and swings forward.
  static Offset _runningFoot(double clock, double side) {
    final phase = (clock * 1.6 + (side < 0 ? .5 : 0)) % 1;
    if (phase < .5) return Offset(18 * (1 - phase * 4), 0);
    final swing = (phase - .5) * 2;
    return Offset(
      -18 * math.cos(swing * math.pi),
      -16 * math.sin(swing * math.pi),
    );
  }

  // Bend the knee forward between a hip and ankle instead of oscillating it
  // independently in the opposite direction to its own foot.
  static Offset _runningKnee(
    Offset hip,
    Offset ankle,
    double thigh,
    double shin,
  ) {
    final delta = ankle - hip;
    final distance = math.max(.001, delta.distance);
    final along =
        (thigh * thigh - shin * shin + distance * distance) / (2 * distance);
    final bend = math.sqrt(math.max(0, thigh * thigh - along * along));
    return hip +
        delta * (along / distance) +
        Offset(delta.dy, -delta.dx) * (bend / distance);
  }

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

  static void _plate(Canvas c, List<Offset> points, Color color) {
    final path = Path()..addPolygon(points, true);
    c.drawPath(path, Paint()..color = color);
    c.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  static void _gear(Canvas c, Offset center, double radius, double angle) {
    final points = List.generate(48, (i) {
      final a = angle + i * math.pi / 24;
      final r = radius * (i % 4 < 2 ? 1 : .82);
      return center + Offset(math.cos(a), math.sin(a)) * r;
    });
    _plate(c, points, _steel);
    c.drawCircle(center, radius * .62, Paint()..color = _ink);
    for (var i = 0; i < 3; i++) {
      final a = angle + i * math.pi * 2 / 3;
      _line(
        c,
        center,
        center + Offset(math.cos(a), math.sin(a)) * radius * .53,
        _armor,
        3,
      );
    }
    c.drawCircle(center, 3, Paint()..color = _ember);
  }

  static double _runningBob(double clock) =>
      math.sin(clock * 1.6 * math.pi * 2).abs() * 3;

  /// Chest-relative running hand position, also used to attach a towing chain.
  static Offset runningHand(double clock, double side) => Offset(
    side * 32 - _runningFoot(clock, side).dx * .85 + 21,
    -10 - _runningBob(clock),
  );

  /// Origin is the chest; the head sits at (0, -33), soles at y=58.
  static void paint(
    Canvas c,
    Offset p,
    double clock, {
    double damage = 0,
    bool firing = false,
    bool speaking = false,
    bool running = false,
  }) {
    final wear = damage.clamp(0.0, 1.0);
    final breath = math.sin(clock * 2.6);
    final jaw = speaking ? 2 + (math.sin(clock * 19) + 1) * 2 : 0.0;
    final hit = firing
        ? math.pow(math.max(0.0, math.sin(clock * 13)), 12).toDouble()
        : 0.0;
    c.save();
    c.translate(p.dx + hit * 2, p.dy);
    c.drawOval(
      const Rect.fromLTWH(-44, 51, 88, 14),
      Paint()..color = Colors.black.withValues(alpha: .32),
    );

    // Crank-driven legs with steel pistons and treaded boots.
    for (final side in [-1.0, 1.0]) {
      final stride = math.sin(clock * 3 + (side < 0 ? math.pi : 0)) * 3;
      final hip = Offset(side * (running ? 7 : 16), 19);
      final ankle = running
          ? Offset(side * 7, 51) + _runningFoot(clock, side)
          : Offset(side * 23, 51);
      final knee = running
          ? _runningKnee(hip, ankle, 20, 23)
          : Offset(side * 22, 37 + stride);
      _line(c, hip, knee, _ink, 15);
      _line(c, hip + const Offset(3, 0), knee, _steel, 4);
      _gear(c, knee, 8, -clock * side);
      _line(c, knee, ankle, _armor, 11);
      // Both boots point down the road when running, rather than splaying out.
      final facing = running ? 1.0 : side;
      _plate(c, [
        ankle + Offset(facing * -11, -4),
        ankle + Offset(facing * 7, -5),
        ankle + Offset(facing * 15, 5),
        ankle + Offset(facing * -13, 5),
      ], _steel);
      for (var i = 0; i < 3; i++) {
        _line(
          c,
          ankle + Offset(facing * (-7 + i * 7), 2),
          ankle + Offset(facing * (-6 + i * 7), 5),
          _ink,
          2,
        );
      }
    }

    // Twin exhaust stacks, little puffs and drifting forge embers.
    for (final side in [-1.0, 1.0]) {
      _line(c, Offset(side * 22, -20), Offset(side * 27, -54), _ink, 9);
      _line(
        c,
        Offset(side * 27 - 4, -54),
        Offset(side * 27 + 4, -54),
        _steel,
        3,
      );
      for (var i = 0; i < 3; i++) {
        final t = (clock * .55 + i / 3 + side * .1) % 1;
        c.drawCircle(
          Offset(side * 27 + math.sin(t * 5 + side) * 5, -58 - t * 26),
          3 + t * 6,
          Paint()..color = _steel.withValues(alpha: (1 - t) * .22),
        );
      }
    }

    c.save();
    final upperBody = Offset(
      running ? 5 : 0,
      running ? -_runningBob(clock) : breath * 1.3,
    );
    c.translate(upperBody.dx, upperBody.dy);
    for (final side in [-1.0, 1.0]) {
      final swing = running ? -_runningFoot(clock, side).dx * .85 : 0.0;
      final elbow = running
          ? Offset(side * 32 + swing, 6)
          : Offset(side * (44 + breath * 2), 6);
      final fist = running
          ? runningHand(clock, side) - upperBody
          : Offset(side * (49 + breath * 2), 24 - side * breath * 3);
      _line(c, Offset(side * 28, -14), elbow, _ink, 13);
      _line(c, Offset(side * 30, -14), elbow, _steel, 4);
      _line(c, elbow, fist, _armor, 13);
      _line(
        c,
        elbow + Offset(side * 4, 0),
        fist + Offset(side * 4, -3),
        _steel,
        3,
      );
      _gear(c, Offset(side * 31, -17), 16, clock * side * .7);
      _plate(c, [
        fist + const Offset(-9, -6),
        fist + const Offset(8, -8),
        fist + const Offset(11, 9),
        fist + const Offset(-10, 10),
      ], _armor);
      for (var i = 0; i < 3; i++) {
        _line(
          c,
          fist + Offset(-5 + i * 5, 1),
          fist + Offset(-5 + i * 5, 7),
          _steel,
          2,
        );
      }
    }

    _plate(c, const [
      Offset(-29, -21),
      Offset(-14, -29),
      Offset(18, -27),
      Offset(29, -17),
      Offset(25, 24),
      Offset(0, 31),
      Offset(-26, 23),
    ], _armor);
    _plate(c, const [
      Offset(-26, -20),
      Offset(-14, -25),
      Offset(-13, 22),
      Offset(-23, 18),
    ], const Color(0xffbd7890));
    _line(c, const Offset(17, -20), const Offset(23, 16), _steel, 2);
    for (final x in [-20.0, 20.0]) {
      for (final y in [-16.0, 18.0]) {
        c.drawCircle(Offset(x, y), 2, Paint()..color = _steel);
      }
    }

    // A spinning chainring around a furnace, with a pulsing hot center.
    _gear(c, const Offset(0, 5), 18, -clock * .8);
    c.drawCircle(
      const Offset(0, 5),
      11,
      Paint()..color = _ember.withValues(alpha: .35),
    );
    c.drawCircle(const Offset(0, 5), 8 + breath, Paint()..color = _ember);
    c.drawCircle(
      const Offset(-1, 4),
      4,
      Paint()..color = const Color(0xffffedb0),
    );
    for (var i = -1; i <= 1; i++) {
      _line(c, Offset(i * 5.0, -4), Offset(i * 5.0, 14), _ink, 2);
    }

    // Helmet crest, visor and an articulated sprocket-toothed jaw.
    _plate(c, const [
      Offset(-19, -27),
      Offset(-22, -47),
      Offset(-13, -55),
      Offset(0, -49),
      Offset(13, -55),
      Offset(22, -47),
      Offset(19, -27),
    ], _steel);
    _plate(c, const [
      Offset(-18, -44),
      Offset(0, -40),
      Offset(18, -44),
      Offset(15, -29),
      Offset(-15, -29),
    ], _ink);
    _line(c, const Offset(-14, -39), const Offset(-4, -35), _ember, 3);
    _line(c, const Offset(4, -35), const Offset(14, -39), _ember, 3);
    _plate(c, [
      Offset(-15, -28 + jaw),
      Offset(15, -28 + jaw),
      Offset(10, -20 + jaw),
      Offset(-10, -20 + jaw),
    ], _steel);
    for (var i = 0; i < 5; i++) {
      _line(
        c,
        Offset(-10 + i * 5.0, -29 + jaw),
        Offset(-10 + i * 5.0, -25 + jaw),
        _ink,
        2,
      );
    }
    if (wear > .3) {
      _line(c, const Offset(18, -17), const Offset(12, -10), _ember, 1.5);
      _line(c, const Offset(12, -10), const Offset(20, -5), _ember, 1.5);
    }
    if (wear > .65) {
      _line(c, const Offset(-21, 5), const Offset(-16, 15), _ember, 2);
      _line(c, const Offset(-16, 15), const Offset(-21, 22), _ember, 2);
      for (var i = 0; i < 4; i++) {
        final t = (clock * 1.2 + i / 4) % 1;
        c.drawCircle(
          Offset(-20 - t * 16, 8 + t * 24),
          1.5,
          Paint()..color = _ember.withValues(alpha: 1 - t),
        );
      }
    }
    if (hit > .1) {
      for (var i = 0; i < 5; i++) {
        final ray = Offset(math.cos(i * 1.3), math.sin(i * 1.3));
        _line(c, ray * 17, ray * (17 + hit * 13), const Color(0xffffedb0), 2);
      }
    }
    c.restore();
    c.restore();
  }

  /// A distant, right-facing runner. Strokes only: no glow, smoke or trail.
  /// The origin is ground level and the crest is 18 pixels above it.
  static void runningOutline(
    Canvas c,
    Offset feet,
    double clock,
    Color color, {
    double slope = 0,
  }) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    c.save();
    c.translate(feet.dx, feet.dy);
    c.rotate(slope.clamp(-.5, .5));
    c.scale(.75);
    for (final side in [-1.0, 1.0]) {
      final hip = Offset(side - 1, -11);
      final foot = Offset(side, 0) + _runningFoot(clock, side) * .3;
      final knee = _runningKnee(hip, foot, 6.8, 7.4);
      c.drawPath(
        Path()
          ..moveTo(hip.dx - 1, hip.dy)
          ..lineTo(knee.dx - 2, knee.dy)
          ..lineTo(foot.dx - 2, foot.dy)
          ..lineTo(foot.dx + 3, foot.dy)
          ..lineTo(knee.dx + 1, knee.dy - 1)
          ..lineTo(hip.dx + 1, hip.dy),
        stroke,
      );
      final arm = -_runningFoot(clock, side).dx * .3;
      c.drawPath(
        Path()
          ..moveTo(1, -18)
          ..lineTo(arm, -13)
          ..lineTo(arm + 4, -16),
        stroke,
      );
    }
    c.drawPath(
      Path()..addPolygon(const [
        Offset(-5, -18),
        Offset(3, -20),
        Offset(6, -14),
        Offset(2, -10),
        Offset(-5, -12),
      ], true),
      stroke,
    );
    c.drawPath(
      Path()..addPolygon(const [
        Offset(-2, -19),
        Offset(-3, -23),
        Offset(0, -22),
        Offset(3, -24),
        Offset(6, -22),
        Offset(7, -19),
        Offset(4, -17),
      ], true),
      stroke,
    );
    c.drawCircle(const Offset(-3, -17), 2.5, stroke);
    c.drawLine(const Offset(3, -21), const Offset(6, -20), stroke);
    c.restore();
  }
}
