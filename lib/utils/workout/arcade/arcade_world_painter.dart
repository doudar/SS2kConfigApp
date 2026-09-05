import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../workout_parser.dart';
import 'arcade_session.dart';
import 'arcade_pedaling.dart';
import 'arcade_road.dart';
import 'arcade_story.dart';
import 'arcade_story_art.dart';
import 'arcade_drones.dart';
import 'arcade_drone_art.dart';
import 'arcade_segment_profile.dart';
import 'arcade_golem_art.dart';
import 'arcade_checkpoint_art.dart';
import 'arcade_cage_art.dart';

const arcadeMint = Color(0xff74ffd3);
const arcadeGold = Color(0xffffd477);
const arcadeInk = Color(0xff080f21);

Color biomeColor(ArcadeBiome biome) => switch (biome) {
  ArcadeBiome.grove => const Color(0xff53d9b0),
  ArcadeBiome.coast => const Color(0xff60cdff),
  ArcadeBiome.neon => const Color(0xffb391ff),
  ArcadeBiome.volcano => const Color(0xffff8068),
};

/// A bounded isometric diorama. Power controls visual travel; the road stretches
/// to keep its sector boundaries aligned with the authoritative workout clock.
class ArcadeWorldPainter extends CustomPainter {
  ArcadeWorldPainter({
    required this.segments,
    required this.road,
    required this.seconds,
    required this.animation,
    required this.biome,
    required this.onTarget,
    required this.charge,
    required this.pedalPhase,
    required this.moving,
    this.story,
    this.drone,
    this.droneFlightBounds,
    this.reducedMotion = false,
    this.escapeSeconds,
    this.showCheckpoints = true,
  });

  final List<WorkoutSegment> segments;
  final ArcadeRoadSnapshot road;
  final double seconds;
  final double animation;
  final ArcadeBiome biome;
  final bool onTarget;
  final double charge;
  final double pedalPhase;
  final bool moving;
  final ArcadeStoryFrame? story;
  final ArcadeDroneFrame? drone;
  final Rect? droneFlightBounds;
  final bool reducedMotion;
  // Accepted workout time plus the existing bounded frame interpolation.
  // Null before the opening or for an endless ride with no destination.
  final double? escapeSeconds;
  final bool showCheckpoints;

  double? get _escapeDuration {
    final time = escapeSeconds;
    if (time == null || !time.isFinite || time < 0) return null;
    for (final segment in segments) {
      if (segment.duration <= 0) continue;
      // A workout starting with a boss goes straight into its aimable battle.
      // Fifteen seconds on the road, then a brief distant hillside escape.
      final duration = math.min(segment.duration.toDouble(), 23.0);
      if (time >= duration || biomeFor(segment) == ArcadeBiome.volcano) {
        return null;
      }
      return duration;
    }
    return null;
  }

  Color get accent => biomeColor(biome);
  late final double _heightScale =
      1.6 /
      segments.fold<double>(
        1.6,
        (peak, segment) => math.max(
          peak,
          math.max(
            arcadeSegmentPower(segment, 0),
            arcadeSegmentPower(segment, 1),
          ),
        ),
      );
  double _roadHeight(double power) =>
      12 + math.max(0, power) * 22 * _heightScale;

  double _scaleFor(Size size) => math
      .min(
        size.width / 650,
        size.height / (size.height < 260 && size.width > 550 ? 300 : 380),
      )
      .clamp(.35, 1.8);
  Offset _originFor(Size size) {
    final short = size.height < 260 && size.width > 550;
    return Offset(
      size.width * (short ? .56 : .43),
      size.height * (short ? .72 : .60),
    );
  }

  double get _riderHeight => _roadHeight(
    road.spans.isEmpty
        ? .5
        : arcadeSegmentPower(
            road.spans[road.currentIndex].segment,
            road.currentProgress,
          ),
  );

