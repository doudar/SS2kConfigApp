import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'arcade_drones.dart';
import 'arcade_enemy_art.dart';

/// Counterattacks share the encounter clock and use a bounded set of vectors.
/// The caller keeps [source] at the launch position as the enemy escapes.
class ArcadeEnemyAttacks {
  static const _ink = Color(0xff111b31);

  static void paint(
    Canvas c,
    ArcadeDroneFrame frame, {
    required Offset source,
    required Offset target,
    required double scale,
    required bool reducedMotion,
  }) {
    if (frame.phase != ArcadeDronePhase.departing || !frame.stolePoints) return;
    if (scale <= 0 || !scale.isFinite) return;
    final progress = (frame.age / ArcadeDrones.departureSeconds).clamp(
      0.0,
      1.0,
    );
    if (progress >= 1) return;
    final tint = ArcadeEnemyArt.tint(frame.style);
    final alpha = (1 - ((progress - .78) / .22).clamp(0.0, 1.0));
    final delta = target - source;
    final distance = delta.distance / scale;
    final arcSide = delta.dx >= 0 ? -1.0 : 1.0;
    c.save();
    c.translate(source.dx, source.dy);
    c.rotate(math.atan2(delta.dy, delta.dx));
    c.scale(scale);
    if (reducedMotion) {
      // A quiet source emblem and target ring communicate the same consequence
      // without a sweeping beam, flying projectile, or expanding impact.
      _emblem(
        c,
        frame.style,
        Offset.zero,
        tint.withValues(alpha: alpha * .75),
        0,
      );
      _ring(c, Offset(distance, 0), 13, tint.withValues(alpha: alpha * .55), 2);
      c.restore();
      return;
    }
    final flight = (progress / .68).clamp(0.0, 1.0);
    final impact = ((progress - .68) / .32).clamp(0.0, 1.0);
    final color = tint.withValues(alpha: alpha);
    final pale = Color.lerp(tint, Colors.white, .7)!.withValues(alpha: alpha);
    final center = Offset(distance * flight, 0);
    switch (frame.style) {
      case ArcadeDroneStyle.wheel:
        if (flight < 1) {
          _line(
            c,
            center - const Offset(25, 0),
            center,
            color.withValues(alpha: .35),
            4,
          );
          _gear(c, center, 11, color, progress * 15);
        }
      case ArcadeDroneStyle.sentinel:
        for (final side in [-1.0, 1.0]) {
          final end = center + Offset(0, side * 5 * (1 - flight));
          final start = Offset(
            math.max(0, end.dx - 65),
            side * 9 * (1 - flight),
          );
          _line(c, start, end, color.withValues(alpha: alpha * .3), 7);
          _line(c, start, end, pale, 2);
        }
      case ArcadeDroneStyle.beetle:
        if (flight < 1) {
          for (var i = -1; i <= 1; i++) {
            final p =
                center +
                Offset(-i.abs() * 13, i * 21 * math.sin(flight * math.pi));
            _line(
              c,
              p - const Offset(17, 0),
              p,
              color.withValues(alpha: .4),
              3,
            );
            _bolt(c, p, color, progress * 8 + i);
          }
        }
      case ArcadeDroneStyle.wasp:
        if (flight < 1) {
          final p =
              center + Offset(0, arcSide * math.sin(flight * math.pi) * 25);
          _shard(c, p, 20, color);
          for (var i = 1; i <= 3; i++) {
            _line(
              c,
              p + Offset(-i * 5, -3),
              p + Offset(-i * 5 - 4, -8),
              pale,
              1.5,
            );
            _line(
              c,
              p + Offset(-i * 5, 3),
              p + Offset(-i * 5 - 4, 8),
              pale,
              1.5,
            );
          }
        }
      case ArcadeDroneStyle.orb:
        if (flight < 1) {
          for (var i = 0; i < 3; i++) {
            final p = center - Offset(i * 15.0, 0);
            c.drawOval(
              Rect.fromCenter(
                center: p,
                width: 8 + flight * 12,
                height: 18 + flight * 22 - i * 3,
              ),
              _stroke(color.withValues(alpha: alpha * (1 - i * .23)), 2.5),
            );
          }
          _line(c, center - const Offset(25, 0), center, pale, 2);
        }
      case ArcadeDroneStyle.golem:
        if (flight < 1) {
          final p =
              center + Offset(0, arcSide * math.sin(flight * math.pi) * 60);
          _gear(c, p, 19, color, progress * 8);
          _polygon(c, [
            p + const Offset(-7, -7),
            p + const Offset(7, -5),
            p + const Offset(8, 5),
            p + const Offset(-4, 9),
          ], _ink);
          _line(c, p + const Offset(-5, -6), p + const Offset(6, -4), pale, 2);
        }
      case ArcadeDroneStyle.bramble:
        final vine = Path()..moveTo(0, 0);
        final length = distance * flight;
        for (var i = 1; i <= 16; i++) {
          final fraction = i / 16;
          vine.lineTo(
            length * fraction,
            math.sin(fraction * math.pi * 5) *
                10 *
                math.sin(fraction * math.pi),
          );
        }
        c.drawPath(vine, _stroke(_ink.withValues(alpha: alpha), 7));
        c.drawPath(vine, _stroke(color, 4));
        for (var i = 1; i <= 7; i++) {
          final f = i / 8;
          final p = Offset(
            length * f,
            math.sin(f * math.pi * 5) * 10 * math.sin(f * math.pi),
          );
          final side = i.isEven ? 1.0 : -1.0;
          _polygon(c, [
            p,
            p + Offset(-8, side * 11),
            p + const Offset(-6, 0),
          ], color);
        }
        if (flight < 1) _shard(c, center, 13, pale);
      case ArcadeDroneStyle.duneScorpion:
        if (flight < 1) {
          for (var i = -2; i <= 2; i++) {
            final p =
                center +
                Offset(-i.abs() * 9, math.sin(flight * math.pi) * i * 13);
            _line(
              c,
              p - const Offset(12, 0),
              p,
              color.withValues(alpha: .45),
              3,
            );
            _drop(c, p, 5.5 - i.abs() * .5, color);
          }
        }
      case ArcadeDroneStyle.frostWarden:
        if (flight < 1) {
          for (var i = -2; i <= 2; i++) {
            final p =
                center +
                Offset(-i.abs() * 11, i * 20 * math.sin(flight * math.pi));
            _shard(c, p, 14 - i.abs() * 2, color);
            _line(
              c,
              p - const Offset(8, 0),
              p + const Offset(11, 0),
              pale,
              1.3,
            );
          }
        }
      case ArcadeDroneStyle.stormRay:
        final bolt = Path()..moveTo(0, 0);
        for (var i = 1; i <= 10; i++) {
          final f = i / 10;
          bolt.lineTo(
            distance * flight * f,
            i == 10 ? 0 : (i.isEven ? -1 : 1) * (5 + (i % 3) * 4.0),
          );
        }
        c.drawPath(bolt, _stroke(color.withValues(alpha: alpha * .25), 9));
        c.drawPath(bolt, _stroke(color, 4));
        c.drawPath(bolt, _stroke(pale, 1.5));
      case ArcadeDroneStyle.voidRegent:
        for (final p in [Offset.zero, Offset(distance, 0)]) {
          c.drawOval(
            Rect.fromCenter(center: p, width: 12, height: 40),
            _stroke(color.withValues(alpha: alpha * .75), 3),
          );
          c.drawOval(
            Rect.fromCenter(center: p, width: 6, height: 30),
            _stroke(pale.withValues(alpha: alpha * .5), 1),
          );
        }
        // Stolen stars return through the portal toward their master.
        for (var i = 0; i < 3; i++) {
          final f = ((flight * 1.4 - i * .15).clamp(0.0, 1.0));
          if (f > 0 && f < 1) {
            final p = Offset(
              distance * (1 - f),
              math.sin(f * math.pi) * (i - 1) * 18,
            );
            _star(c, p, 6, color, progress * 4);
          }
        }
    }
    if (impact > 0) _impact(c, frame.style, Offset(distance, 0), impact, color);
    c.restore();
  }

