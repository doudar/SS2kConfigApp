import 'dart:math' as math;
import 'arcade_road.dart';
import 'arcade_segment_profile.dart';

/// Cheap, deterministic relief sampled on the existing road polygons.
/// Distance is the integrated road coordinate, never a timer or a forecast
/// segment length: pausing and changing power cannot regenerate the hills.
class ArcadeTerrain {
  static double relief(double distance, {bool reducedMotion = false}) {
    if (reducedMotion || !distance.isFinite) return 14;
    // Two broad wavelengths avoid an obvious repeating series of speed bumps.
    // The maximum grade is 2.64 height units per tile, below the isometric
    // road's 18-unit longitudinal drop, so hills never fold back on themselves.
    return 14 + 10 * math.sin(distance * .14) + 4 * math.sin(distance * .31);
  }

  static double height(
    double power,
    double distance,
    double heightScale, {
    bool reducedMotion = false,
  }) {
    final intensity = power.isFinite && heightScale.isFinite
        ? (power * heightScale).clamp(0.0, 1.6)
        : 0.0;
    return 12 + intensity * 34 + relief(distance, reducedMotion: reducedMotion);
  }
}

/// A continuous visual surface, independent of the instantaneous ERG target.
/// Every interval starts at the preceding road's actual ending elevation.
class ArcadeTerrainProfile {
  ArcadeTerrainProfile(
    this.road,
    this.heightScale, {
    this.reducedMotion = false,
  });
  final ArcadeRoadSnapshot road;
  final double heightScale;
  final bool reducedMotion;
  late final List<double> _entryHeights = _entries();
  late final int _firstRoad = road.spans.indexWhere(
    (span) => span.segment.duration > 0,
  );

  double _base(double power) =>
      ArcadeTerrain.height(power, 0, heightScale, reducedMotion: true) - 14;

  List<double> _entries() {
    final entries = <double>[];
    var elevation = _base(
      road.spans.isEmpty ? .5 : arcadeSegmentPower(road.spans.first.segment, 0),
    );
    for (var i = 0; i < road.spans.length; i++) {
      final span = road.spans[i];
      entries.add(elevation);
      if (span.length <= 0) continue;
      final target = _base(arcadeSegmentPower(span.segment, 1));
      // A very short sector may not finish its climb; the following sector
      // inherits the reached height, not an unreachable target plateau.
      final blend = i == _firstRoad
          ? 1.0
          : (span.length / arcadeRoadTransitionTiles).clamp(0.0, 1.0);
      elevation = blend >= 1
          ? target
          : elevation + (target - elevation) * blend;
    }
    return entries;
  }

  double heightAt(double distance) {
    if (!distance.isFinite)
      distance = road.position.isFinite ? road.position : 0;
    final relief = ArcadeTerrain.relief(distance, reducedMotion: reducedMotion);
    if (road.spans.isEmpty) return _base(.5) + relief;
    var low = 0, high = road.spans.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (road.spans[middle].end <= distance) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = math.min(low, road.spans.length - 1);
    final span = road.spans[index];
    final target = _base(road.powerAt(distance));
    if (index == _firstRoad) return target + relief;
    final blend = span.length <= 0
        ? 0.0
        : ((distance - span.start) / arcadeRoadTransitionTiles).clamp(0.0, 1.0);
    if (blend >= 1) return target + relief;
    final entry = _entryHeights[index];
    return entry + (target - entry) * blend + relief;
  }
}
