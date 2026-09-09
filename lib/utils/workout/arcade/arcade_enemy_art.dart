import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_drones.dart';
import 'arcade_golem_art.dart';

/// Small, fixed vector silhouettes. No particles, images or extra tickers.
/// Every boss fits the same generous targeting envelope as the original golem.
class ArcadeEnemyArt {
  static const _ink = Color(0xff10182f);
  static const _eye = Color(0xffffe2a1);
  static Color tint(ArcadeDroneStyle style) => switch (style) {
    ArcadeDroneStyle.wheel => const Color(0xff72d7ff),
    ArcadeDroneStyle.sentinel => const Color(0xffbc9aff),
    ArcadeDroneStyle.beetle ||
    ArcadeDroneStyle.bramble => const Color(0xff9ce68c),
    ArcadeDroneStyle.wasp ||
    ArcadeDroneStyle.duneScorpion => const Color(0xffffc565),
    ArcadeDroneStyle.orb ||
    ArcadeDroneStyle.frostWarden => const Color(0xff96e5ff),
    ArcadeDroneStyle.stormRay => const Color(0xffd1b6ff),
    ArcadeDroneStyle.voidRegent => const Color(0xffff83c7),
    _ => const Color(0xffff9760),
  };

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

  static void _plate(
    Canvas c,
    List<Offset> points,
    Color color, {
    double width = 2,
  }) {
    final path = Path()..addPolygon(points, true);
    c.drawPath(path, Paint()..color = color);
    c.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static void _orb(Canvas c, Offset p, double radius, Color color) {
    c.drawCircle(p, radius + 2, Paint()..color = _ink);
    c.drawCircle(p, radius, Paint()..color = color);
    c.drawCircle(
      p + Offset(-radius * .25, -radius * .3),
      radius * .25,
      Paint()..color = Colors.white.withValues(alpha: .7),
    );
  }

  static void _eyes(
    Canvas c,
    double y, {
    double spacing = 8,
    Color color = _eye,
  }) {
    for (final side in [-1.0, 1.0]) {
      _line(
        c,
        Offset(side * (spacing - 3), y + 1),
        Offset(side * (spacing + 3), y - 1),
        _ink,
        7,
      );
      _line(
        c,
        Offset(side * (spacing - 3), y + 1),
        Offset(side * (spacing + 3), y - 1),
        color,
        3,
      );
    }
  }

  static void _gear(
    Canvas c,
    Offset center,
    double radius,
    Color color,
    double turn,
  ) {
    _plate(
      c,
      List.generate(32, (i) {
        final angle = turn + i * math.pi / 16;
        final r = radius * (i % 4 < 2 ? 1 : .8);
        return center + Offset(math.cos(angle), math.sin(angle)) * r;
      }),
      color,
      width: 1.5,
    );
    c.drawCircle(center, radius * .5, Paint()..color = _ink);
    c.drawCircle(center, radius * .2, Paint()..color = _eye);
  }

  static void paint(
    Canvas c,
    ArcadeDroneStyle style,
    double clock, {
    double damage = 0,
    bool hit = false,
    bool counter = false,
  }) {
    if (style == ArcadeDroneStyle.golem) {
      ArcadeGolemArt.paint(
        c,
        Offset.zero,
        clock,
        damage: damage,
        firing: hit,
        speaking: counter,
      );
      return;
    }
    final color = tint(style);
    c.save();
    if (hit) c.translate(math.sin(clock * 30) * 2, 0);
    switch (style) {
      case ArcadeDroneStyle.beetle:
        _beetle(c, color, clock);
      case ArcadeDroneStyle.wasp:
        _wasp(c, color, clock);
      case ArcadeDroneStyle.orb:
        _pulseOrb(c, color, clock);
      case ArcadeDroneStyle.bramble:
        _bramble(c, color, clock);
      case ArcadeDroneStyle.duneScorpion:
        _scorpion(c, color, clock);
      case ArcadeDroneStyle.frostWarden:
        _frost(c, color, clock);
      case ArcadeDroneStyle.stormRay:
        _ray(c, color, clock);
      case ArcadeDroneStyle.voidRegent:
        _regent(c, color, clock);
      default:
        break;
    }
    if (style.isBoss) _details(c, style, color);
    _surfaceDetails(c, style, color, clock);
    if (style.isBoss && damage > 0) {
      // Consistent readable armor damage across all silhouettes.
      final crack = Path()
        ..moveTo(-9, -7)
        ..lineTo(-3, 0)
        ..lineTo(-8, 7)
        ..lineTo(2, 17);
      c.drawPath(
        crack,
        Paint()
          ..color = _eye.withValues(alpha: .5 + damage * .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + damage,
      );
      if (damage >= .5) {
        _line(c, const Offset(12, 2), const Offset(6, 11), _eye, 1.5);
        _line(c, const Offset(6, 11), const Offset(13, 17), _eye, 1.5);
      }
    }
    c.restore();
  }

  static void _stroke(Canvas c, Path path, Color color, double width) {
    c.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static void _rivet(Canvas c, Offset p, Color color, {double radius = 1.5}) {
    c.drawCircle(p, radius + .6, Paint()..color = _ink);
    c.drawCircle(p, radius, Paint()..color = color);
    _line(
      c,
      p + Offset(-radius * .45, -.3),
      p + Offset(radius * .45, -.3),
      _ink,
      .65,
    );
  }

  static void _gem(Canvas c, Offset p, double radius, Color color) {
    _plate(
      c,
      [
        p + Offset(0, -radius),
        p + Offset(radius * .7, 0),
        p + Offset(0, radius),
        p + Offset(-radius * .7, 0),
      ],
      color,
      width: 1,
    );
    c.drawPath(
      Path()..addPolygon([
        p + Offset(0, -radius),
        p,
        p + Offset(-radius * .7, 0),
      ], true),
      Paint()..color = Color.lerp(color, Colors.white, .65)!,
    );
    c.drawPath(
      Path()..addPolygon([
        p,
        p + Offset(radius * .7, 0),
        p + Offset(0, radius),
      ], true),
      Paint()..color = Color.lerp(color, _ink, .35)!,
    );
  }

  /// Fixed, bounded surface geometry follows the same limb/wing poses as the
  /// base artwork. All animation uses the existing clock, including previews.
  static void _surfaceDetails(
    Canvas c,
    ArcadeDroneStyle style,
    Color color,
    double clock,
  ) {
    final light = Color.lerp(color, Colors.white, .55)!;
    final dark = Color.lerp(color, _ink, .55)!;
    const brass = Color(0xffd7ae68);
    switch (style) {
      case ArcadeDroneStyle.beetle:
        for (final side in [-1.0, 1.0]) {
          _plate(
            c,
            [
              Offset(side * 4, -10),
              Offset(side * 12, -16),
              Offset(side * 17, -7),
              Offset(side * 16, 10),
              Offset(side * 8, 14),
              Offset(side * 5, 7),
            ],
            side < 0 ? color : dark,
            width: 1,
          );
          _stroke(
            c,
            Path()
              ..moveTo(side * 7, -10)
              ..quadraticBezierTo(side * 15, -11, side * 14, 5),
            light,
            1.2,
          );
          for (var i = 0; i < 3; i++) {
            _line(
              c,
              Offset(side * 9, -5.0 + i * 4),
              Offset(side * 14, -7.0 + i * 4),
              _ink,
              1.3,
            );
          }
          _rivet(c, Offset(side * 9, 10), brass, radius: 1.1);
          final knee = Offset(side * 27, 6 + math.sin(clock * 7 + 1) * 2);
          _rivet(c, knee, brass, radius: 2);
          _line(c, Offset(side * 16, 9), knee, light, 1);
          _plate(
            c,
            [
              Offset(side * 3, -17),
              Offset(side * 9, -20),
              Offset(side * 12, -16),
              Offset(side * 8, -13),
            ],
            brass,
            width: 1,
          );
          _line(c, Offset(side * 6, -17), Offset(side * 10, -17), light, 1);
        }
        _plate(
          c,
          const [
            Offset(-5, -8),
            Offset(0, -11),
            Offset(5, -8),
            Offset(4, -3),
            Offset(-4, -3),
          ],
          dark,
          width: 1,
        );
        _rivet(c, const Offset(0, -7), light, radius: 1.2);
        _stroke(
          c,
          Path()..addArc(const Rect.fromLTWH(-8, -3, 16, 16), .3, 2),
          light,
          1,
        );
        _line(c, const Offset(-3, 15), const Offset(3, 15), brass, 2);
      case ArcadeDroneStyle.wasp:
        final flutter = math.sin(clock * 28) * 4;
        for (final side in [-1.0, 1.0]) {
          final root = Offset(side * 10, -5);
          final tip = Offset(side * 33, -22 - flutter);
          _line(c, root, tip, light.withValues(alpha: .8), 1.2);
          _line(c, root, Offset(side * 35, -8), light.withValues(alpha: .7), 1);
          _line(
            c,
            Offset(side * 19, -10),
            Offset(side * 25, -17 - flutter * .5),
            light,
            .7,
          );
          _line(
            c,
            Offset(side * 25, -7),
            Offset(side * 29, -18 - flutter * .7),
            light,
            .7,
          );
          _rivet(c, root, brass, radius: 2.2);
          _plate(
            c,
            [
              Offset(side * 2, -13),
              Offset(side * 8, -15),
              Offset(side * 10, -8),
              Offset(side * 3, -8),
            ],
            dark,
            width: 1,
          );
          _gem(c, Offset(side * 6, -11), 2.8, const Color(0xffff9b62));
          _line(c, Offset(side * 4, -17), Offset(side * 9, -24), brass, 1);
        }
        _plate(
          c,
          const [
            Offset(-7, -5),
            Offset(0, -8),
            Offset(7, -5),
            Offset(6, 0),
            Offset(-6, 0),
          ],
          brass,
          width: 1,
        );
        _rivet(c, const Offset(0, -3), light, radius: 1.6);
        _line(c, const Offset(-10, 7), const Offset(9, 7), light, 1);
        for (var i = 0; i < 3; i++) {
          _line(
            c,
            Offset(-4.0 + i, 17.0 + i * 3),
            Offset(4.0 - i, 17.0 + i * 3),
            dark,
            1.5,
          );
        }
        _gem(c, const Offset(0, 24), 3.2, const Color(0xffffeee1));
      case ArcadeDroneStyle.orb:
        // Three inset shell panels surround a scanning optical core.
        for (var i = 0; i < 3; i++) {
          c.save();
          c.rotate(i * math.pi * 2 / 3);
          _stroke(
            c,
            Path()..addArc(const Rect.fromLTWH(-15, -15, 30, 30), -1.2, 1.35),
            light,
            2.2,
          );
          _rivet(c, const Offset(11, -7), brass, radius: 1.2);
          _line(c, const Offset(4, -12), const Offset(7, -10), color, 1);
          c.restore();
        }
        c.drawCircle(const Offset(0, -1), 7, Paint()..color = _ink);
        c.drawCircle(const Offset(0, -1), 5.5, Paint()..color = color);
        final pupil = Offset(math.sin(clock * 1.5) * 1.5, -1);
        c.drawCircle(pupil, 2.8, Paint()..color = _ink);
        c.drawCircle(
          pupil + const Offset(-1, -1.5),
          1.2,
          Paint()..color = Colors.white,
        );
        for (var i = 0; i < 3; i++) {
          c.save();
          c.rotate(clock * .6 + i * math.pi / 3);
          _line(c, const Offset(-24, -7), const Offset(-19, -9), brass, 1.5);
          _line(c, const Offset(18, 9), const Offset(22, 8), light, 1.5);
          c.restore();
        }
      case ArcadeDroneStyle.bramble:
        final wood = Color.lerp(color, const Color(0xff9e7250), .7)!;
        for (final side in [-1.0, 1.0]) {
          final sway = math.sin(clock * 1.8 + side) * 3;
          _stroke(
            c,
            Path()
              ..moveTo(side * 17, -17)
              ..lineTo(side * 22, -5)
              ..lineTo(side * 18, 10)
              ..lineTo(side * 22, 24),
            wood,
            2,
          );
          _stroke(
            c,
            Path()
              ..moveTo(side * 10, -10)
              ..lineTo(side * 13, -4)
              ..lineTo(side * 12, 0),
            light.withValues(alpha: .5),
            1,
          );
          _line(
            c,
            Offset(side * 36, -10 + sway),
            Offset(side * 39, 17 + sway),
            wood,
            2,
          );
          _line(
            c,
            Offset(side * 42, -6 + sway),
            Offset(side * 43, 9 + sway),
            light.withValues(alpha: .45),
            1,
          );
          _stroke(
            c,
            Path()
              ..moveTo(side * 17, 37)
              ..lineTo(side * 22, 45)
              ..lineTo(side * 20, 57),
            wood,
            2,
          );
          _line(c, Offset(side * 21, -18), Offset(side * 39, -29), light, 1.2);
          _line(c, Offset(side * 28, -22), Offset(side * 30, -29), light, 1);
          _line(c, Offset(side * 30, -23), Offset(side * 35, -21), dark, 1);
          // Moss shelves sit on the branches and move with the hands.
          c.drawOval(
            Rect.fromCenter(
              center: Offset(side * 38, -8 + sway),
              width: 13,
              height: 5,
            ),
            Paint()..color = color,
          );
          _gem(c, Offset(side * 21, 17), 3.5, light);
          _line(c, Offset(side * 10, -32), Offset(side * 4, -30), dark, 2);
          _line(c, Offset(side * 9, -21), Offset(side * 4, -19), wood, 1.5);
        }
        _stroke(
          c,
          Path()..addOval(const Rect.fromLTWH(-7, -18, 14, 6)),
          wood,
          1.2,
        );
        for (var i = 0; i < 3; i++) {
          _line(
            c,
            Offset(-4.0 + i * 4, -17),
            Offset(-3.0 + i * 4, -15),
            light,
            1,
          );
        }
        c.drawCircle(
          const Offset(0, 7),
          5.5,
          Paint()..color = const Color(0xff33492d),
        );
        _gem(c, const Offset(0, 7), 5, const Color(0xffffdf8b));
        _stroke(
          c,
          Path()
            ..moveTo(-9, 24)
            ..quadraticBezierTo(0, 34, 10, 25),
          color,
          2,
        );
        _plate(
          c,
          const [Offset(-10, 24), Offset(-18, 21), Offset(-13, 17)],
          light,
          width: .7,
        );
      case ArcadeDroneStyle.duneScorpion:
        for (final side in [-1.0, 1.0]) {
          _plate(
            c,
            [
              Offset(side * 35, -22),
              Offset(side * 49, -26),
              Offset(side * 52, -17),
              Offset(side * 45, -15),
            ],
            light,
            width: 1,
          );
          _line(c, Offset(side * 35, -15), Offset(side * 28, -10), brass, 3);
          _line(c, Offset(side * 33, -16), Offset(side * 21, -7), light, 1);
          _rivet(c, Offset(side * 34, -14), dark, radius: 3);
          _rivet(c, Offset(side * 49, -21), brass, radius: 1.4);
          for (var i = 0; i < 3; i++) {
            final y = 6.0 + i * 10;
            final knee = Offset(side * (32 + i * 4), y + 3);
            _rivet(c, knee, brass, radius: 2.2);
            final foot = Offset(
              side * (43 + i * 4),
              y + 17 + math.sin(clock * 4 + i + side) * 3,
            );
            _line(c, knee, Offset.lerp(knee, foot, .65)!, light, 1.2);
            _rivet(c, Offset(side * 13, 10 + i * 9), dark, radius: 1.1);
          }
          _line(c, Offset(side * 4, -13), Offset(side * 12, -15), light, 1.2);
        }
        const joints = [
          Offset(13, 12),
          Offset(34, -4),
          Offset(35, -28),
          Offset(18, -48),
          Offset(-6, -52),
        ];
        for (final joint in joints.skip(1)) {
          _rivet(c, joint, brass, radius: 2.5);
        }
        _stroke(
          c,
          Path()
            ..moveTo(28, -5)
            ..lineTo(29, -25)
            ..lineTo(15, -42)
            ..lineTo(-5, -46),
          light,
          1.2,
        );
        _gem(c, const Offset(-19, -37), 5, const Color(0xffef8c4f));
        _plate(
          c,
          const [Offset(-7, -3), Offset(0, -6), Offset(7, -3), Offset(0, 3)],
          brass,
          width: 1,
        );
        for (var i = 0; i < 3; i++) {
          _line(c, Offset(-10, 7.0 + i * 9), Offset(0, 11.0 + i * 9), light, 1);
        }
      case ArcadeDroneStyle.frostWarden:
        for (final side in [-1.0, 1.0]) {
          _plate(
            c,
            [
              Offset(side * 25, -22),
              Offset(side * 36, -34),
              Offset(side * 30, -8),
            ],
            const Color(0xffe3fcff),
            width: .7,
          );
          _line(c, Offset(side * 35, -26), Offset(side * 45, -17), dark, 1);
          _line(c, Offset(side * 40, -18), Offset(side * 40, -11), light, 1);
          _plate(
            c,
            [
              Offset(side * 33, 3),
              Offset(side * 42, 0),
              Offset(side * 48, 22),
              Offset(side * 42, 29),
            ],
            color,
            width: 1,
          );
          _line(c, Offset(side * 38, 5), Offset(side * 42, 19), light, 1.4);
          _line(c, Offset(side * 35, 11), Offset(side * 41, 9), light, 1);
          _line(c, Offset(side * 37, 17), Offset(side * 43, 15), light, 1);
          _gem(c, Offset(side * 18, 31), 5, light);
          _plate(
            c,
            [
              Offset(side * 13, 41),
              Offset(side * 22, 38),
              Offset(side * 26, 53),
              Offset(side * 13, 56),
            ],
            color,
            width: 1,
          );
          _line(c, Offset(side * 15, 42), Offset(side * 18, 51), light, 1);
          _line(
            c,
            Offset(side * 14, -48),
            Offset(side * 9, -54),
            Colors.white,
            1.2,
          );
          _plate(
            c,
            [
              Offset(side * 5, -28),
              Offset(side * 10, -26),
              Offset(side * 7, -18),
            ],
            light,
            width: .6,
          );
        }
        _gem(c, const Offset(0, -57), 3.5, const Color(0xffeaffff));
        _stroke(
          c,
          Path()
            ..moveTo(-9, -16)
            ..lineTo(-20, -18)
            ..lineTo(-21, -9),
          light,
          1.5,
        );
        _stroke(
          c,
          Path()
            ..moveTo(9, -16)
            ..lineTo(20, -18)
            ..lineTo(21, -9),
          color,
          1.5,
        );
        for (var i = 0; i < 6; i++) {
          c.save();
          c.translate(0, 3);
          c.rotate(i * math.pi / 3);
          _line(c, const Offset(0, 6), const Offset(0, 12), light, 1);
          _line(c, const Offset(0, 9), const Offset(-2, 7), light, 1);
          c.restore();
        }
        _gem(c, const Offset(0, 3), 4, Colors.white);
      case ArcadeDroneStyle.stormRay:
        final flap = math.sin(clock * 2) * 7;
        for (final side in [-1.0, 1.0]) {
          final root = Offset(side * 16, -8);
          _line(
            c,
            Offset(side * 14, -24),
            Offset(side * 39, -36 + flap),
            light,
            1.3,
          );
          for (var i = 0; i < 3; i++) {
            final tip = Offset(side * (37 + i * 5), -28 + flap + i * 11);
            _stroke(
              c,
              Path()
                ..moveTo(root.dx, root.dy)
                ..quadraticBezierTo(side * 29, -15 + i * 3.0, tip.dx, tip.dy),
              dark,
              1.2,
            );
            final node = Offset.lerp(root, tip, .7)!;
            c.drawCircle(
              node,
              1.5,
              Paint()
                ..color = light.withValues(
                  alpha: .55 + .35 * math.sin(clock * 3 - i).abs(),
                ),
            );
          }
          final turbine = Offset(side * 21, 7);
          _orb(c, turbine, 5.5, dark);
          for (var i = 0; i < 3; i++) {
            final angle = clock * 3 + i * math.pi * 2 / 3;
            _line(
              c,
              turbine,
              turbine + Offset(math.cos(angle), math.sin(angle)) * 3.5,
              light,
              1.2,
            );
          }
          _rivet(c, Offset(side * 13, -29), brass, radius: 1.4);
          _line(c, Offset(side * 4, -29), Offset(side * 8, -27), light, 1.3);
          for (var i = 0; i < 3; i++) {
            _line(
              c,
              Offset(side * 6, -12.0 + i * 3),
              Offset(side * 11, -14.0 + i * 3),
              color,
              1.1,
            );
          }
        }
        _gem(c, const Offset(0, -32), 3.5, Colors.white);
        _orb(c, const Offset(0, 4), 3, light);
        _plate(
          c,
          const [
            Offset(-6, 52),
            Offset(-1, 57),
            Offset(-6, 64),
            Offset(-10, 60),
          ],
          light,
          width: 1,
        );
      case ArcadeDroneStyle.voidRegent:
        for (final side in [-1.0, 1.0]) {
          final sway = math.sin(clock * 2 + side) * 4;
          _stroke(
            c,
            Path()
              ..moveTo(side * 29, -12)
              ..quadraticBezierTo(side * 27, 17, side * (43 + sway), 40),
            color.withValues(alpha: .65),
            1.3,
          );
          _stroke(
            c,
            Path()
              ..moveTo(side * 33, 20)
              ..lineTo(side * (43 + sway), 41)
              ..lineTo(side * 25, 34),
            brass,
            1,
          );
          for (var i = 0; i < 3; i++) {
            _gem(
              c,
              Offset(side * (29 + i * 3), 6.0 + i * 9),
              i == 1 ? 2.5 : 1.5,
              light,
            );
          }
          final hand = Offset(side * 43, 18 + sway);
          _stroke(
            c,
            Path()..addArc(
              Rect.fromCircle(center: hand, radius: 9),
              clock * .8,
              4.8,
            ),
            brass,
            1,
          );
          _gem(c, hand, 4, Colors.white);
          _line(c, Offset(side * 3, -38), Offset(side * 15, -39), light, 2);
          _gem(c, Offset(side * 14, -48), 3.8, const Color(0xffffe2a1));
          _line(c, Offset(side * 16, -51), Offset(side * 19, -56), light, 1.2);
          _line(c, Offset(side * 9, -18), Offset(side * 6, -13), dark, 1.5);
          _line(c, Offset(side * 6, -4), Offset(side * 17, -12), brass, 1.8);
        }
        _gem(c, const Offset(0, -53), 5.5, Colors.white);
        _line(c, const Offset(-4, -15), const Offset(4, -15), dark, 1.2);
        _stroke(
          c,
          Path()..addOval(const Rect.fromLTWH(-13, -3, 26, 26)),
          brass,
          1,
        );
        for (var i = 0; i < 4; i++) {
          final angle = clock * .45 + i * math.pi / 2;
          _rivet(
            c,
            Offset(math.cos(angle) * 13, 10 + math.sin(angle) * 13),
            light,
            radius: 1.3,
          );
        }
        _gem(c, const Offset(0, 30), 3, brass);
      default:
        break;
    }
  }

  static void _details(Canvas c, ArcadeDroneStyle style, Color color) {
    final light = Color.lerp(color, Colors.white, .4)!;
    for (final side in [-1.0, 1.0]) {
      switch (style) {
        case ArcadeDroneStyle.bramble:
          _line(
            c,
            Offset(side * 17, 38),
            Offset(side * 21, 54),
            color.withValues(alpha: .5),
            1.5,
          );
          _line(c, Offset(side * 16, -9), Offset(side * 20, 0), color, 1.5);
          _plate(
            c,
            [
              Offset(side * 18, 15),
              Offset(side * 27, 9),
              Offset(side * 24, 22),
            ],
            color,
            width: 1,
          );
          _line(c, Offset(side * 32, -18), Offset(side * 38, -24), light, 1);
          _line(c, Offset(side * 21, 60), Offset(side * 28, 55), _ink, 2);
        case ArcadeDroneStyle.duneScorpion:
          _line(c, Offset(side * 43, -22), Offset(side * 49, -24), light, 1.5);
          _orb(c, Offset(side * 30, -12), 2, _eye);
          for (var i = 0; i < 3; i++) {
            c.drawCircle(
              Offset(side * 14, 10.0 + i * 9),
              1.2,
              Paint()..color = _ink,
            );
          }
        case ArcadeDroneStyle.frostWarden:
          _plate(
            c,
            [
              Offset(side * 27, -26),
              Offset(side * 38, -36),
              Offset(side * 40, -13),
            ],
            light,
            width: .6,
          );
          _plate(
            c,
            [
              Offset(side * 39, 0),
              Offset(side * 46, -2),
              Offset(side * 48, 19),
            ],
            color,
            width: .6,
          );
          _line(c, Offset(side * 13, 33), Offset(side * 16, 43), light, 1.5);
          _line(c, Offset(side * 13, 36), Offset(side * 18, 34), light, 1.5);
        case ArcadeDroneStyle.stormRay:
          _line(c, Offset(side * 8, -31), Offset(side * 12, -8), light, 1);
          for (var i = 0; i < 3; i++) {
            _line(
              c,
              Offset(side * (16 + i * 4), 11.0 - i),
              Offset(side * (20 + i * 4), 9.0 - i),
              color,
              1.2,
            );
          }
        case ArcadeDroneStyle.voidRegent:
          _line(
            c,
            Offset(side * 24, -16),
            Offset(side * 28, 13),
            color.withValues(alpha: .7),
            1,
          );
          _line(
            c,
            Offset(side * 28, 13),
            Offset(side * 38, 34),
            color.withValues(alpha: .7),
            1,
          );
          _orb(c, Offset(side * 15, -43), 2, Colors.white);
          _line(c, Offset(side * 12, 1), Offset(side * 15, -5), light, 1);
          _line(c, Offset(side * 12, 18), Offset(side * 8, 24), light, 1);
        default:
          break;
      }
    }
  }

  static void _beetle(Canvas c, Color color, double clock) {
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < 3; i++) {
        final y = -8.0 + i * 10;
        final knee = Offset(side * 27, y - 4 + math.sin(clock * 7 + i) * 2);
        _line(c, Offset(side * 14, y), knee, _ink, 5);
        _line(c, knee, Offset(side * (32 + i), y + 4), color, 2);
      }
      c.drawOval(
        Rect.fromCenter(center: Offset(side * 9, -1), width: 22, height: 36),
        Paint()..color = _ink,
      );
      c.drawOval(
        Rect.fromCenter(center: Offset(side * 9, -2), width: 18, height: 32),
        Paint()..color = side < 0 ? color : Color.lerp(color, _ink, .3)!,
      );
      _line(
        c,
        Offset(side * 9, -13),
        Offset(side * 13, 7),
        color.withValues(alpha: .7),
        2,
      );
      _line(c, Offset(side * 6, -18), Offset(side * 12, -27), color, 2);
      _orb(c, Offset(side * 12, -27), 2, _eye);
    }
    _line(c, const Offset(0, -14), const Offset(0, 15), _ink, 2);
    _gear(c, const Offset(0, 5), 7, color, clock * 2);
    _eyes(c, -12, spacing: 5);
  }

  static void _wasp(Canvas c, Color color, double clock) {
    final flutter = math.sin(clock * 28) * 4;
    for (final side in [-1.0, 1.0]) {
      _plate(
        c,
        [
          Offset(side * 8, -6),
          Offset(side * 34, -24 - flutter),
          Offset(side * 38, -8),
          Offset(side * 18, 4),
        ],
        color.withValues(alpha: .55),
        width: 1,
      );
      _line(c, Offset(side * 13, 6), Offset(side * 24, 13), _ink, 3);
      _line(c, Offset(side * 24, 13), Offset(side * 27, 21), color, 2);
    }
    _plate(c, [
      const Offset(-11, -16),
      const Offset(11, -16),
      const Offset(15, 4),
      const Offset(0, 28),
      const Offset(-15, 4),
    ], color);
    _line(c, const Offset(-12, 3), const Offset(12, 3), _ink, 5);
    _line(c, const Offset(-7, 14), const Offset(7, 14), _ink, 4);
    _eyes(c, -8, spacing: 5);
    _orb(c, const Offset(0, -20), 3, color);
  }

  static void _pulseOrb(Canvas c, Color color, double clock) {
    for (var i = 0; i < 3; i++) {
      c.save();
      c.rotate(clock * .6 + i * math.pi / 3);
      c.drawOval(
        const Rect.fromLTWH(-33, -12, 66, 24),
        Paint()
          ..color = color.withValues(alpha: .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _orb(c, const Offset(30, 0), 3, i.isEven ? color : _eye);
      c.restore();
    }
    _orb(c, Offset.zero, 17, Color.lerp(color, _ink, .6)!);
    _orb(c, const Offset(0, -1), 9, color);
    _line(c, const Offset(-5, 0), const Offset(5, 0), _ink, 3);
    _line(c, const Offset(0, -5), const Offset(0, 5), _ink, 3);
  }

  static void _bramble(Canvas c, Color color, double clock) {
    final bark = Color.lerp(color, const Color(0xff5b3835), .72)!;
    for (final side in [-1.0, 1.0]) {
      final sway = math.sin(clock * 1.8 + side) * 3;
      _plate(c, [
        Offset(side * 10, 23),
        Offset(side * 26, 27),
        Offset(side * 29, 56),
        Offset(side * 40, 60),
        Offset(side * 12, 61),
      ], bark);
      _line(c, Offset(side * 17, -4), Offset(side * 38, -16 + sway), bark, 15);
      _line(
        c,
        Offset(side * 38, -16 + sway),
        Offset(side * 43, 18 + sway),
        bark,
        12,
      );
      for (var i = 0; i < 3; i++) {
        _line(
          c,
          Offset(side * 43, 16 + sway),
          Offset(side * (35 + i * 8), 31 + sway),
          bark,
          4,
        );
      }
      _plate(c, [
        Offset(side * 18, -21),
        Offset(side * 44, -37),
        Offset(side * 35, -15),
        Offset(side * 51, -12),
        Offset(side * 27, 3),
      ], color);
      _line(c, Offset(side * 12, -34), Offset(side * 24, -54), bark, 6);
      _line(c, Offset(side * 24, -54), Offset(side * 40, -60), bark, 4);
      _plate(c, [
        Offset(side * 22, -47),
        Offset(side * 28, -65),
        Offset(side * 39, -51),
      ], color);
    }
    _plate(c, [
      const Offset(-20, -29),
      const Offset(20, -29),
      const Offset(29, 4),
      const Offset(19, 33),
      const Offset(-18, 34),
      const Offset(-29, 4),
    ], bark);
    _plate(c, [
      const Offset(-16, -37),
      const Offset(0, -48),
      const Offset(17, -37),
      const Offset(13, -12),
      const Offset(-12, -12),
    ], color);
    _eyes(c, -28);
    _gear(c, const Offset(0, 7), 14, color, clock * .35);
    _line(c, const Offset(-12, 26), const Offset(-7, 17), color, 2);
    _line(c, const Offset(14, 28), const Offset(10, 20), color, 2);
  }

  static void _scorpion(Canvas c, Color color, double clock) {
    final dark = Color.lerp(color, _ink, .45)!;
    final tail = [
      const Offset(13, 12),
      const Offset(34, -4),
      const Offset(35, -28),
      const Offset(18, -48),
      const Offset(-6, -52),
      const Offset(-17, -40),
    ];
    for (var i = 0; i < tail.length - 1; i++) {
      _line(c, tail[i], tail[i + 1], _ink, 14);
      _line(c, tail[i], tail[i + 1], dark, 10);
      _orb(c, tail[i], 6, color);
    }
    _plate(c, [
      const Offset(-23, -48),
      const Offset(-10, -43),
      const Offset(-12, -25),
      const Offset(-28, -36),
    ], color);
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < 3; i++) {
        final y = 6.0 + i * 10;
        final kick = math.sin(clock * 4 + i + side) * 3;
        _line(
          c,
          Offset(side * 17, y),
          Offset(side * (32 + i * 4), y + 3),
          dark,
          6,
        );
        _line(
          c,
          Offset(side * (32 + i * 4), y + 3),
          Offset(side * (43 + i * 4), y + 17 + kick),
          color,
          4,
        );
      }
      _line(c, Offset(side * 12, -5), Offset(side * 34, -13), dark, 9);
      _plate(c, [
        Offset(side * 33, -25),
        Offset(side * 53, -30),
        Offset(side * 58, -13),
        Offset(side * 49, -3),
        Offset(side * 40, -14),
        Offset(side * 34, -3),
      ], color);
    }
    _plate(c, [
      const Offset(0, -21),
      const Offset(23, -7),
      const Offset(21, 28),
      const Offset(0, 39),
      const Offset(-22, 28),
      const Offset(-23, -7),
    ], dark);
    for (var i = 0; i < 3; i++) {
      _plate(
        c,
        [
          Offset(-18, 3.0 + i * 9),
          Offset(0, 9.0 + i * 9),
          Offset(18, 3.0 + i * 9),
          Offset(16, 11.0 + i * 9),
          Offset(0, 16.0 + i * 9),
          Offset(-16, 11.0 + i * 9),
        ],
        color,
        width: 1,
      );
    }
    _eyes(c, -8);
  }

  static void _frost(Canvas c, Color color, double clock) {
    final shadow = Color.lerp(color, const Color(0xff5366ae), .65)!;
    for (final side in [-1.0, 1.0]) {
      _plate(c, [
        Offset(side * 7, 23),
        Offset(side * 27, 23),
        Offset(side * 32, 57),
        Offset(side * 10, 60),
      ], shadow);
      _plate(c, [
        Offset(side * 20, -29),
        Offset(side * 38, -43),
        Offset(side * 52, -18),
        Offset(side * 43, -5),
        Offset(side * 26, -4),
      ], color);
      _plate(c, [
        Offset(side * 35, -5),
        Offset(side * 49, -8),
        Offset(side * 55, 21),
        Offset(side * 42, 35),
        Offset(side * 30, 18),
      ], shadow);
      _plate(c, [
        Offset(side * 40, -29),
        Offset(side * 43, -58),
        Offset(side * 52, -26),
      ], color);
      _line(c, Offset(side * 16, 31), Offset(side * 18, 50), color, 2);
    }
    _plate(c, [
      const Offset(-23, -23),
      const Offset(23, -23),
      const Offset(28, 7),
      const Offset(14, 34),
      const Offset(-14, 34),
      const Offset(-28, 7),
    ], shadow);
    _plate(c, [
      const Offset(0, -19),
      const Offset(17, 4),
      const Offset(0, 25),
      const Offset(-17, 4),
    ], color);
    _plate(c, [
      const Offset(-17, -25),
      const Offset(-20, -42),
      const Offset(-10, -57),
      const Offset(0, -64),
      const Offset(10, -57),
      const Offset(20, -42),
      const Offset(17, -25),
    ], color);
    _plate(
      c,
      [
        const Offset(-12, -45),
        const Offset(0, -53),
        const Offset(12, -45),
        const Offset(8, -28),
        const Offset(-8, -28),
      ],
      shadow,
      width: 1,
    );
    _eyes(c, -37, spacing: 6);
    _orb(
      c,
      const Offset(0, 3),
      6,
      Colors.white.withValues(alpha: .8 + math.sin(clock * 2) * .15),
    );
  }

  static void _ray(Canvas c, Color color, double clock) {
    final flap = math.sin(clock * 2) * 7;
    final dark = Color.lerp(color, _ink, .5)!;
    final tail = Path()
      ..moveTo(0, 15)
      ..quadraticBezierTo(24 * math.sin(clock * 1.6), 37, -6, 62);
    c.drawPath(
      tail,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    c.drawPath(
      tail,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (final side in [-1.0, 1.0]) {
      _plate(c, [
        Offset(side * 8, -31),
        Offset(side * 40, -42 + flap),
        Offset(side * 60, -13 + flap),
        Offset(side * 45, -17 + flap),
        Offset(side * 54, 7 + flap),
        Offset(side * 25, 20),
        Offset(side * 8, 13),
      ], dark);
      _plate(
        c,
        [
          Offset(side * 15, -19),
          Offset(side * 37, -32 + flap),
          Offset(side * 46, -12 + flap),
          Offset(side * 27, -4),
          Offset(side * 34, 9),
          Offset(side * 13, 7),
        ],
        color,
        width: 1,
      );
      _line(
        c,
        Offset(side * 34, -19 + flap),
        Offset(side * 25, -12 + flap),
        Colors.white,
        2,
      );
      _line(
        c,
        Offset(side * 25, -12 + flap),
        Offset(side * 31, -7 + flap),
        Colors.white,
        2,
      );
    }
    _plate(c, [
      const Offset(0, -42),
      const Offset(17, -19),
      const Offset(12, 20),
      const Offset(0, 29),
      const Offset(-12, 20),
      const Offset(-17, -19),
    ], dark);
    _gear(c, const Offset(0, 4), 10, color, clock * .6);
    _eyes(c, -21, spacing: 7);
  }

  static void _regent(Canvas c, Color color, double clock) {
    final dark = Color.lerp(color, _ink, .65)!;
    c.drawOval(
      const Rect.fromLTWH(-42, -49, 84, 26),
      Paint()
        ..color = color.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final side in [-1.0, 1.0]) {
      final sway = math.sin(clock * 2 + side) * 4;
      _plate(c, [
        Offset(side * 12, -22),
        Offset(side * 31, -20),
        Offset(side * 37, 18),
        Offset(side * (48 + sway), 47),
        Offset(side * 17, 36),
      ], dark);
      _line(c, Offset(side * 27, -8), Offset(side * 39, 11 + sway), color, 5);
      _orb(c, Offset(side * 43, 18 + sway), 7, color);
      _plate(c, [
        Offset(side * 5, 22),
        Offset(side * 17, 27),
        Offset(side * (22 + sway), 60),
        Offset(side * 8, 49),
      ], color);
    }
    _plate(c, [
      const Offset(0, -33),
      const Offset(23, -12),
      const Offset(14, 21),
      const Offset(0, 40),
      const Offset(-14, 21),
      const Offset(-23, -12),
    ], dark);
    _plate(c, [
      const Offset(-18, -34),
      const Offset(-22, -61),
      const Offset(-9, -48),
      const Offset(0, -68),
      const Offset(9, -48),
      const Offset(22, -61),
      const Offset(18, -34),
    ], color);
    _plate(c, [
      const Offset(-14, -32),
      const Offset(14, -32),
      const Offset(10, -12),
      const Offset(0, -6),
      const Offset(-10, -12),
    ], color);
    _eyes(c, -24, spacing: 6, color: Colors.white);
    _orb(c, const Offset(0, 10), 9, color);
    _plate(
      c,
      [
        const Offset(0, 1),
        const Offset(5, 10),
        const Offset(0, 19),
        const Offset(-5, 10),
      ],
      Colors.white,
      width: 1,
    );
  }
}
