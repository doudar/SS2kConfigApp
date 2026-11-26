import 'dart:math' as math;
import 'dart:ui';

import 'workout_parser.dart';
import 'workout_training_load.dart';

/// The recorder writes one sample per active second, including coasting.
int? averageRecordedWatts(Iterable<int?> samples) {
  var sum = 0, count = 0;
  for (final sample in samples) {
    if (sample == null || sample < 0) continue;
    sum += sample;
    count++;
  }
  return count == 0 ? null : (sum / count).round();
}

/// One point per end of a target interval or ramp. X is fraction of plan
/// duration, Y is relative power. Equal X values retain vertical interval edges.
List<Offset> skylinePlan(List<WorkoutSegment> segments) {
  final duration = segments.fold<int>(0, (t, s) => t + s.duration);
  if (duration <= 0) return [];
  var elapsed = 0;
  final profile = <Offset>[];
  for (final segment in segments) {
    if (segment.duration <= 0) continue;
    final from = segment.getPowerAtTime(0);
    final to = segment.getPowerAtTime(segment.duration);
    if (!from.isFinite || !to.isFinite) return [];
    profile.add(Offset(elapsed / duration, from));
    elapsed += segment.duration;
    profile.add(Offset(elapsed / duration, to));
  }
  return profile.any((p) => p.dy > 0) ? profile : [];
}

class WorkoutSkyline {
  const WorkoutSkyline(this.profile, this.averageWatts, this.tss);

  final List<Offset> profile;
  final int? averageWatts;
  final double? tss;
  String get label => [
    if (averageWatts != null) 'AVG ${averageWatts}W',
    if (tss != null) '${tss!.round()} TSS',
  ].join('   ');

  // Used only in the preferences picker before the rider has finished a ride.
  static const example = WorkoutSkyline(
    [
      Offset(0, .5),
      Offset(.15, .75),
      Offset(.15, .55),
      Offset(.24, .55),
      Offset(.24, .85),
      Offset(.36, .85),
      Offset(.36, .55),
      Offset(.46, .55),
      Offset(.46, 1),
      Offset(.58, 1),
      Offset(.58, .55),
      Offset(.68, .55),
      Offset(.68, .85),
      Offset(.8, .85),
      Offset(.8, .6),
      Offset(1, .4),
    ],
    178,
    61,
  );

  factory WorkoutSkyline.fromRide(
    List<int?> samples, {
    required List<Offset> plan,
    double? ftp,
    double? savedTss,
  }) {
    // App FIT records and recorder checkpoints are one sample per active
    // second. A gap after skipping an interval is not time spent pedaling.
    final watts = samples.whereType<int>().where((w) => w >= 0).toList();
    final average = averageRecordedWatts(watts);
    double? tss = savedTss != null && savedTss.isFinite && savedTss >= 0
        ? savedTss
        : null;
    if (tss == null &&
        watts.isNotEmpty &&
        ftp != null &&
        ftp.isFinite &&
        ftp > 0) {
      final np = normalizedPower(watts.map((w) => w.toDouble()));
      tss = WorkoutTrainingLoad(watts.length, np / ftp).tss;
    }
    return WorkoutSkyline(
      plan.isEmpty ? _recordedProfile(samples) : plan,
      average,
      tss,
    );
  }

  static List<Offset> _recordedProfile(List<int?> samples) {
    // A trailing 30-second mean at each active second preserves short efforts,
    // even on a long ride. Include coasting and skip missing measurements.
    const window = 30;
    final profile = <Offset>[];
    var sum = 0, count = 0;
    for (var i = 0; i < samples.length; i++) {
      final incoming = samples[i];
      if (incoming != null && incoming >= 0) {
        sum += incoming;
        count++;
      }
      if (i >= window) {
        final outgoing = samples[i - window];
        if (outgoing != null && outgoing >= 0) {
          sum -= outgoing;
          count--;
        }
      }
      if (count > 0) {
        profile.add(Offset(i / math.max(1, samples.length - 1), sum / count));
      }
    }
    if (profile.isEmpty) return const [Offset(0, 0), Offset(1, 0)];
    if (profile.first.dx > 0) profile.insert(0, Offset(0, profile.first.dy));
    if (profile.last.dx < 1) profile.add(Offset(1, profile.last.dy));
    return profile;
  }

