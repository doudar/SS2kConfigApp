import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_story.dart';
import 'arcade_golem_art.dart';
import 'arcade_cage_art.dart';

/// Small canvas actors shared by the roadside story and the final celebration.
class ArcadeStoryArt {
  static const gold = Color(0xffffd477);
  static const mint = Color(0xff74ffd3);
  static const ink = Color(0xff10182f);
  static const standingHeroHead = Offset(1, -51);

  static Offset dismountHead(Offset bike, double progress) => Offset.lerp(
    bike + const Offset(3, -57),
    bike + const Offset(23, 0) + standingHeroHead,
    Curves.easeInOut.transform(progress.clamp(0.0, 1.0)),
  )!;

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
    bool speaking = false,
    double clock = 0,
    bool hero = false,
  }) {
    c.save();
    c.translate(feet.dx, feet.dy - hop);
    final hipY = hero ? -27.0 : -15.0;
    final shoulderY = hero ? -43.0 : -28.0;
    final head = hero ? standingHeroHead : const Offset(0, -35);
    line(
      c,
      const Offset(-4, 0),
      Offset(-2, hipY),
      hero ? const Color(0xff736ba5) : ink,
      4,
    );
    if (hero) {
      final knee = Offset(2.5, hipY / 2);
      line(c, Offset(0, hipY), knee, const Color(0xffb391ff), 5);
      line(c, knee, const Offset(5, 0), Colors.white, 3);
    } else {
      line(c, const Offset(5, 0), Offset(1, hipY), ink, 4);
    }
    line(c, Offset(0, hipY + 1), Offset(0, shoulderY), shirt, 9);
    for (final side in [-1.0, 1.0]) {
      line(
        c,
        Offset(side * 3, shoulderY + 3),
        Offset(side * 12, shoulderY + 8 - cheer * 20),
        shirt,
        3,
      );
    }
    c.drawCircle(head, 6, Paint()..color = const Color(0xffffc69b));
    _face(c, head, speaking, clock);
    c.drawArc(
      Rect.fromCircle(center: head, radius: 7),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = hero ? gold : shirt
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    c.restore();
  }

  static void _face(Canvas c, Offset head, bool speaking, double clock) {
    for (final x in [-2.0, 2.0]) {
      c.drawCircle(head + Offset(x, -1), .7, Paint()..color = ink);
    }
    c.drawOval(
      Rect.fromCenter(
        center: head + const Offset(0, 2.4),
        width: 3,
        height: speaking ? 1.4 + (math.sin(clock * 18) + 1) : 1,
      ),
      Paint()..color = ink,
    );
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
    const saddle = Offset(-12, -34);
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
    // Exposed seatpost above the seat tube, with the saddle above the head tube.
    line(c, seat, saddle, const Color(0xffb5c5dc), 2);
    line(
      c,
      saddle - const Offset(4, 0),
      saddle + const Offset(4, 0),
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
  static void dismount(
    Canvas c,
    Offset bike,
    double progress,
    double phase, {
    bool speaking = false,
  }) {
    final t = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final hip = Offset.lerp(
      bike + const Offset(-11, -39),
      bike + const Offset(23, -27),
      t,
    )!;
    final shoulder = Offset.lerp(
      bike + const Offset(2, -49),
      bike + const Offset(23, -43),
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
    // The pedaling knee bend disappears as the rider stands beside the bike.
    final knee = Offset.lerp(hip, nearFoot, .5)! + Offset(7 * (1 - t), 0);
    line(c, hip, knee, const Color(0xffb391ff), 5);
    line(c, knee, nearFoot, Colors.white, 3);
    line(c, hip, shoulder, const Color(0xffb391ff), 9);
    final hand = Offset.lerp(
      bike + const Offset(11, -34),
      shoulder + const Offset(10, 9),
      t,
    )!;
    line(c, shoulder, hand, const Color(0xffffc69b), 3);
    final head = dismountHead(bike, progress);
    c.drawCircle(head, 6, Paint()..color = const Color(0xffffc69b));
    _face(c, head, speaking, phase / 6);
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

  static void golem(
    Canvas c,
    Offset p,
    double clock, {
    bool speaking = false,
    bool running = false,
  }) {
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(.62);
    ArcadeGolemArt.paint(
      c,
      Offset.zero,
      clock,
      speaking: speaking,
      running: running,
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

  static void encounter(
    Canvas c,
    ArcadeStoryFrame frame,
    double clock, {
    bool speaking = false,
    bool crewSpeaking = false,
    bool running = false,
  }) {
    final tint = color(frame.story.variant);
    final opening = frame.phase == ArcadeStoryPhase.opening;
    final captured = opening && frame.progress >= .28;
    final escape = captured
        ? ((frame.progress - .65) / .35).clamp(0.0, 1.0)
        : 0.0;
    c.save();
    c.translate(escape * 180, -escape * 30);
    if (captured) {
      ArcadeCageArt.paint(c, const Offset(0, 8), tint, front: false);
    }
    for (var i = 0; i < 3; i++) {
      person(
        c,
        Offset(-28 + i * 24, 8),
        Color.lerp(tint, mint, i * .25)!,
        cheer: opening ? .15 : .8,
        hop: captured ? 0 : math.max(0, math.sin(clock * 3 + i)) * 3,
        speaking: crewSpeaking && i == 1,
        clock: clock,
      );
    }
    if (captured) {
      ArcadeCageArt.paint(c, const Offset(0, 8), tint, front: true);
      relic(c, const Offset(-3, -76), frame.story.variant);
      ArcadeCageArt.chain(
        c,
        const Offset(51, -15),
        const Offset(65, -10),
        const Color(0xffa2819b),
      );
      golem(
        c,
        const Offset(88, -18),
        clock,
        speaking: speaking,
        running: running,
      );
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
