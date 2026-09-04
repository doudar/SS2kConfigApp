import 'dart:math' as math;
import '../workout_parser.dart';

/// One road unit is one isometric tile. At FTP this is 12x the original
/// one-tile-per-six-seconds display speed. This never controls trainer speed,
/// workout duration, exported distance or scoring.
const arcadeTilesPerSecondAtFtp = 2.0;

double arcadeRoadSpeed(double watts, double ftp) {
  if (!watts.isFinite || !ftp.isFinite || watts <= 0 || ftp <= 0) return 0;
  // Bound corrupt telemetry and extreme sprints to a renderable visual speed.
  return (watts / ftp).clamp(0.0, 6.0) * arcadeTilesPerSecondAtFtp;
}

class ArcadeRoadSpan {
  const ArcadeRoadSpan(this.segment, this.start, this.end);
  final WorkoutSegment segment;
  final double start;
  final double end;
  double get length => end - start;
}

class ArcadeRoadPiece {
  const ArcadeRoadPiece(this.segment, this.start, this.end);
  final WorkoutSegment segment;
  final double start;
  final double end;
}

class ArcadeRoadSnapshot {
  const ArcadeRoadSnapshot({
    required this.position,
    required this.speed,
    required this.spans,
    required this.currentIndex,
  });
  final double position;
  final double speed;
  final List<ArcadeRoadSpan> spans;
  final int currentIndex;

  int _indexAt(double distance) {
    var low = 0;
    var high = spans.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (spans[middle].end <= distance) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.min(low, spans.length - 1);
  }

  WorkoutSegment? segmentAt(double distance) =>
      spans.isEmpty ? null : spans[_indexAt(distance)].segment;

  /// Split tiles precisely at sector boundaries instead of sampling a biome
  /// once per tile. Extend the end scenery beyond the finite route.
  Iterable<ArcadeRoadPiece> pieces(double start, double end) sync* {
    if (spans.isEmpty || end <= start) return;
    var cursor = start;
    while (cursor < end) {
      final index = _indexAt(cursor);
      final span = spans[index];
      final boundary = index == spans.length - 1
          ? end
          : math.min(end, span.end);
      if (boundary <= cursor) return;
      yield ArcadeRoadPiece(span.segment, cursor, boundary);
      cursor = boundary;
    }
  }
}

/// Integrates actual power on the workout clock. Completed road lengths are
/// fixed; the active sector forecasts its remaining length from current power.
/// Future sectors are estimates from their prescribed average FTP intensity.
class ArcadeRoad {
  List<WorkoutSegment> _segments = const [];
  List<double> _endTimes = [];
  List<double> _completedEnds = [];
  List<ArcadeRoadSpan> _spans = const [];
  double _position = 0;
  double _speed = 0;
  double _forecastSpeed = 0;
  double? _seconds;
  bool _playing = false;
  bool _skip = false;
  int _index = 0;
  int revision = 0;

  void willSkip() => _skip = true;

  int _indexAtTime(double seconds) {
    var i = 0;
    while (i < _endTimes.length - 1 && seconds >= _endTimes[i]) i++;
    return i;
  }

  double _plannedSpeed(WorkoutSegment segment) {
    if (segment.type == SegmentType.freeRide) {
      return _forecastSpeed > 0 ? _forecastSpeed : arcadeTilesPerSecondAtFtp;
    }
    final ratio = segment.isRamp
        ? (segment.powerLow + segment.powerHigh) / 2
        : segment.powerLow;
    return arcadeRoadSpeed(ratio, 1);
  }

  void update({
    required List<WorkoutSegment> segments,
    required double seconds,
    required double watts,
    required double ftp,
    required bool playing,
  }) {
    if (!seconds.isFinite) return;
    final previous = _seconds;
    final extendingFreeRide =
        _segments.length == 1 &&
        segments.length == 1 &&
        _segments.first.type == SegmentType.freeRide &&
        segments.first.type == SegmentType.freeRide &&
        _endTimes.length == 1 &&
        segments.first.duration > _endTimes.single &&
        seconds > 0;
    final reset =
        (!identical(_segments, segments) && !extendingFreeRide) ||
        (previous != null && seconds < previous);
    if (reset) {
      _position = 0;
      _speed = 0;
      _forecastSpeed = 0;
      _seconds = null;
      _playing = false;
      _skip = false;
      _index = 0;
      _completedEnds = List.filled(segments.length, 0);
    }
    if (!identical(_segments, segments) || extendingFreeRide) {
      _segments = segments;
      var end = 0.0;
      _endTimes = [
        for (final segment in segments) end += math.max(0, segment.duration),
      ];
    }
    revision++;
    if (segments.isEmpty) {
      _spans = const [];
      _seconds = seconds;
      return;
    }
    final time = seconds.clamp(0.0, _endTimes.last);
    final nextIndex = _indexAtTime(time);
    final oldTime = _seconds;
    final delta = oldTime == null ? 0.0 : time - oldTime;
    final ridden = _playing && !_skip && delta > 0 && delta <= 1.5;
    if (oldTime != null) {
      var cursor = oldTime;
      for (var i = _index; i <= nextIndex; i++) {
        final end = math.min(time, _endTimes[i]);
        if (ridden) _position += math.max(0.0, end - cursor) * _speed;
        if (i < nextIndex || time >= _endTimes[i])
          _completedEnds[i] = _position;
        cursor = end;
      }
    }
    _index = nextIndex;
    _seconds = time;
    _skip = false;
    if (playing) {
      _forecastSpeed = arcadeRoadSpeed(watts, ftp);
    } else if (reset || oldTime == null) {
      _forecastSpeed = _plannedSpeed(segments[_index]);
    }
    _playing = playing;
    _speed = playing ? _forecastSpeed : 0;
    var distance = 0.0;
    final spans = <ArcadeRoadSpan>[];
    for (var i = 0; i < segments.length; i++) {
      final start = distance;
      distance = i < _index
          ? _completedEnds[i]
          : i == _index
          ? _position + _forecastSpeed * math.max(0, _endTimes[i] - time)
          : start +
                _plannedSpeed(segments[i]) * math.max(0, segments[i].duration);
      spans.add(ArcadeRoadSpan(segments[i], start, distance));
    }
    _spans = List.unmodifiable(spans);
  }

  ArcadeRoadSnapshot snapshot({double aheadSeconds = 0}) {
    // Smooth between the controller's 100 ms samples, without predicting past
    // the next sector boundary or adding motion while paused.
    final remaining = _endTimes.isEmpty
        ? 0.0
        : math.max(0.0, _endTimes[_index] - (_seconds ?? 0));
    final ahead = aheadSeconds.isFinite
        ? aheadSeconds.clamp(0.0, math.min(.1, remaining))
        : 0.0;
    return ArcadeRoadSnapshot(
      position: _position + _speed * ahead,
      speed: _speed,
      spans: _spans,
      currentIndex: _index,
    );
  }
}
