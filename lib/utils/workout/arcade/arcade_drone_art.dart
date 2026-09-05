import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_drones.dart';
import 'arcade_golem_art.dart';

/// The same pose drives drawing and pointer hit testing, including reduced
/// motion, viewport scaling, banking and the interpolated workout clock.
class ArcadeDroneLayout {
  ArcadeDroneLayout({
    required this.size,
    required this.frame,
    required Offset worldOrigin,
    required this.muzzle,
    required double scale,
    required bool reducedMotion,
    Rect? flightBounds,
  }) {
    bodyScale = frame.isBoss
        ? scale.clamp(.4, 1.5)
        : (scale * 1.1).clamp(.72, 1.6);
    final bounds = flightBounds ?? (Offset.zero & size);
    double fit(double value, double low, double high) =>
        low <= high ? value.clamp(low, high) : (low + high) / 2;
    Offset hover(double clock) {
      final p =
          worldOrigin +
          Offset(
                164 + frame.hoverX + math.sin(clock * 1.6 + frame.serial) * 18,
                -135 + frame.hoverY + math.sin(clock * 2.3) * 8,
              ) *
              scale;
      return Offset(
        fit(
          p.dx,
          bounds.left + (frame.isBoss ? 64 : 46) * bodyScale,
          bounds.right - (frame.isBoss ? 64 : 46) * bodyScale,
        ),
        fit(
          p.dy,
          bounds.top + (frame.isBoss ? 76 : 32) * bodyScale,
          bounds.bottom - (frame.isBoss ? 62 : 32) * bodyScale,
        ),
      );
    }

    final entry = switch (frame.entrySide) {
      0 => Offset(size.width + 80 * bodyScale, size.height * .35),
      1 => Offset(size.width * .68, -80 * bodyScale),
      _ => Offset(-80 * bodyScale, size.height * .3),
    };
    Offset approach(double progress, double clock) {
      final end = hover(clock);
      final control = Offset(
        frame.entrySide == 2 ? size.width * .1 : size.width * .9,
        end.dy - 85 * bodyScale,
      );
      final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
      return entry * ((1 - t) * (1 - t)) +
          control * (2 * (1 - t) * t) +
          end * (t * t);
    }

    final locked =
        frame.phase == ArcadeDronePhase.firing ||
        frame.phase == ArcadeDronePhase.exploding;
    position = hover(locked ? frame.lockClock : frame.clock);
    bank = math.sin(frame.clock * 1.6) * .09;
    if (frame.phase == ArcadeDronePhase.entering) {
      position = approach(frame.age / ArcadeDrones.entrySeconds, frame.clock);
      bank = -.3 * (1 - frame.age / ArcadeDrones.entrySeconds);
    } else if (frame.phase == ArcadeDronePhase.departing && !frame.isBoss) {
      final t = Curves.easeInCubic.transform(
        (frame.age / ArcadeDrones.departureSeconds).clamp(0.0, 1.0),
      );
      position = Offset.lerp(
        approach(frame.departureEntry, frame.lockClock),
        Offset(size.width + 100 * bodyScale, -70 * bodyScale),
        t,
      )!;
      bank = -.4 * t;
    }
    if (reducedMotion) {
      position = hover(0);
      bank = 0;
    }
    if (frame.isBoss) bank = 0;
  }
  final Size size;
  final ArcadeDroneFrame frame;
  final Offset muzzle;
  late final double bodyScale;
  late Offset position;
  late double bank;

  bool contains(Offset tap) {
    final p = tap - position;
    final x = p.dx * math.cos(bank) + p.dy * math.sin(bank);
    final y = -p.dx * math.sin(bank) + p.dy * math.cos(bank);
    // Include the rotor housings and antennae, with a small touch allowance.
    return math.pow(x / ((frame.isBoss ? 64 : 43) * bodyScale + 4), 2) +
            math.pow(y / ((frame.isBoss ? 70 : 30) * bodyScale + 4), 2) <=
        1;
  }

