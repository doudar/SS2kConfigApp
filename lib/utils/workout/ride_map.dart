import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'workout_skyline.dart';

enum RideDrawing {
  random('Random drawing'),
  bicycle('Road bike'),
  smartSpin2k('SmartSpin2k'),
  chainring('Chainring'),
  bottle('Water bottle'),
  skyline('Workout skyline'),
  none('No map');

  const RideDrawing(this.label);
  final String label;

  static const outlines = [bicycle, smartSpin2k, chainring, bottle];

  RideDrawing forRide(DateTime start, {bool includeSkyline = false}) {
    if (this != random) return this;
    final choices = includeSkyline ? const [...outlines, skyline] : outlines;
    return choices[math.Random(
      start.millisecondsSinceEpoch ~/ 1000,
    ).nextInt(choices.length)];
  }
}

typedef MapCenter = ({String name, double lat, double lon});
typedef MapCoordinate = ({double lat, double lon});

class RideMapSettings {
  static const eauClaire = (
    name: 'Eau Claire, WI',
    lat: 44.8113,
    lon: -91.4985,
  );
  static const _key = 'workout_ride_map';
  const RideMapSettings({
    this.drawing = RideDrawing.random,
    this.center = eauClaire,
  });
  final RideDrawing drawing;
  final MapCenter center;

  RideMapSettings withDrawing(RideDrawing value) =>
      RideMapSettings(drawing: value, center: center);

  static RideMapSettings load(SharedPreferences prefs) {
    final saved = prefs.getString(_key);
    if (saved == null) return const RideMapSettings();
    try {
      final data = jsonDecode(saved);
      if (data is Map) {
        final drawing =
            RideDrawing.values
                .where((v) => v.name == data['drawing'])
                .firstOrNull ??
            RideDrawing.random;
        final center = parseCenter(data['name'], data['lat'], data['lon']);
        return RideMapSettings(drawing: drawing, center: center ?? eauClaire);
      }
    } on FormatException {
      // A malformed preference can be replaced from the menu.
    }
    return const RideMapSettings();
  }

  static MapCenter? parseCenter(Object? name, Object? lat, Object? lon) {
    if (name is! String ||
        name.trim().isEmpty ||
        lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      return null;
    }
    return (name: name.trim(), lat: lat.toDouble(), lon: lon.toDouble());
  }

  Future<bool> save(SharedPreferences prefs) => prefs.setString(
    _key,
    jsonEncode({
      'drawing': drawing.name,
      'name': center.name,
      'lat': center.lat,
      'lon': center.lon,
    }),
  );
}