  /// Telegraph the final two seconds of the ready window near the weapon.
  /// Call with the current enemy center; no stored launch point is needed.
  static void paintWarning(
    Canvas c,
    ArcadeDroneFrame frame, {
    required Offset source,
    required Offset target,
    required double scale,
    required bool reducedMotion,
  }) {
    if (!frame.ready || frame.secondsLeft > 2 || scale <= 0) return;
    final delta = target - source;
    final charge = (1 - frame.secondsLeft / 2).clamp(0.0, 1.0);
    final color = ArcadeEnemyArt.tint(
      frame.style,
    ).withValues(alpha: .55 + charge * .3);
    c.save();
    c.translate(source.dx, source.dy);
    c.rotate(math.atan2(delta.dy, delta.dx));
    c.scale(scale);
    final p = Offset(frame.isBoss ? 40 : 26, 0);
    _ring(c, p, 15, color.withValues(alpha: .25), 1.5);
    c.drawArc(
      Rect.fromCircle(center: p, radius: 15),
      -math.pi / 2,
      math.pi * 2 * charge,
      false,
      _stroke(color, 2),
    );
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(.65);
    _emblem(
      c,
      frame.style,
      Offset.zero,
      color,
      reducedMotion ? 0 : frame.clock * 2,
    );
    c.restore();
    c.restore();
  }

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static void _line(Canvas c, Offset a, Offset b, Color color, double width) =>
      c.drawLine(a, b, _stroke(color, width));
  static void _ring(Canvas c, Offset p, double r, Color color, double width) =>
      c.drawCircle(p, r, _stroke(color, width));