  ArcadeDroneLayout? droneLayout(Size size) {
    final frame = drone;
    if (frame == null || !frame.visible || size.isEmpty) return null;
    final scale = _scaleFor(size);
    final origin = _originFor(size);
    return ArcadeDroneLayout(
      size: size,
      frame: frame,
      worldOrigin: origin,
      muzzle: origin + Offset(22, -_riderHeight - 37) * scale,
      scale: scale,
      reducedMotion: reducedMotion,
      flightBounds: droneFlightBounds,
    );
  }

  void _polygon(Canvas canvas, List<Offset> points, Color color) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color);
  }

  void _line(Canvas canvas, Offset a, Offset b, Color color, double width) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  Offset _iso(double u, double v, [double h = 0]) =>
      Offset((u - v) * 39, (u + v) * 18 - h);

  void _block(
    Canvas canvas,
    double u,
    double v,
    double width,
    double depth,
    double height,
    Color color,
  ) {
    final a = _iso(u, v, height), b = _iso(u + width, v, height);
    final c = _iso(u + width, v + depth, height),
        d = _iso(u, v + depth, height);
    _polygon(canvas, [
      b,
      c,
      _iso(u + width, v + depth),
      _iso(u + width, v),
    ], Color.lerp(color, Colors.black, .62)!);
    _polygon(canvas, [
      c,
      d,
      _iso(u, v + depth),
      _iso(u + width, v + depth),
    ], Color.lerp(color, Colors.black, .38)!);
    _polygon(canvas, [a, b, c, d], color);
    _line(canvas, d, c, color.withValues(alpha: .55), 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xff10182f),
            Color.lerp(arcadeInk, accent, .12)!,
            arcadeInk,
          ],
        ).createShader(Offset.zero & size),
    );

    // Deterministic stars; no allocations of random worlds on animation frames.
    for (var i = 0; i < 64; i++) {
      final x = ((i * 137.51) % 997) / 997 * size.width;
      final y = ((i * 73.31) % 419) / 419 * size.height * .74;
      canvas.drawCircle(
        Offset(x, y),
        i % 7 == 0 ? 1.6 : .8,
        Paint()..color = Colors.white.withValues(alpha: .15 + (i % 4) * .09),
      );
    }
    final moon = Offset(size.width * .79, size.height * .23);
    canvas.drawCircle(
      moon,
      47,
      Paint()..color = accent.withValues(alpha: .045),
    );
    canvas.drawCircle(
      moon,
      33,
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: .55),
            accent.withValues(alpha: .04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromCircle(center: moon, radius: 33)),
    );
    canvas.save();
    canvas.translate(moon.dx, moon.dy);
    canvas.rotate(-.35);
    canvas.drawOval(
      const Rect.fromLTWH(-60, -13, 120, 26),
      Paint()
        ..color = accent.withValues(alpha: .30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
    _workoutHills(canvas, size);

    final scale = _scaleFor(size);
    final worldOrigin = _originFor(size);
    canvas.translate(worldOrigin.dx, worldOrigin.dy);
    canvas.scale(scale);
    // Ride towards upper-right: negative longitudinal coordinates are ahead.
    canvas.scale(-1, 1);
    final position = road.position;
    final fraction = position - position.floor();
    // Continue the road to the viewport edge, including wide desktop windows.
    final aheadTiles = math.max(
      12,
      math
          .min(
            ((size.width - worldOrigin.dx) / scale + 120) / 39,
            (worldOrigin.dy / scale + 120) / 18,
          )
          .ceil(),
    );
    for (var tile = -aheadTiles; tile <= 11; tile++) {
      final u = tile + fraction;
      final worldEnd = (position.floor() - tile).toDouble();
      final segment = road.segmentAt(worldEnd - .5);
      final tileBiome = segment == null ? biome : biomeFor(segment);
      final color = biomeColor(tileBiome);
      final base = _roadHeight(road.powerAt(worldEnd - .5));
      for (final piece
          in road.pieces(worldEnd - 1, worldEnd).toList().reversed) {
        _roadSurface(
          canvas,
          position - piece.end,
          piece.end - piece.start,
          piece,
        );
      }
      final seed = position.floor() - tile;
      if (seed % 3 == 0) {
        _block(
          canvas,
          u,
          -3.3,
          1.4,
          1.3,
          base - 3,
          Color.lerp(color, arcadeInk, .6)!,
        );
        final p = _iso(u + .5, -2.8, base);
        if (tileBiome == ArcadeBiome.grove || tileBiome == ArcadeBiome.coast) {
          _tree(canvas, p, color, seed % 2 == 0 ? 1 : .7);
        } else {
          _crystal(canvas, p, color, 35 + seed.abs() % 35);
        }
      }
      if (seed % 4 == 0) {
        _block(
          canvas,
          u,
          2.5,
          1,
          1,
          base - 5,
          Color.lerp(color, arcadeInk, .65)!,
        );
        final p = _iso(u + .4, 2.9, base);
        _crystal(canvas, p, color, 22);
        // Falling light beneath floating islands.
        _line(
          canvas,
          p + const Offset(0, 35),
          p + const Offset(0, 92),
          color.withValues(alpha: .12),
          3,
        );
      }
      if (tile < -1 && tile > -9 && seed % 2 == 0) {
        final p = _iso(
          u + .4,
          .1,
          base + 18 + math.sin(animation * 2 + tile) * 3,
        );
        _polygon(canvas, [
          p + const Offset(0, -7),
          p + const Offset(5, 0),
          p + const Offset(0, 7),
          p + const Offset(-5, 0),
        ], arcadeGold);
        canvas.drawCircle(
          p,
          11,
          Paint()..color = arcadeGold.withValues(alpha: .06),
        );
      }
    }
    _checkpoints(canvas, passed: false);
    // Threats are generated from the active workout sector.
    final chapter = story;
    if (chapter != null &&
        chapter.phase != ArcadeStoryPhase.chase &&
        (biome != ArcadeBiome.volcano || charge >= 1)) {
      final p = _iso(-4.8, 0, 65);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.scale(-.8, .8);
      ArcadeStoryArt.encounter(canvas, chapter, animation);
      canvas.restore();
    } else if (biome == ArcadeBiome.volcano &&
        charge < 1 &&
        !(drone?.isBoss ?? false)) {
      // Idle preview only. Active bosses use the shared aimable combat layer.
      final boss = _iso(-4.5, 0, 70 + math.sin(animation * 2) * 5);
      _boss(canvas, boss);
    }
    final riderHeight = _riderHeight;
    _getaway(canvas, size);
    _cyclist(canvas, _iso(0, 0, riderHeight));
    _checkpoints(canvas, passed: true);
    canvas.restore();
    final targetDrone = drone;
    final layout = droneLayout(size);
    if (targetDrone != null && layout != null) {
      // Screen-space flight paths begin beyond the actual viewport edge.
      ArcadeDroneArt.paint(
        canvas,
        size,
        targetDrone,
        layout: layout,
        reducedMotion: reducedMotion,
      );
    }
  }

  void _checkpoints(Canvas canvas, {required bool passed}) {
    if (!showCheckpoints || road.spans.isEmpty) return;
    // Only visit nearby sectors. Their endpoints come from the exact snapshot
    // used to split road tiles, so power changes stretch road and gates together.
    var first = road.currentIndex;
    while (first > 0 && road.spans[first - 1].end >= road.position - 7) {
      first--;
    }
    var last = road.currentIndex;
    while (last + 1 < road.spans.length &&
        road.spans[last + 1].end <= road.position + 12) {
      last++;
    }
    for (var i = last; i >= first; i--) {
      final span = road.spans[i];
      final u = road.position - span.end;
      if (span.segment.duration <= 0 ||
          span.length <= .01 ||
          u < -12 ||
          u > 7 ||
          (u > 0) != passed)
        continue;
      var nextIndex = i + 1;
      while (nextIndex < road.spans.length &&
          road.spans[nextIndex].segment.duration <= 0) {
        nextIndex++;
      }
      final next = nextIndex < road.spans.length
          ? road.spans[nextIndex].segment
          : null;
      final color = next == null ? arcadeGold : biomeColor(biomeFor(next));
      final height =
          _roadHeight(
            math.max(
              arcadeSegmentPower(span.segment, 1),
              next == null ? 0 : arcadeSegmentPower(next, 0),
            ),
          ) +
          1;
      ArcadeCheckpointArt.paint(
        canvas,
        farFoot: _iso(u, -1.3, height),
        nearFoot: _iso(u, 1.3, height),
        color: color,
        title: next == null ? 'FINISH' : 'CHECKPOINT ${i + 1}',
        target: next == null
            ? 'BRING IT HOME'
            : 'NEXT ${arcadeTargetLabel(next, 1, percent: true)}',
        finish: next == null,
      );
    }
  }

  void _getaway(Canvas canvas, Size size) {
    final duration = _escapeDuration;
    if (duration == null) return;
    final progress = escapeSeconds! / math.min(15.0, duration);
    if (progress >= 1) return;
    final worldScale = _scaleFor(size);
    final origin = _originFor(size);
    // Run beyond the first viewport edge reached by the road. Margins include
    // the trailing cage, so the entire convoy clears the edge before removal.
    const towDistance = 2.6;
    final rightExit =
        ((size.width - origin.dx) / worldScale + 65) / 39 + towDistance;
    final topExit = (origin.dy / worldScale + 20) / 18 + towDistance;
    final exit = math.max(4.0, math.min(rightExit, topExit)) + .5;
    final ahead = 4.0 + (exit - 4.0) * Curves.easeInQuad.transform(progress);
    final feet = _iso(
      -ahead,
      0,
      _roadHeight(road.powerAt(road.position + ahead)),
    );
    final cageFeet = _iso(
      -ahead + towDistance,
      0,
      _roadHeight(road.powerAt(road.position + ahead - towDistance)),
    );
    final tint = ArcadeStoryArt.color(story?.story.variant ?? 0);
    final clock = reducedMotion ? 0.0 : escapeSeconds!;
    final hand = ArcadeGolemArt.runningHand(clock, -1);
    ArcadeCageArt.chain(
      canvas,
      cageFeet + const Offset(-35.7, -16.1),
      feet + Offset(-hand.dx, hand.dy - 56) * .62,
      const Color(0xffa2819b),
    );
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    // Undo the world's reflection so the runner faces the same way as the bike.
    canvas.scale(-.62, .62);
    ArcadeGolemArt.paint(canvas, const Offset(0, -56), clock, running: true);
    canvas.restore();
    canvas.save();
    canvas.translate(cageFeet.dx, cageFeet.dy);
    canvas.scale(-.7, .7);
    ArcadeCageArt.paint(canvas, Offset.zero, tint, front: false);
    for (var i = 0; i < 3; i++) {
      ArcadeStoryArt.person(
        canvas,
        Offset(-30 + i * 30, 0),
        Color.lerp(tint, ArcadeStoryArt.mint, i * .25)!,
        cheer: .05,
      );
    }
    ArcadeCageArt.paint(canvas, Offset.zero, tint, front: true);
    ArcadeStoryArt.relic(
      canvas,
      const Offset(3, -78),
      story?.story.variant ?? 0,
    );
    canvas.restore();
  }

  /// A miniature route through the whole workout: duration determines width,
  /// prescribed FTP determines height. Beveled shoulders turn interval blocks
  /// into hills while preserving their order, relative height and ramp direction.
  void _workoutHills(Canvas canvas, Size size) {
    final route = segments.where((segment) => segment.duration > 0).toList();
    if (route.isEmpty) return;
    final duration = route.fold<double>(0, (sum, s) => sum + s.duration);
    double intensity(WorkoutSegment segment, double progress) {
      // A free ride has no prescribed ERG height; give it a low, quiet ridge.
      if (segment.type == SegmentType.freeRide) return .45;
      final start = segment.type == SegmentType.cooldown
          ? segment.powerHigh
          : segment.powerLow;
      final end = segment.type == SegmentType.cooldown
          ? segment.powerLow
          : segment.powerHigh;
      final power = segment.isRamp
          ? start + (end - start) * progress
          : segment.powerLow;
      return power.isFinite ? power.clamp(0.0, 6.0) : 0;
    }

    // The x coordinates stay on the workout clock, independent of the dynamic
    // foreground road. Skips, pauses and restarts therefore share its progress.
    final profile = <Offset>[Offset(0, intensity(route.first, 0))];
    var elapsed = 0.0;
    var peak = 1.5;
    for (final segment in route) {
      for (final t in const [.12, .5, .88]) {
        final power = intensity(segment, t);
        final height = power * (t == .5 && !segment.isRamp ? 1.04 : 1.0);
        peak = math.max(peak, height);
        profile.add(
          Offset((elapsed + segment.duration * t) / duration, height),
        );
      }
      elapsed += segment.duration;
    }
    profile.add(Offset(1, intensity(route.last, 1)));
    peak = math.max(peak, math.max(profile.first.dy, profile.last.dy));

    // Insets keep the tiny rider visible at the very start and finish.
    final margin = math.min(14.0, size.width * .04);
    Offset project(Offset point, int layer) => Offset(
      margin + point.dx * (size.width - margin * 2),
      size.height * (.38 + layer * .05) -
          point.dy / peak * size.height * (.14 + layer * .02),
    );
    for (var layer = 0; layer < 3; layer++) {
      final first = project(profile.first, layer);
      final last = project(profile.last, layer);
      final silhouette = Path()..moveTo(0, first.dy);
      for (final point in profile) {
        final p = project(point, layer);
        silhouette.lineTo(p.dx, p.dy);
      }
      silhouette
        ..lineTo(size.width, last.dy)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        silhouette,
        Paint()..color = Color.lerp(arcadeInk, accent, .045 + layer * .025)!,
      );
    }

    final ridge = profile.map((p) => project(p, 2)).toList();
    final outline = Path()..addPolygon(ridge, false);
    canvas.drawPath(
      outline,
      Paint()
        ..color = accent.withValues(alpha: .20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final progress = seconds.isFinite
        ? (seconds / duration).clamp(0.0, 1.0)
        : 0.0;
    final x = margin + progress * (size.width - margin * 2);
    var edge = 1;
    while (edge < ridge.length - 1 && ridge[edge].dx < x) edge++;
    final a = ridge[edge - 1], b = ridge[edge];
    final fraction = b.dx > a.dx
        ? ((x - a.dx) / (b.dx - a.dx)).clamp(0.0, 1.0)
        : 0.0;
    final rider = Offset.lerp(a, b, fraction)!;
    final traveled = Path()..moveTo(ridge.first.dx, ridge.first.dy);
    for (var i = 1; i < edge; i++) {
      traveled.lineTo(ridge[i].dx, ridge[i].dy);
    }
    traveled.lineTo(rider.dx, rider.dy);
    canvas.drawPath(
      traveled,
      Paint()
        ..color = arcadeGold.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
    _horizonRider(canvas, rider, math.atan2(b.dy - a.dy, b.dx - a.dx));
    final escapeDuration = _escapeDuration;
    if (escapeDuration != null && escapeDuration > 15 && escapeSeconds! >= 15) {
      // After the convoy exits, a brief silhouette crosses the distant hills.
      // Only the hero draws a traveled path.
      final run = ((escapeSeconds! - 15) / (escapeDuration - 15)).clamp(
        0.0,
        1.0,
      );
      final lead = progress + (1 - progress) * (.12 + .88 * run);
      final monsterX = margin + lead * (size.width - margin * 2);
      var monsterEdge = 1;
      while (monsterEdge < ridge.length - 1 &&
          ridge[monsterEdge].dx < monsterX) {
        monsterEdge++;
      }
      final start = ridge[monsterEdge - 1], end = ridge[monsterEdge];
      final t = end.dx > start.dx
          ? ((monsterX - start.dx) / (end.dx - start.dx)).clamp(0.0, 1.0)
          : 0.0;
      final opacity =
          (run / .15).clamp(0.0, 1.0) * ((1 - run) / .15).clamp(0.0, 1.0);
      ArcadeGolemArt.runningOutline(
        canvas,
        Offset.lerp(start, end, t)!,
        reducedMotion ? 0 : escapeSeconds!,
        const Color(0xffff666f).withValues(alpha: opacity),
        slope: math.atan2(end.dy - start.dy, end.dx - start.dx),
      );
    }
  }

  void _horizonRider(Canvas canvas, Offset position, double slope) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.drawCircle(
      const Offset(0, -6),
      13,
      Paint()
        ..shader = RadialGradient(
          colors: [
            arcadeGold.withValues(alpha: .18),
            arcadeGold.withValues(alpha: 0),
          ],
        ).createShader(const Rect.fromLTWH(-13, -19, 26, 26)),
    );
    canvas.rotate(slope.clamp(-.5, .5));
    final stroke = Paint()
      ..color = arcadeGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(const Offset(-5, -2.5), 2.5, stroke);
    canvas.drawCircle(const Offset(5, -2.5), 2.5, stroke);
    _line(canvas, const Offset(-5, -2.5), const Offset(-1, -6), arcadeGold, 1);
    _line(canvas, const Offset(-1, -6), const Offset(1, -2.5), arcadeGold, 1);
    _line(canvas, const Offset(1, -2.5), const Offset(-5, -2.5), arcadeGold, 1);
    _line(canvas, const Offset(1, -2.5), const Offset(3, -6), arcadeGold, 1);
    _line(canvas, const Offset(3, -6), const Offset(5, -2.5), arcadeGold, 1);
    _line(canvas, const Offset(-1, -6), const Offset(3, -6), arcadeGold, 1);
    _line(
      canvas,
      const Offset(-1, -6),
      const Offset(-2, -9),
      Colors.white,
      1.3,
    );
    _line(
      canvas,
      const Offset(-2, -9),
      const Offset(1, -11),
      Colors.white,
      1.3,
    );
    _line(canvas, const Offset(1, -11), const Offset(3, -6), Colors.white, 1);
    canvas.drawCircle(const Offset(1.5, -13), 1.7, Paint()..color = arcadeGold);
    canvas.restore();
  }

  void _roadSurface(
    Canvas canvas,
    double u,
    double width,
    ArcadeRoadPiece piece,
  ) {
    final segment = piece.segment;
    final color = biomeColor(biomeFor(segment));
    // The tile starts at its later power; increasing u runs back in time.
    final frontHeight = _roadHeight(piece.endPower);
    final backHeight = _roadHeight(piece.startPower);
    double height(double fraction) =>
        frontHeight + (backHeight - frontHeight) * fraction;
    final surfaceWidth = math.max(width - .012, width * .96);
    final a = _iso(u, -1.2, frontHeight);
    final b = _iso(u + surfaceWidth, -1.2, height(surfaceWidth / width));
    final c = _iso(u + surfaceWidth, 1.2, height(surfaceWidth / width));
    final d = _iso(u, 1.2, frontHeight);
    final surfaceColor = Color.lerp(color, const Color(0xff182239), .68)!;
    _polygon(canvas, [
      b,
      c,
      _iso(u + surfaceWidth, 1.2),
      _iso(u + surfaceWidth, -1.2),
    ], Color.lerp(surfaceColor, Colors.black, .62)!);
    _polygon(canvas, [
      c,
      d,
      _iso(u, 1.2),
      _iso(u + surfaceWidth, 1.2),
    ], Color.lerp(surfaceColor, Colors.black, .38)!);
    _polygon(canvas, [a, b, c, d], surfaceColor);
    for (final side in [-1.15, 1.15]) {
      _line(
        canvas,
        _iso(u, side, frontHeight + 1),
        _iso(u + surfaceWidth, side, height(surfaceWidth / width) + 1),
        color,
        2,
      );
    }
    _line(
      canvas,
      _iso(u + width * .18, 0, height(.18) + 1),
      _iso(u + width * .65, 0, height(.65) + 1),
      Colors.white.withValues(alpha: .35),
      2,
    );
  }

  void _tree(Canvas c, Offset p, Color color, double scale) {
    _line(c, p, p + Offset(0, -30 * scale), const Color(0xff82677a), 5);
    for (var i = 0; i < 3; i++) {
      final y = p.dy - 13 * scale - i * 14 * scale;
      _polygon(c, [
        Offset(p.dx, y - 28 * scale),
        Offset(p.dx + 20 * scale, y),
        Offset(p.dx - 20 * scale, y),
      ], Color.lerp(color, arcadeInk, i * .14)!);
    }
  }

  void _crystal(Canvas c, Offset p, Color color, num height) {
    _polygon(c, [
      p,
      p + const Offset(-11, -9),
      p + Offset(-3, -height.toDouble()),
      p + const Offset(10, -10),
    ], color.withValues(alpha: .85));
    _polygon(c, [
      p,
      p + Offset(-3, -height.toDouble()),
      p + const Offset(10, -10),
    ], Color.lerp(color, Colors.white, .25)!);
  }

  void _boss(Canvas c, Offset p) {
    ArcadeGolemArt.paint(c, p, animation, damage: charge);
  }

  void _cyclist(Canvas c, Offset p) {
    c.save();
    c.translate(p.dx, p.dy);
    // Undo world mirroring so rider leans toward the destination.
    c.scale(-1, 1);
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
      const Color(0xff6d63a5),
      const Color(0xff9eaeca),
    );
    _line(c, crank, pose.farPedal, const Color(0xff9aaac3), 2.5);
    _shoe(c, pose.farPedal, const Color(0xffa8b7d0));
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
      _line(c, pair[0], pair[1], arcadeMint, 3);
    }
    _line(c, stem, const Offset(18, -37), Colors.white, 3);
    _line(c, const Offset(11, -37), const Offset(22, -37), Colors.white, 3);
    _line(
      c,
      seat + const Offset(-6, -2),
      seat + const Offset(5, -2),
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
    _leg(
      c,
      pose.hip,
      pose.nearKnee,
      pose.nearPedal,
      const Color(0xffb391ff),
      const Color(0xffdce5ff),
    );
    _shoe(c, pose.nearPedal, arcadeGold);
    _line(c, pose.hip, const Offset(2, -59), const Color(0xffa78aff), 12);
    _line(
      c,
      const Offset(3, -55),
      const Offset(14, -41),
      const Color(0xffffc69b),
      4,
    );
    _line(
      c,
      const Offset(14, -41),
      const Offset(21, -37),
      const Color(0xffffc69b),
      4,
    );
    c.drawCircle(
      const Offset(10, -68),
      9,
      Paint()..color = const Color(0xffffc69b),
    );
    c.drawArc(
      const Rect.fromLTWH(0, -79, 22, 20),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = arcadeGold
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke,
    );
    _line(
      c,
      const Offset(14, -69),
      const Offset(21, -70),
      const Color(0xff152036),
      3,
    );
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

  void _leg(
    Canvas c,
    Offset hip,
    Offset knee,
    Offset pedal,
    Color shorts,
    Color shin,
  ) {
    _line(c, hip, knee, shorts, 6);
    c.drawCircle(knee, 2.8, Paint()..color = shin);
    _line(c, knee, pedal, shin, 4);
  }

  void _shoe(Canvas c, Offset pedal, Color color) {
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

  @override
  bool shouldRepaint(covariant ArcadeWorldPainter oldDelegate) => true;
}