  Offset missEndpoint(Offset tap) {
    var direction = tap - muzzle;
    if (direction.distance < 1) direction = const Offset(0, -1);
    return muzzle + direction / direction.distance * size.longestSide * 1.6;
  }
}

class ArcadeDroneArt {
  static const mint = Color(0xff74ffd3);
  static const gold = Color(0xffffd477);
  static const ink = Color(0xff10182f);

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
    Size size,
    ArcadeDroneFrame frame, {
    required ArcadeDroneLayout layout,
    required bool reducedMotion,
  }) {
    if (!frame.visible || size.isEmpty) return;
    final tint = frame.isBoss
        ? const Color(0xffff9760)
        : frame.style == ArcadeDroneStyle.sentinel
        ? const Color(0xffbc9aff)
        : const Color(0xff72d7ff);
    final bodyScale = layout.bodyScale;
    final position = layout.position;
    final bank = layout.bank;
    final muzzle = layout.muzzle;
    c.save();
    c.clipRect(Offset.zero & size);

    if (frame.phase == ArcadeDronePhase.entering ||
        frame.phase == ArcadeDronePhase.hovering ||
        frame.ready) {
      // Six illuminated segments around the handlebar emitter show earned energy.
      for (var i = 0; i < 6; i++) {
        c.drawArc(
          Rect.fromCircle(center: muzzle, radius: 11 * bodyScale),
          -math.pi / 2 + i * math.pi / 3,
          math.pi / 4,
          false,
          Paint()
            ..color = (frame.charge * 6 >= i + 1
                ? mint
                : mint.withValues(alpha: .16))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * bodyScale,
        );
      }
      c.drawCircle(
        muzzle,
        (2 + frame.charge * 3) * bodyScale,
        Paint()..color = mint.withValues(alpha: .4 + frame.charge * .6),
      );
      if ((frame.phase == ArcadeDronePhase.hovering || frame.ready) &&
          frame.charge > .3) {
        // A faint targeting line makes the rider-to-drone relationship explicit.
        for (var i = 0; i < 12; i++) {
          final t = i / 12;
          _line(
            c,
            Offset.lerp(muzzle, position, t)!,
            Offset.lerp(muzzle, position, t + .025)!,
            mint.withValues(alpha: frame.charge * .24),
            1,
          );
        }
        final r = ((frame.isBoss ? 76 : 44) - frame.charge * 5) * bodyScale;
        for (var i = 0; i < 4; i++) {
          c.drawArc(
            Rect.fromCircle(center: position, radius: r),
            i * math.pi / 2 + .2,
            .35,
            false,
            Paint()
              ..color = mint.withValues(alpha: frame.charge * .8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 * bodyScale,
          );
        }
      }
    }

    if (frame.ready) {
      c.drawArc(
        Rect.fromCircle(
          center: position,
          radius: (frame.isBoss ? 76 : 46) * bodyScale,
        ),
        -math.pi / 2,
        math.pi * 2 * frame.secondsLeft / ArcadeDrones.readySeconds,
        false,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    if (frame.phase == ArcadeDronePhase.firing) {
      final t = (frame.age / ArcadeDrones.shotSeconds).clamp(0.0, 1.0);
      final aim = frame.shotHit
          ? position
          : Offset(frame.aimX * size.width, frame.aimY * size.height);
      final head = reducedMotion ? aim : Offset.lerp(muzzle, aim, t)!;
      final tail = reducedMotion
          ? muzzle
          : Offset.lerp(muzzle, aim, math.max(0, t - .23))!;
      _line(c, tail, head, mint.withValues(alpha: .16), 13 * bodyScale);
      _line(c, tail, head, mint, 4 * bodyScale);
      _line(c, tail, head, Colors.white, 1.5 * bodyScale);
      c.drawCircle(head, 5 * bodyScale, Paint()..color = Colors.white);
      c.drawCircle(
        muzzle,
        (4 + (1 - t) * 8) * bodyScale,
        Paint()..color = mint.withValues(alpha: (1 - t) * .5),
      );
    }

    if (frame.phase == ArcadeDronePhase.departing && frame.stolePoints) {
      // Coins zip from the rider toward the escaping thief; scoring happens
      // once in the session, never in this animation.
      for (var i = 0; i < 3; i++) {
        final t = reducedMotion
            ? .65
            : ((frame.age / ArcadeDrones.departureSeconds) * 1.5 - i * .13)
                  .clamp(0.0, 1.0);
        if (t <= 0 || t >= 1) continue;
        final coin = Offset.lerp(muzzle, position, t)!;
        c.drawCircle(coin, 4 * bodyScale, Paint()..color = gold);
        _line(
          c,
          coin - Offset(0, 2 * bodyScale),
          coin + Offset(0, 2 * bodyScale),
          ink,
          1.5,
        );
      }
    }

    if (frame.isBoss &&
        frame.phase == ArcadeDronePhase.exploding &&
        !frame.defeated) {
      // A landed hit cracks armor but leaves the boss in place for the next shot.
      c.drawCircle(
        position,
        26 * bodyScale,
        Paint()..color = gold.withValues(alpha: .2),
      );
    }
    if (frame.phase == ArcadeDronePhase.exploding &&
        (!frame.isBoss || frame.defeated)) {
      final t = (frame.age / ArcadeDrones.explosionSeconds).clamp(0.0, 1.0);
      if (reducedMotion) {
        c.drawCircle(
          position,
          22 * bodyScale,
          Paint()..color = gold.withValues(alpha: .4),
        );
        for (var i = 0; i < 4; i++) {
          final d = Offset(
            math.cos(i * math.pi / 2),
            math.sin(i * math.pi / 2),
          );
          _line(
            c,
            position + d * 9 * bodyScale,
            position + d * 27 * bodyScale,
            gold,
            3,
          );
        }
      } else {
        c.drawCircle(
          position,
          (8 + t * 58) * bodyScale,
          Paint()
            ..color = gold.withValues(alpha: (1 - t) * .85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (1 - t) * 4 * bodyScale,
        );
        c.drawCircle(
          position,
          (1 - t) * 27 * bodyScale,
          Paint()
            ..shader =
                RadialGradient(
                  colors: [Colors.white, gold.withValues(alpha: 0)],
                ).createShader(
                  Rect.fromCircle(
                    center: position,
                    radius: math.max(1, (1 - t) * 27 * bodyScale),
                  ),
                ),
        );
        for (var i = 0; i < 18; i++) {
          final angle = i * math.pi * 2 / 18 + frame.serial * .7;
          final velocity =
              Offset(math.cos(angle), math.sin(angle)) * (35 + i % 4 * 12);
          final p =
              position + (velocity * t + Offset(0, 40 * t * t)) * bodyScale;
          c.save();
          c.translate(p.dx, p.dy);
          c.rotate(angle + t * (i.isEven ? 5 : -4));
          if (i % 3 == 0) {
            c.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(
                  center: Offset.zero,
                  width: 9 * bodyScale,
                  height: 4 * bodyScale,
                ),
                const Radius.circular(1),
              ),
              Paint()..color = tint.withValues(alpha: 1 - t),
            );
          } else {
            c.drawCircle(
              Offset.zero,
              (2 + i % 2) * bodyScale,
              Paint()
                ..color = (i.isEven ? gold : mint).withValues(alpha: 1 - t),
            );
          }
          c.restore();
        }
      }
    } else {
      c.save();
      c.translate(position.dx, position.dy);
      c.scale(bodyScale);
      c.rotate(bank);
      if (frame.isBoss) {
        ArcadeGolemArt.paint(
          c,
          Offset.zero,
          reducedMotion ? 0 : frame.clock,
          damage: frame.damage,
          firing: !reducedMotion && frame.phase == ArcadeDronePhase.exploding,
          speaking:
              frame.phase == ArcadeDronePhase.departing && frame.stolePoints,
        );
      } else {
        _body(c, frame.style, tint, reducedMotion ? 0 : frame.clock);
      }
      c.restore();
    }
    c.restore();
  }

  static void _body(
    Canvas c,
    ArcadeDroneStyle style,
    Color tint,
    double clock,
  ) {
    final sentinel = style == ArcadeDroneStyle.sentinel;
    // Wheel-like ducted fans: hubs, spokes, tread marks and articulated arms.
    for (final side in [-1.0, 1.0]) {
      final hub = Offset(side * 28, -5);
      _line(c, Offset(side * 9, 0), hub, const Color(0xff53647f), 6);
      _line(
        c,
        Offset(side * 9, -2),
        hub - const Offset(0, 2),
        tint.withValues(alpha: .6),
        1,
      );
      c.drawOval(
        Rect.fromCenter(
          center: hub + const Offset(0, 16),
          width: 14,
          height: 30 + math.sin(clock * 22) * 4,
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tint.withValues(alpha: .4), tint.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(hub.dx - 7, hub.dy + 5, 14, 30)),
      );
      c.drawCircle(hub, 12, Paint()..color = ink);
      c.drawCircle(
        hub,
        11,
        Paint()
          ..color = tint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      for (var i = 0; i < 8; i++) {
        final angle = clock * 15 * side + i * math.pi / 4;
        final d = Offset(math.cos(angle), math.sin(angle));
        _line(c, hub + d * 3, hub + d * 8, tint.withValues(alpha: .6), 1.4);
        _line(c, hub + d * 12, hub + d * 13.5, const Color(0xff7e8da7), 1.3);
      }
      c.drawCircle(hub, 3, Paint()..color = const Color(0xffdce5ff));
      c.drawCircle(hub + const Offset(0, -14), 2, Paint()..color = gold);
    }
    final body = Path()
      ..addPolygon([
        const Offset(-19, -9),
        Offset(sentinel ? -10 : -13, sentinel ? -20 : -15),
        Offset(sentinel ? 10 : 13, sentinel ? -20 : -15),
        const Offset(19, -9),
        const Offset(16, 11),
        const Offset(7, 18),
        const Offset(-7, 18),
        const Offset(-16, 11),
      ], true);
    c.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(tint, Colors.white, .15)!,
            const Color(0xff26354f),
          ],
        ).createShader(const Rect.fromLTWH(-19, -20, 38, 38)),
    );
    c.drawPath(
      body,
      Paint()
        ..color = tint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-14, -9, 28, 15),
        const Radius.circular(7),
      ),
      Paint()..color = ink,
    );
    final eye = Offset(math.sin(clock * 1.6) * 3, -2);
    c.drawCircle(
      eye,
      6,
      Paint()..color = const Color(0xffff8068).withValues(alpha: .22),
    );
    c.drawCircle(eye, 3.5, Paint()..color = const Color(0xffff8068));
    c.drawCircle(eye + const Offset(-1, -1), 1, Paint()..color = Colors.white);
    for (var i = 0; i < 3; i++) {
      _line(c, Offset(-5 + i * 5, 9), Offset(-5 + i * 5, 12), tint, 1);
    }
    for (final side in [-1.0, 1.0]) {
      c.drawCircle(Offset(side * 13, 8), 1.5, Paint()..color = gold);
      _line(
        c,
        Offset(side * 8, -16),
        Offset(side * (sentinel ? 15 : 10), -27),
        tint,
        1.5,
      );
      c.drawCircle(
        Offset(side * (sentinel ? 15 : 10), -27),
        2.2,
        Paint()
          ..color = gold.withValues(alpha: .65 + math.sin(clock * 4) * .25),
      );
    }
  }
}