  static void _polygon(Canvas c, List<Offset> points, Color color) {
    final path = Path()..addPolygon(points, true);
    c.drawPath(path, Paint()..color = color);
    c.drawPath(path, _stroke(_ink.withValues(alpha: color.a), 1.5));
  }

  static void _gear(Canvas c, Offset p, double r, Color color, double turn) {
    _polygon(
      c,
      List.generate(32, (i) {
        final angle = turn + i * math.pi / 16;
        final radius = r * (i % 4 < 2 ? 1 : .77);
        return p + Offset(math.cos(angle), math.sin(angle)) * radius;
      }),
      color,
    );
    _ring(c, p, r * .43, _ink.withValues(alpha: color.a), 3);
    c.drawCircle(
      p,
      2,
      Paint()..color = Colors.white.withValues(alpha: color.a * .8),
    );
  }

  static void _bolt(Canvas c, Offset p, Color color, double turn) {
    _polygon(
      c,
      List.generate(
        6,
        (i) =>
            p +
            Offset(
                  math.cos(turn + i * math.pi / 3),
                  math.sin(turn + i * math.pi / 3),
                ) *
                7,
      ),
      color,
    );
    _line(
      c,
      p - const Offset(3, 0),
      p + const Offset(3, 0),
      _ink.withValues(alpha: color.a),
      2,
    );
  }

  static void _shard(Canvas c, Offset p, double r, Color color) {
    _polygon(c, [
      p + Offset(r, 0),
      p + Offset(-r * .7, -r * .34),
      p + Offset(-r * .4, 0),
      p + Offset(-r * .7, r * .34),
    ], color);
    _line(
      c,
      p - Offset(r * .4, 0),
      p + Offset(r * .8, 0),
      Colors.white.withValues(alpha: color.a * .7),
      1,
    );
  }

