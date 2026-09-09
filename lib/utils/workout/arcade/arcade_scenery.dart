import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'arcade_session.dart';

enum ArcadeSceneryKind {
  pine,
  broadleaf,
  birch,
  mushroom,
  palm,
  reeds,
  coral,
  antenna,
  crystal,
  ruin,
  vent,
  basalt,
  rabbit,
}

/// Spatially seeded decorations stay attached to their islands as power changes.
/// No Random instances, particles, assets, timers or growing world caches.
class ArcadeScenery {
  static int seed(int tile, [int salt = 0]) {
    var value = (tile * 374761393 + salt * 668265263) & 0x7fffffff;
    value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff;
    return value ^ (value >> 16);
  }

  /// Every 90 travelled tiles reveals another layer of the same sector.
  /// This uses distance from the fixed sector entry, not its power forecast.
  static int depth(double distanceFromEntry) => distanceFromEntry.isFinite
      ? (math.max(0, distanceFromEntry) / 90).floor().clamp(0, 2)
      : 0;

  static ArcadeSceneryKind kind({
    required ArcadeBiome biome,
    required int tile,
    required int side,
    required int depth,
    required int levelIndex,
  }) {
    final value = seed(tile, side);
    if ((biome == ArcadeBiome.grove || biome == ArcadeBiome.coast) &&
        value % 53 == 0)
      return ArcadeSceneryKind.rabbit;
    // The world has a recognizable flora/architecture even at recovery power.
    if (levelIndex > 0 && value.isEven) {
      final landmark = switch (levelIndex.clamp(1, 5)) {
        1 => const [
          ArcadeSceneryKind.birch,
          ArcadeSceneryKind.ruin,
          ArcadeSceneryKind.mushroom,
        ],
        2 => const [
          ArcadeSceneryKind.palm,
          ArcadeSceneryKind.basalt,
          ArcadeSceneryKind.ruin,
        ],
        3 => const [
          ArcadeSceneryKind.pine,
          ArcadeSceneryKind.crystal,
          ArcadeSceneryKind.birch,
        ],
        4 => const [
          ArcadeSceneryKind.antenna,
          ArcadeSceneryKind.crystal,
          ArcadeSceneryKind.ruin,
        ],
        _ => const [
          ArcadeSceneryKind.coral,
          ArcadeSceneryKind.ruin,
          ArcadeSceneryKind.crystal,
        ],
      };
      return landmark[(value ~/ 2 + depth) % landmark.length];
    }
    final choices = switch (biome) {
      ArcadeBiome.grove => const [
        ArcadeSceneryKind.pine,
        ArcadeSceneryKind.broadleaf,
        ArcadeSceneryKind.birch,
        ArcadeSceneryKind.mushroom,
        ArcadeSceneryKind.ruin,
      ],
      ArcadeBiome.coast => const [
        ArcadeSceneryKind.palm,
        ArcadeSceneryKind.reeds,
        ArcadeSceneryKind.broadleaf,
        ArcadeSceneryKind.coral,
        ArcadeSceneryKind.ruin,
      ],
      ArcadeBiome.neon => const [
        ArcadeSceneryKind.crystal,
        ArcadeSceneryKind.antenna,
        ArcadeSceneryKind.mushroom,
        ArcadeSceneryKind.ruin,
        ArcadeSceneryKind.coral,
      ],
      ArcadeBiome.volcano => const [
        ArcadeSceneryKind.basalt,
        ArcadeSceneryKind.vent,
        ArcadeSceneryKind.crystal,
        ArcadeSceneryKind.ruin,
        ArcadeSceneryKind.antenna,
      ],
    };
    final count = (3 + depth).clamp(3, choices.length);
    return choices[(value + levelIndex * 7) % count];
  }