/// Each outline is one continuous pen stroke, shared by the picker and FIT export.
Path rideDrawingPath(RideDrawing drawing, {WorkoutSkyline? skyline}) {
  switch (drawing) {
    case RideDrawing.skyline:
      return (skyline ?? WorkoutSkyline.example).toPath();
    case RideDrawing.bicycle:
      final path = Path()..moveTo(24, 57);
      void wheel(double hubX) {
        final rim = Rect.fromCircle(center: Offset(hubX, 57), radius: 21);
        const sector = 2 * math.pi / 6;
        for (var spoke = 0; spoke < 6; spoke++) {
          path
            ..arcTo(rim, math.pi / 2 + spoke * sector, sector, false)
            ..lineTo(hubX, 57);
        }
      }
      wheel(24);
      path
        ..lineTo(46, 30)
        ..lineTo(84, 25)
        ..lineTo(88, 36)
        ..lineTo(55, 60)
        ..arcTo(
          const Rect.fromLTRB(51, 56, 59, 64),
          -math.pi / 2,
          math.pi,
          false,
        )
        ..arcTo(
          const Rect.fromLTRB(51, 56, 59, 64),
          math.pi / 2,
          math.pi,
          false,
        )
        ..lineTo(55, 60)
        ..lineTo(61, 66)
        ..lineTo(65, 66)
        ..lineTo(61, 66)
        ..lineTo(55, 60)
        ..lineTo(24, 57)
        ..lineTo(55, 60)
        ..lineTo(43, 20)
        ..lineTo(36, 19)
        ..quadraticBezierTo(36, 17, 42, 17)
        ..lineTo(53, 18)
        ..quadraticBezierTo(51, 21, 43, 20)
        ..lineTo(46, 30)
        ..lineTo(84, 25)
        ..lineTo(82, 19)
        ..lineTo(92, 17)
        ..cubicTo(104, 15, 105, 28, 95, 28)
        ..lineTo(92, 28)
        ..lineTo(95, 28)
        ..cubicTo(105, 28, 104, 15, 92, 17)
        ..lineTo(82, 19)
        ..lineTo(88, 36)
        ..quadraticBezierTo(93, 54, 100, 57);
      wheel(100);
      return path;
    case RideDrawing.smartSpin2k:
      // The outer casing and broad knob cup share a single, continuous outline.
      return Path()
        ..moveTo(227, 529)
        ..lineTo(131, 496)
        ..quadraticBezierTo(115, 491, 118, 474)
        ..lineTo(122, 428)
        // Extend the lower edge of the inset to join it to the GPS trace.
        ..lineTo(173, 442)
        ..lineTo(293, 473)
        ..quadraticBezierTo(302, 476, 303, 466)
        ..lineTo(322, 265)
        ..quadraticBezierTo(323, 257, 315, 257)
        ..lineTo(196, 247)
        ..quadraticBezierTo(187, 246, 186, 256)
        ..lineTo(167, 431)
        ..quadraticBezierTo(166, 440, 173, 442)
        ..lineTo(122, 428)
        ..lineTo(137, 269)
        ..cubicTo(144, 159, 232, 53, 351, 51)
        ..lineTo(489, 49)
        ..cubicTo(515, 47, 565, 56, 602, 66)
        ..cubicTo(649, 77, 730, 100, 770, 106)
        ..cubicTo(836, 118, 841, 63, 877, 61)
        ..cubicTo(899, 59, 912, 83, 907, 120)
        ..lineTo(847, 553)
        ..quadraticBezierTo(843, 579, 822, 579)
        ..lineTo(710, 576)
        ..lineTo(688, 770)
        ..cubicTo(683, 801, 561, 815, 448, 797)
        ..cubicTo(317, 778, 198, 741, 206, 705)
        ..lineTo(227, 529)
        // Follow the cup lip back to the curved seam between the case faces.
        ..quadraticBezierTo(301, 557, 355, 569)
        ..cubicTo(457, 593, 660, 620, 710, 576)
        ..lineTo(355, 569)
        ..quadraticBezierTo(338, 567, 340, 545)
        ..lineTo(366, 176)
        ..cubicTo(371, 97, 423, 49, 489, 49)
        ..cubicTo(515, 47, 565, 56, 602, 66)
        ..lineTo(877, 61);
    case RideDrawing.chainring:
      final path = Path();
      const teeth = 16;
      for (var tooth = 0; tooth < teeth; tooth++) {
        for (final (phase, radius) in const [
          (0.0, 41),
          (.22, 41),
          (.32, 47),
          (.66, 47),
          (.76, 41),
        ]) {
          final angle = (tooth + phase) * 2 * math.pi / teeth;
          final x = radius * math.cos(angle), y = radius * math.sin(angle);
          if (tooth == 0 && phase == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
      }
      path.lineTo(41, 0);
      // The inner edge of the toothed ring joins the five-arm spider.
      path
        ..lineTo(34, 0)
        ..arcTo(const Rect.fromLTRB(-34, -34, 34, 34), 0, math.pi, false)
        ..arcTo(const Rect.fromLTRB(-34, -34, 34, 34), math.pi, math.pi, false);
      for (var arm = 0; arm < 5; arm++) {
        final angle = arm * 2 * math.pi / 5;
        final next = (arm + 1) * 2 * math.pi / 5;
        path
          ..lineTo(12 * math.cos(angle + .20), 12 * math.sin(angle + .20))
          ..arcTo(
            const Rect.fromLTRB(-12, -12, 12, 12),
            angle + .20,
            next - angle - .40,
            false,
          )
          ..lineTo(34 * math.cos(next - .16), 34 * math.sin(next - .16))
          ..arcTo(
            const Rect.fromLTRB(-34, -34, 34, 34),
            next - .16,
            .16,
            false,
          );
      }
      return path;
    case RideDrawing.bottle:
      return Path()
        ..moveTo(18, 93)
        ..quadraticBezierTo(12, 93, 12, 86)
        ..lineTo(12, 49)
        ..quadraticBezierTo(17, 43, 14, 39)
        ..quadraticBezierTo(10, 35, 13, 29)
        ..lineTo(21, 20)
        ..lineTo(21, 15)
        ..lineTo(47, 15)
        ..lineTo(21, 15)
        ..lineTo(18, 15)
        ..lineTo(18, 10)
        ..lineTo(28, 10)
        ..lineTo(29, 4)
        ..lineTo(39, 4)
        ..lineTo(40, 10)
        ..lineTo(50, 10)
        ..lineTo(50, 15)
        ..lineTo(47, 15)
        ..lineTo(47, 20)
        ..lineTo(55, 29)
        ..quadraticBezierTo(58, 35, 54, 39)
        ..quadraticBezierTo(51, 43, 56, 49)
        ..lineTo(56, 86)
        ..quadraticBezierTo(56, 93, 50, 93)
        ..close();
    case RideDrawing.random:
    case RideDrawing.none:
      throw ArgumentError.value(
        drawing,
        'drawing',
        'Choose a concrete outline',
      );
  }
}

class RideMapRoute {
  static const lengthMeters = 20 * 1609.344;
  static const earthRadius = 6371000.0;
  final PathMetric _stroke;
  final Offset _origin;
  final MapCenter center;
  final double _length;

  RideMapRoute._(Path path, this.center, this._length)
    : _stroke = path.computeMetrics().single,
      _origin = path.getBounds().center;

  static RideMapRoute? forRide(
    RideMapSettings settings,
    DateTime start, {
    WorkoutSkyline? skyline,
    double? skylineDistance,
  }) {
    final drawing = settings.drawing.forRide(start);
    if (drawing == RideDrawing.skyline) {
      if (skyline == null || skylineDistance == null || skylineDistance <= 0)
        return null;
      return RideMapRoute._(skyline.toPath(), settings.center, skylineDistance);
    }
    return drawing == RideDrawing.none
        ? null
        : RideMapRoute._(
            rideDrawingPath(drawing),
            settings.center,
            lengthMeters,
          );
  }

  MapCoordinate position(double meters) {
    // Retrace the line on alternate passes so open outlines have no jump.
    final cycle = meters % (2 * _length);
    final along = cycle <= _length ? cycle : 2 * _length - cycle;
    final point = _stroke
        .getTangentForOffset(along / _length * _stroke.length)!
        .position;
    final offset = (point - _origin) * (_length / _stroke.length);
    final angle = offset.distance / earthRadius;
    final bearing = math.atan2(offset.dx, -offset.dy);
    final lat = center.lat * math.pi / 180;
    final sinLat =
        math.sin(lat) * math.cos(angle) +
        math.cos(lat) * math.sin(angle) * math.cos(bearing);
    final destLat = math.asin(sinLat.clamp(-1, 1));
    final deltaLon = math.atan2(
      math.sin(bearing) * math.sin(angle) * math.cos(lat),
      math.cos(angle) - math.sin(lat) * math.sin(destLat),
    );
    return (
      lat: destLat * 180 / math.pi,
      lon: (center.lon + deltaLon * 180 / math.pi + 180) % 360 - 180,
    );
  }
}