  static void _drop(Canvas c, Offset p, double r, Color color) {
    final path = Path()
      ..moveTo(p.dx - r * 2, p.dy)
      ..quadraticBezierTo(p.dx + r, p.dy - r * 1.8, p.dx + r, p.dy)
      ..quadraticBezierTo(p.dx + r, p.dy + r * 1.8, p.dx - r * 2, p.dy);
    c.drawPath(path, Paint()..color = color);
    _line(
      c,
      p,
      p + Offset(r * .3, -r * .4),
      Colors.white.withValues(alpha: color.a * .7),
      1.5,
    );
  }

  static void _star(Canvas c, Offset p, double r, Color color, double turn) {
    _polygon(
      c,
      List.generate(8, (i) {
        final angle = turn + i * math.pi / 4;
        return p +
            Offset(math.cos(angle), math.sin(angle)) * (i.isEven ? r : r * .35);
      }),
      color,
    );
  }

  static void _emblem(
    Canvas c,
    ArcadeDroneStyle style,
    Offset p,
    Color color,
    double turn,
  ) {
    switch (style) {
      case ArcadeDroneStyle.wheel || ArcadeDroneStyle.golem:
        _gear(c, p, 10, color, turn);
      case ArcadeDroneStyle.beetle:
        _bolt(c, p, color, turn);
      case ArcadeDroneStyle.wasp || ArcadeDroneStyle.frostWarden:
        _shard(c, p, 12, color);
      case ArcadeDroneStyle.duneScorpion:
        _drop(c, p, 7, color);
      case ArcadeDroneStyle.bramble:
        _polygon(c, [
          p + const Offset(12, 0),
          p + const Offset(-5, -9),
          p + const Offset(-1, 0),
          p + const Offset(-5, 9),
        ], color);
      case ArcadeDroneStyle.orb:
        _ring(c, p, 10, color, 2);
        _ring(c, p, 5, color, 2);
      case ArcadeDroneStyle.sentinel:
        _line(c, p + const Offset(-10, -4), p + const Offset(10, -4), color, 3);
        _line(c, p + const Offset(-10, 4), p + const Offset(10, 4), color, 3);
      case ArcadeDroneStyle.stormRay:
        c.drawPath(
          Path()
            ..moveTo(p.dx - 10, p.dy - 7)
            ..lineTo(p.dx + 1, p.dy - 2)
            ..lineTo(p.dx - 2, p.dy + 3)
            ..lineTo(p.dx + 11, p.dy + 8),
          _stroke(color, 3),
        );
      case ArcadeDroneStyle.voidRegent:
        _star(c, p, 12, color, turn);
    }
  }

  static void _impact(
    Canvas c,
    ArcadeDroneStyle style,
    Offset p,
    double progress,
    Color color,
  ) {
    final alpha = color.a * (1 - progress);
    if (alpha <= 0) return;
    final tint = color.withValues(alpha: alpha);
    final radius = 9 + progress * (style.isBoss ? 27 : 18);
    _ring(c, p, radius, tint.withValues(alpha: alpha * .45), 2);
    // Six short fragments remain local to the rider, with no full-screen flash.
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + .25;
      final unit = Offset(math.cos(angle), math.sin(angle));
      final fragment = p + unit * radius;
      switch (style) {
        case ArcadeDroneStyle.frostWarden || ArcadeDroneStyle.wasp:
          _shard(c, fragment, 5, tint);
        case ArcadeDroneStyle.duneScorpion:
          c.drawCircle(fragment, 2 + (1 - progress) * 2, Paint()..color = tint);
        case ArcadeDroneStyle.voidRegent:
          _star(c, fragment, 4, tint, angle);
        case ArcadeDroneStyle.bramble:
          _polygon(c, [
            fragment,
            fragment + unit * 7,
            fragment + Offset(-unit.dy, unit.dx) * 4,
          ], tint);
        case ArcadeDroneStyle.beetle ||
            ArcadeDroneStyle.golem ||
            ArcadeDroneStyle.wheel:
          _bolt(c, fragment, tint, angle);
        default:
          _line(c, fragment, fragment + unit * 7, tint, 2);
      }
    }
  }
}