  static void paint(
    Canvas canvas,
    Offset foot, {
    required ArcadeSceneryKind kind,
    required Color accent,
    required int variant,
    double animation = 0,
    bool reducedMotion = false,
    int levelIndex = 0,
  }) {
    final c = canvas;
    c.save();
    c.translate(foot.dx, foot.dy);
    final scale = .65 + (variant % 5) * .08;
    c.scale(scale);
    final shade = Color.lerp(accent, const Color(0xff17263e), .5)!;
    final light = Color.lerp(accent, Colors.white, .3)!;
    const bark = Color(0xff9b8799);
    void line(Offset a, Offset b, Color color, double width) => c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    void poly(List<Offset> points, Color color) =>
        c.drawPath(Path()..addPolygon(points, true), Paint()..color = color);
    void oval(Rect rect, Color color) =>
        c.drawOval(rect, Paint()..color = color);
    void crystal(double x, double height) {
      poly([
        Offset(x, 0),
        Offset(x - 9, -8),
        Offset(x - 2, -height),
        Offset(x + 8, -9),
      ], shade);
      poly([Offset(x, 0), Offset(x - 2, -height), Offset(x + 8, -9)], light);
    }

    oval(
      const Rect.fromLTWH(-20, -4, 40, 9),
      Colors.black.withValues(alpha: .2),
    );
    switch (kind) {
      case ArcadeSceneryKind.pine:
        line(Offset.zero, const Offset(0, -63), bark, 5);
        for (var i = 0; i < 3; i++) {
          final y = -15.0 - i * 16;
          final width = 23.0 - i * 4;
          poly([
            Offset(0, y - 30),
            Offset(width, y),
            Offset(-width, y),
          ], i == 1 ? accent : shade);
          line(Offset(0, y - 27), Offset(width * .65, y - 6), light, 1.5);
          if (levelIndex == 3) {
            poly([
              Offset(0, y - 30),
              Offset(8, y - 18),
              Offset(-8, y - 18),
            ], const Color(0xffeef8ff));
          }
        }
      case ArcadeSceneryKind.broadleaf:
        line(Offset.zero, const Offset(2, -43), bark, 6);
        line(const Offset(1, -22), const Offset(-15, -37), bark, 3);
        line(const Offset(1, -28), const Offset(19, -45), bark, 3);
        oval(const Rect.fromLTWH(-31, -63, 41, 34), shade);
        oval(const Rect.fromLTWH(0, -71, 38, 40), accent);
        oval(const Rect.fromLTWH(-19, -83, 39, 43), accent);
        oval(const Rect.fromLTWH(-15, -78, 25, 12), light);
        for (var i = 0; i < 3; i++) {
          c.drawCircle(
            Offset(-18 + i * 16, -45 - (i % 2) * 14),
            2.5,
            Paint()..color = const Color(0xffffd477),
          );
        }
      case ArcadeSceneryKind.birch:
        for (var i = 0; i < 2; i++) {
          final x = -8.0 + i * 16;
          line(
            Offset(x, 0),
            Offset(x + 3, -62 + i * 9),
            const Color(0xffd4ddd9),
            4,
          );
          for (var j = 0; j < 4; j++) {
            line(
              Offset(x - 1, -9.0 - j * 11),
              Offset(x + 2, -10.0 - j * 11),
              shade,
              2,
            );
          }
          oval(
            Rect.fromLTWH(x - 12, -80 + i * 8, 29, 44),
            i == 0 ? shade : accent,
          );
          line(Offset(x, -71 + i * 8), Offset(x + 6, -73 + i * 8), light, 2);
        }
      case ArcadeSceneryKind.mushroom:
        for (var i = 0; i < 3; i++) {
          final x = -18.0 + i * 18;
          final h = i == 1 ? 38.0 : 21.0;
          line(Offset(x, 0), Offset(x, -h), const Color(0xffc7c3df), 5);
          c.drawPath(
            Path()
              ..moveTo(x - h * .6, -h)
              ..quadraticBezierTo(x, -h * 2, x + h * .6, -h)
              ..close(),
            Paint()..color = i == 1 ? accent : shade,
          );
          line(Offset(x - h * .5, -h), Offset(x + h * .5, -h), light, 2);
          c.drawCircle(Offset(x - 3, -h - 6), 2, Paint()..color = light);
        }
      case ArcadeSceneryKind.palm:
        final trunk = Path()
          ..moveTo(-5, 0)
          ..quadraticBezierTo(10, -24, 4, -55);
        c.drawPath(
          trunk,
          Paint()
            ..color = bark
            ..strokeWidth = 6
            ..style = PaintingStyle.stroke,
        );
        for (var i = 0; i < 5; i++) {
          final x = -36.0 + i * 18;
          final y = -48.0 - (2 - (i - 2).abs()) * 12;
          c.drawPath(
            Path()
              ..moveTo(4, -55)
              ..quadraticBezierTo(x * .5, y - 20, x, y)
              ..quadraticBezierTo(x * .55, y - 6, 4, -55),
            Paint()..color = i.isEven ? accent : shade,
          );
        }
        c.drawCircle(
          const Offset(1, -53),
          4,
          Paint()..color = const Color(0xffffd477),
        );
      case ArcadeSceneryKind.reeds:
        for (var i = 0; i < 6; i++) {
          final x = -18.0 + i * 7;
          final height = 19.0 + (variant + i * 13) % 26;
          line(
            Offset(x, 0),
            Offset(x + (i.isEven ? 3 : -4), -height),
            shade,
            2,
          );
          line(Offset(x, -height + 5), Offset(x, -height - 3), light, 3);
        }
        oval(const Rect.fromLTWH(-23, -2, 45, 6), accent.withValues(alpha: .4));
      case ArcadeSceneryKind.coral:
        for (var i = 0; i < 3; i++) {
          final x = -14.0 + i * 14;
          final height = 20.0 + (i == 1 ? 18 : 0);
          line(Offset(x, 0), Offset(x, -height), accent, 5);
          line(Offset(x, -height + 10), Offset(x - 7, -height + 3), accent, 4);
          line(Offset(x, -height + 13), Offset(x + 8, -height + 6), shade, 4);
          c.drawCircle(Offset(x, -height), 3, Paint()..color = light);
        }
      case ArcadeSceneryKind.antenna:
        poly(const [
          Offset(-12, 0),
          Offset(12, 0),
          Offset(7, -10),
          Offset(-7, -10),
        ], shade);
        line(const Offset(0, -6), const Offset(0, -63), accent, 3);
        line(const Offset(-16, -44), const Offset(16, -44), shade, 3);
        line(const Offset(-11, -54), const Offset(11, -54), shade, 3);
        c.drawCircle(const Offset(0, -65), 4, Paint()..color = light);
        c.drawCircle(
          const Offset(0, -65),
          8,
          Paint()..color = accent.withValues(alpha: .12),
        );
      case ArcadeSceneryKind.crystal:
        crystal(-14, 26);
        crystal(12, 35);
        crystal(0, 54 + (variant % 3) * 8.0);
      case ArcadeSceneryKind.ruin:
        for (var i = 0; i < 2; i++) {
          final x = -23.0 + i * 35;
          final height = i == 0 ? 46.0 : 31.0;
          poly([
            Offset(x, 0),
            Offset(x + 12, 3),
            Offset(x + 12, -height),
            Offset(x, -height - 4),
          ], shade);
          poly([
            Offset(x + 12, 3),
            Offset(x + 20, -2),
            Offset(x + 20, -height - 5),
            Offset(x + 12, -height),
          ], accent);
          line(
            Offset(x + 4, -height + 8),
            Offset(x + 8, -height + 15),
            light,
            2,
          );
        }
        poly(const [
          Offset(-26, -48),
          Offset(-4, -43),
          Offset(5, -48),
          Offset(-18, -55),
        ], accent);
        oval(const Rect.fromLTWH(-8, -3, 18, 6), shade);
      case ArcadeSceneryKind.vent:
        poly(const [
          Offset(-23, 0),
          Offset(-14, -18),
          Offset(9, -24),
          Offset(23, -3),
          Offset(6, 4),
        ], shade);
        oval(const Rect.fromLTWH(-10, -24, 23, 9), const Color(0xffffa16c));
        for (var i = 0; i < 2; i++) {
          final drift = reducedMotion ? 0.0 : math.sin(animation * .7 + i) * 3;
          oval(
            Rect.fromLTWH(-8 + drift + i * 4, -39.0 - i * 13, 18 + i * 5.0, 12),
            accent.withValues(alpha: .14 - i * .04),
          );
        }
      case ArcadeSceneryKind.basalt:
        for (var i = 0; i < 3; i++) {
          final x = -21.0 + i * 15;
          final height = 22.0 + (variant + i * 11) % 32;
          poly([
            Offset(x, 0),
            Offset(x + 12, 3),
            Offset(x + 12, -height),
            Offset(x, -height - 3),
          ], shade);
          poly([
            Offset(x + 12, 3),
            Offset(x + 19, -3),
            Offset(x + 19, -height - 7),
            Offset(x + 12, -height),
          ], Color.lerp(shade, Colors.black, .25)!);
          line(
            Offset(x + 2, -height + 3),
            Offset(x + 10, -height + 5),
            accent,
            2,
          );
        }
      case ArcadeSceneryKind.rabbit:
        // A rare island resident; its small idle hop never crosses the road.
        final hop = reducedMotion
            ? 0.0
            : math.max(0.0, math.sin(animation * 3 + variant)) * 3;
        c.translate(0, -hop);
        const fur = Color(0xffdfd9ed);
        oval(const Rect.fromLTWH(-12, -14, 23, 15), fur);
        c.drawCircle(const Offset(11, -15), 7, Paint()..color = fur);
        oval(const Rect.fromLTWH(7, -34, 5, 17), fur);
        oval(const Rect.fromLTWH(13, -31, 5, 15), fur);
        line(
          const Offset(10, -29),
          const Offset(10, -21),
          const Color(0xffce96b0),
          2,
        );
        c.drawCircle(
          const Offset(14, -17),
          1.4,
          Paint()..color = const Color(0xff17263e),
        );
        c.drawCircle(const Offset(-13, -9), 4, Paint()..color = Colors.white);
        line(const Offset(4, -1), const Offset(14, -1), fur, 4);
    }
    c.restore();
  }
}