  Path toPath({bool includeLettering = true}) {
    const width = 900.0, baseline = 260.0;
    var low = profile.first.dy, high = low;
    for (final p in profile) {
      low = math.min(low, p.dy);
      high = math.max(high, p.dy);
    }
    // Keep recovery troughs clear of the lettering, even for a flat workout.
    double y(double power) =>
        high == low ? 100 : 167 - 155 * (power - low) / (high - low);
    final path = Path()..moveTo(0, y(profile.first.dy));
    for (final p in profile.skip(1)) {
      path.lineTo(p.dx * width, y(p.dy));
    }
    path.lineTo(width, baseline);

    // Riders traverse the baseline right to left. Reverse the pen stroke,
    // keeping the words upright and readable left to right on a north-up map.
    final lettering = <Offset>[];
    var cursor = 0.0;
    for (final char in (includeLettering ? label : '').split('')) {
      if (char == ' ') {
        cursor += 4;
        continue;
      }
      final stroke = _glyphs[char]!;
      lettering.addAll(stroke.map((p) => Offset(cursor + p.dx, p.dy)));
      cursor += stroke.map((p) => p.dx).reduce(math.max) + 2.7;
    }
    final scale = cursor == 0 ? 5.0 : math.min(5.0, width * .82 / cursor);
    final left = (width - (cursor - 2.7) * scale) / 2;
    for (final point in lettering.reversed) {
      path.lineTo(left + point.dx * scale, baseline - point.dy * scale);
    }
    return path
      ..lineTo(0, baseline)
      ..close();
  }
}

// Single-stroke glyphs in SVG polyline coordinates (Y points up). Each starts
// and ends on the baseline. Retraced branches allow crossbars without pen lifts.
final _glyphs =
    <String, String>{
      'A': '0,0 3.5,10 5.6,4 1.4,4 5.6,4 7,0',
      'V': '3.5,0 0,10 3.5,0 7,10 3.5,0',
      'G':
          '2,0 .3,1.5 .3,8.4 1.9,10 5.3,10 6.8,8.5 5.3,10 1.9,10 .3,8.4 .3,1.5 2,0 5.3,0 6.7,1.4 6.7,4.5 3.9,4.5 6.7,4.5 6.7,1.4 5.3,0',
      'W': '1.9,0 0,10 1.9,0 4.5,6.4 7.1,0 9,10 7.1,0',
      'T': '3.5,0 3.5,10 0,10 7,10 3.5,10 3.5,0',
      'S':
          '1.4,0 .1,1.3 1.4,0 4.9,0 6.2,1.3 6.2,3.6 5.1,4.8 1.25,5.45 .2,6.6 .2,8.7 1.5,10 4.8,10 6.05,8.8 4.8,10 1.5,10 .2,8.7 .2,6.6 1.25,5.45 5.1,4.8 6.2,3.6 6.2,1.3 4.9,0',
      '0': '1.5,0 0,1.5 0,8.5 1.5,10 4.8,10 6.3,8.5 6.3,1.5 4.8,0 1.5,0 4.8,0',
      '1': '0,0 2.8,0 2.8,10 .45,8.3 2.8,10 2.8,0 5,0',
      '2':
          '0,0 6,6.6 6,8.5 4.5,10 1.5,10 0,8.5 1.5,10 4.5,10 6,8.5 6,6.6 0,0 6.3,0',
      '3':
          '1.2,0 0,1.2 1.2,0 4.8,0 6.1,1.4 6.1,3.7 4.6,5 2,5 4.6,5 6.1,6.4 6.1,8.7 4.8,10 1.2,10 0,8.8 1.2,10 4.8,10 6.1,8.7 6.1,6.4 4.6,5 6.1,3.7 6.1,1.4 4.8,0',
      '4': '5,0 5,10 0,3.4 6.5,3.4 5,3.4 5,0',
      '5':
          '1.2,0 0,1.2 1.2,0 4.9,0 6.2,1.4 6.2,4.3 4.8,5.6 .4,5.6 .4,10 6.1,10 .4,10 .4,5.6 4.8,5.6 6.2,4.3 6.2,1.4 4.9,0',
      '6':
          '1.5,0 .2,1.3 .2,7.4 2.6,10 5.5,10 2.6,10 .2,7.4 .2,4.1 1.65,5.4 4.8,5.4 6.15,4.1 6.15,1.3 4.8,0 1.5,0 4.8,0',
      '7': '1.2,0 6.3,10 0,10 6.3,10 1.2,0',
      '8':
          '1.6,0 .3,1.2 .3,3.8 1.65,5 4.85,5 6.1,6.3 6.1,8.8 4.85,10 1.65,10 .4,8.8 .4,6.3 1.65,5 4.85,5 6.2,3.75 6.2,1.2 4.9,0 1.6,0 4.9,0',
      '9':
          '1.2,0 3.6,0 6.1,2.8 6.1,8.7 4.8,10 1.6,10 .2,8.6 .2,6.1 1.6,4.7 4.7,4.7 6.1,6.1 6.1,2.8 3.6,0',
    }.map(
      (char, polyline) => MapEntry(
        char,
        polyline.split(' ').map((pair) {
          final xy = pair.split(',');
          return Offset(double.parse(xy.first), double.parse(xy.last));
        }).toList(),
      ),
    );
