import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_story.dart';

/// Small canvas actors shared by the roadside story and the final celebration.
class ArcadeStoryArt {
  static const gold = Color(0xffffd477);
  static const mint = Color(0xff74ffd3);
  static const ink = Color(0xff10182f);

  static Color color(int variant) => const [
    Color(0xffffce73),
    Color(0xff81dfff),
    Color(0xffff9bbd),
  ][variant % 3];

  static void line(
    Canvas c,
    Offset a,
    Offset b,
    Color color, [
    double width = 3,
  ]) {
    c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  static void person(
    Canvas c,
    Offset feet,
    Color shirt, {
    double cheer = 0,
    double hop = 0,
  }) {
    c.save();
    c.translate(feet.dx, feet.dy - hop);
    line(c, const Offset(-4, 0), const Offset(-2, -15), ink, 4);
    line(c, const Offset(5, 0), const Offset(1, -15), ink, 4);
    line(c, const Offset(0, -14), const Offset(0, -28), shirt, 9);
    for (final side in [-1.0, 1.0]) {
      line(
        c,
        Offset(side * 3, -25),
        Offset(side * 12, -20 - cheer * 20),
        shirt,
        3,
      );
    }
    c.drawCircle(
      const Offset(0, -35),
      6,
      Paint()..color = const Color(0xffffc69b),
    );
    c.drawArc(
      const Rect.fromLTWH(-7, -42, 14, 14),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = shirt
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    c.restore();
  }

  static void bicycle(Canvas c, Offset p, {double phase = 0}) {
    c.save();
    c.translate(p.dx, p.dy);
    final wheelPaint = Paint()
      ..color = mint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final x in [-17.0, 17.0]) {
      c.drawCircle(Offset(x, -10), 10, Paint()..color = ink);
      c.drawCircle(Offset(x, -10), 10, wheelPaint);
      for (var i = 0; i < 3; i++) {
        final d =
            Offset(
              math.cos(phase + i * math.pi / 3),
              math.sin(phase + i * math.pi / 3),
            ) *
            8;
        line(c, Offset(x, -10) - d, Offset(x, -10) + d, Colors.white30, 1);
      }
    }
    const rear = Offset(-17, -10),
        front = Offset(17, -10),
        crank = Offset(0, -10);
    const seat = Offset(-8, -26), stem = Offset(10, -28);
    for (final pair in [
      [rear, seat],
      [seat, crank],
      [crank, rear],
      [seat, stem],
      [stem, crank],
      [stem, front],
    ]) {
      line(c, pair[0], pair[1], mint, 2);
    }
    line(
      c,
      seat - const Offset(4, 0),
      seat + const Offset(4, 0),
      Colors.white,
      2,
    );
    line(c, stem, stem + const Offset(0, -6), Colors.white, 2);
    line(
      c,
      stem + const Offset(-3, -6),
      stem + const Offset(5, -6),
      Colors.white,
      2,
    );
    c.restore();
  }

  /// Interpolate the cyclist off the saddle onto the ground, then stand upright.
  static void dismount(Canvas c, Offset bike, double progress, double phase) {
    final t = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final hip = Offset.lerp(
      bike + const Offset(-7, -34),
      bike + const Offset(23, -16),
      t,
    )!;
    final shoulder = Offset.lerp(
      bike + const Offset(2, -49),
      bike + const Offset(23, -30),
      t,
    )!;
    final nearFoot = Offset.lerp(
      bike + Offset(math.cos(phase) * 7, -10 + math.sin(phase) * 7),
      bike + const Offset(28, 0),
      t,
    )!;
    final farFoot = Offset.lerp(
      bike + Offset(-math.cos(phase) * 7, -10 - math.sin(phase) * 7),
      bike + const Offset(18, 0),
      t,
    )!;
    line(c, hip, farFoot, const Color(0xff736ba5), 4);
    bicycle(c, bike, phase: phase);
    line(
      c,
      hip,
      Offset.lerp(hip, nearFoot, .5)! + const Offset(7, 0),
      const Color(0xffb391ff),
      5,
    );
    line(
      c,
      Offset.lerp(hip, nearFoot, .5)! + const Offset(7, 0),
      nearFoot,
      Colors.white,
      3,
    );
    line(c, hip, shoulder, const Color(0xffb391ff), 9);
    final hand = Offset.lerp(
      bike + const Offset(11, -34),
      shoulder + const Offset(10, 9),
      t,
    )!;
    line(c, shoulder, hand, const Color(0xffffc69b), 3);
    final head = shoulder + const Offset(1, -8);
    c.drawCircle(head, 6, Paint()..color = const Color(0xffffc69b));
    c.drawArc(
      Rect.fromCircle(center: head, radius: 7),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  static void golem(Canvas c, Offset p, double clock) {
    c.save();
    c.translate(p.dx, p.dy);
    final teeth = <Offset>[];
    for (var i = 0; i < 48; i++) {
      final angle = i * math.pi / 24 + clock * .2;
      final r = i % 4 < 2 ? 25.0 : 31.0;
      teeth.add(Offset(math.cos(angle) * r, math.sin(angle) * r));
    }
    c.drawPath(
      Path()..addPolygon(teeth, true),
      Paint()..color = const Color(0xff995472),
    );
    c.drawCircle(Offset.zero, 21, Paint()..color = ink);
    line(c, const Offset(-12, -5), const Offset(-4, -2), gold, 3);
    line(c, const Offset(4, -2), const Offset(12, -5), gold, 3);
    line(
      c,
      const Offset(-6, 10),
      const Offset(6, 10),
      const Color(0xffff8068),
      3,
    );
    c.restore();
  }

  static void relic(Canvas c, Offset p, int variant) {
    c.save();
    c.translate(p.dx, p.dy);
    final tint = color(variant);
    c.drawCircle(
      Offset.zero,
      21,
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withValues(alpha: .35), tint.withValues(alpha: 0)],
        ).createShader(const Rect.fromLTWH(-21, -21, 42, 42)),
    );
    final stroke = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    switch (variant % 3) {
      case 0:
        c.drawCircle(Offset.zero, 7, Paint()..color = gold);
        for (var i = 0; i < 8; i++) {
          final ray = Offset(
            math.cos(i * math.pi / 4),
            math.sin(i * math.pi / 4),
          );
          line(c, ray * 11, ray * 15, gold, 2);
        }
      case 1:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-8, -11, 16, 22),
            const Radius.circular(3),
          ),
          stroke,
        );
        c.drawCircle(Offset.zero, 4, Paint()..color = Colors.white);
        line(c, const Offset(-5, -12), const Offset(0, -17), tint, 2);
        line(c, const Offset(0, -17), const Offset(5, -12), tint, 2);
      default:
        for (final x in [-8.0, 8.0]) {
          c.drawCircle(Offset(x, 0), 8, stroke);
          line(c, Offset(x - 6, -4), Offset(x + 6, 4), tint, 1);
          line(c, Offset(x - 6, 4), Offset(x + 6, -4), tint, 1);
        }
    }
    c.restore();
  }

  static void encounter(Canvas c, ArcadeStoryFrame frame, double clock) {
    final tint = color(frame.story.variant);
    final opening = frame.phase == ArcadeStoryPhase.opening;
    final captured = opening && frame.progress >= .28;
    final escape = captured
        ? ((frame.progress - .65) / .35).clamp(0.0, 1.0)
        : 0.0;
    c.save();
    c.translate(escape * 180, -escape * 30);
    for (var i = 0; i < 3; i++) {
      person(
        c,
        Offset(-28 + i * 24, 8),
        Color.lerp(tint, mint, i * .25)!,
        cheer: opening ? .15 : .8,
        hop: captured ? 0 : math.max(0, math.sin(clock * 3 + i)) * 3,
      );
    }
    if (captured) {
      relic(c, const Offset(-3, -64), frame.story.variant);
      final cage = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-43, -48, 82, 60),
        const Radius.circular(12),
      );
      c.drawRRect(cage, Paint()..color = tint.withValues(alpha: .12));
      c.drawRRect(
        cage,
        Paint()
          ..color = tint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      for (var i = 0; i < 5; i++) {
        line(
          c,
          Offset(-32 + i * 16, -43),
          Offset(-32 + i * 16, 9),
          tint.withValues(alpha: .65),
          1.5,
        );
      }
      line(c, const Offset(40, -10), const Offset(65, -10), tint, 2);
      golem(c, const Offset(88, -18), clock);
      for (var i = 0; i < 6; i++) {
        final t = (clock * .3 + i / 6) % 1;
        c.drawCircle(
          Offset(-45 - t * 40, 5 + math.sin(i * 2) * 9),
          (1 - t) * 3,
          Paint()..color = gold.withValues(alpha: 1 - t),
        );
      }
    }
    c.restore();
  }
}