enum ArcadeAmbientKind { birds, plane }

class ArcadeAmbientFrame {
  const ArcadeAmbientFrame(
    this.kind,
    this.progress,
    this.reverse,
    this.variant,
  );
  final ArcadeAmbientKind kind;
  final double progress;
  final bool reverse;
  final int variant;
}

/// At most one five-to-nine-second sky visitor in each 58-second window.
/// The workout clock naturally freezes encounters on pause and hidden scenes.
class ArcadeAmbient {
  static ArcadeAmbientFrame? at(double seconds, {bool reducedMotion = false}) {
    if (reducedMotion || !seconds.isFinite || seconds < 0) return null;
    final window = (seconds / 58).floor();
    final seed = ArcadeScenery.seed(window, 97);
    final offset = seconds - window * 58 - (18 + seed % 18);
    final plane = window % 3 == 2;
    final duration = plane ? 9.0 : 6.0;
    if (offset < 0 || offset >= duration) return null;
    return ArcadeAmbientFrame(
      plane ? ArcadeAmbientKind.plane : ArcadeAmbientKind.birds,
      offset / duration,
      seed.isEven,
      seed % 3,
    );
  }

  static void paint(Canvas canvas, Size size, ArcadeAmbientFrame? frame) {
    if (frame == null) return;
    final progress = frame.reverse ? 1 - frame.progress : frame.progress;
    final p = Offset(
      -55 + progress * (size.width + 110),
      size.height * (.19 + frame.variant * .035) +
          math.sin(frame.progress * math.pi) * 10,
    );
    canvas.save();
    canvas.translate(p.dx, p.dy);
    if (frame.reverse) canvas.scale(-1, 1);
    final ink = Paint()..color = const Color(0xffa5bbd5);
    if (frame.kind == ArcadeAmbientKind.birds) {
      ink
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final x = -i * 12.0;
        final y = i.isEven ? 0.0 : -8.0;
        final wing = math.sin(frame.progress * 42 + i) * 4;
        canvas.drawPath(
          Path()
            ..moveTo(x - 6, y + wing)
            ..quadraticBezierTo(x - 2, y - 2, x, y)
            ..quadraticBezierTo(x + 2, y - 2, x + 6, y + wing),
          ink,
        );
      }
    } else {
      canvas.drawPath(
        Path()..addPolygon(const [
          Offset(-24, 1),
          Offset(-32, -9),
          Offset(-26, -10),
          Offset(-15, -2),
          Offset(0, -2),
          Offset(-5, -16),
          Offset(1, -16),
          Offset(13, -2),
          Offset(28, 0),
          Offset(31, 4),
          Offset(9, 6),
          Offset(-4, 17),
          Offset(-10, 17),
          Offset(-3, 5),
          Offset(-24, 4),
        ], true),
        ink,
      );
      canvas.drawLine(
        const Offset(17, 1),
        const Offset(24, 2),
        Paint()
          ..color = const Color(0xff405571)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        const Offset(8, 7),
        1.5,
        Paint()..color = const Color(0xffffd477),
      );
    }
    canvas.restore();
  }
}
