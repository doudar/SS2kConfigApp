import 'dart:math' as math;

import '../workout_parser.dart';
import 'arcade_cues.dart';
import 'arcade_road.dart';
import 'arcade_story.dart';
import 'arcade_drones.dart';

enum ArcadeBiome { grove, coast, neon, volcano }

extension ArcadeBiomeStory on ArcadeBiome {
  String get title => switch (this) {
    ArcadeBiome.grove => 'RECHARGE GROVE',
    ArcadeBiome.coast => 'COASTAL CRUISE',
    ArcadeBiome.neon => 'NEON SWITCHBACKS',
    ArcadeBiome.volcano => 'THE CRANK FORGE',
  };

  String get mission => switch (this) {
    ArcadeBiome.grove => 'Ease into the target. Collect forest energy.',
    ArcadeBiome.coast => 'Find your rhythm. Chase the wheel drones.',
    ArcadeBiome.neon => 'Hold your line. Outride the neon sentinels.',
    ArcadeBiome.volcano => 'Hold the target to break the Gear Golem!',
  };
}

ArcadeBiome biomeFor(WorkoutSegment segment) {
  if (segment.type == SegmentType.freeRide) return ArcadeBiome.coast;
  final power = segment.isRamp
      ? (segment.powerLow + segment.powerHigh) / 2
      : segment.powerLow;
  if (power >= 1.05) return ArcadeBiome.volcano;
  if (power >= .85) return ArcadeBiome.neon;
  if (power >= .60) return ArcadeBiome.coast;
  return ArcadeBiome.grove;
}

/// Presentation-only rewards. Never writes targets or drives the workout clock.
/// State lives above the view, so switching to Classic does not lose the run.
class ArcadeSession {
  ArcadeSession({ArcadeDrones? drones}) : drones = drones ?? ArcadeDrones();
  final ArcadeRoad road = ArcadeRoad();
  final ArcadeDrones drones;

  /// Set by the visible Arcade view. Classic and modal screens cannot be shot
  /// through, so encounters wait while the rider cannot interact with them.
  bool droneInteractionEnabled = false;
  ArcadeStory story = ArcadeStory.random();
  bool openingSeen = false;
  ArcadeStory? _stagedOpening;
  void stageOpening(ArcadeStory opening) => _stagedOpening = opening;
  void cancelStagedOpening() => _stagedOpening = null;
  bool musicEnabled = false;
  bool effectsEnabled = true;
  List<WorkoutSegment>? _segments;
  double? _lastTime;
  bool _wasPlaying = false;
  bool _skip = false;
  double _points = 0;
  double streakSeconds = 0;
  double _offTargetSeconds = 0;
  final Map<int, double> _charge = {};
  final Set<int> cleared = {};
  int bossesDefeated = 0;
  int bestCombo = 1;
  bool onTarget = false;
  bool hasSignal = false;
  bool finished = false;
  String? reward;
  double _rewardUntil = 0;
  double _energySeconds = 0;
  final List<ArcadeCue> _cues = [];
  int cueRevision = 0;
  Iterable<ArcadeCue> get cues => _cues;

  int get score => _points.floor();

  bool fireDrone({
    required int serial,
    required bool hit,
    required double aimX,
    required double aimY,
    required double shownClock,
  }) {
    if (!droneInteractionEnabled || !_wasPlaying || !hasSignal) return false;
    final events = drones.fire(
      serial: serial,
      hit: hit,
      aimX: aimX,
      aimY: aimY,
      shownClock: shownClock,
    );
    if (events.isEmpty) return false;
    _cues.clear();
    cueRevision++;
    _applyDroneEvents(events, _lastTime ?? 0);
    return true;
  }

  void _applyDroneEvents(Iterable<ArcadeDroneEvent> events, double seconds) {
    for (final event in events) {
      switch (event) {
        case ArcadeDroneEvent.ready:
          _cues.add(ArcadeCue.combo);
        case ArcadeDroneEvent.fired:
          _cues.add(ArcadeCue.bolt);
        case ArcadeDroneEvent.destroyed:
        case ArcadeDroneEvent.bossHit:
          _cues.add(ArcadeCue.droneHit);
        case ArcadeDroneEvent.bossDestroyed:
          final sector = drones.snapshot().sector;
          if (cleared.add(sector)) {
            bossesDefeated++;
            _points += 500;
            reward = 'GEAR GOLEM DEFEATED  +500';
            _rewardUntil = seconds + 5;
            _cues.add(ArcadeCue.bossDefeat);
          }
        case ArcadeDroneEvent.escaped:
        case ArcadeDroneEvent.bossCounter:
          final stolen = math.min(score, ArcadeDrones.theftPoints);
          _points = math.max(0.0, _points - ArcadeDrones.theftPoints);
          reward = event == ArcadeDroneEvent.bossCounter
              ? 'GOLEM COUNTERATTACK · −$stolen POINTS'
              : stolen > 0
              ? 'DRONE STOLE $stolen POINTS!'
              : 'DRONE ESCAPED · NO POINTS TO STEAL';
          _rewardUntil = seconds + 4;
          _cues.add(ArcadeCue.crewAlarm);
      }
    }
  }

  int get combo => 1 + (streakSeconds / 15).floor().clamp(0, 3);
  String get rank => score >= 6000
      ? 'LEGEND'
      : score >= 2500
      ? 'HERO'
      : 'EXPLORER';

  int segmentIndex(List<WorkoutSegment> segments, double seconds) {
    var end = 0.0;
    for (var i = 0; i < segments.length; i++) {
      end += segments[i].duration;
      if (seconds < end) return i;
    }
    return math.max(0, segments.length - 1);
  }

  double segmentStart(List<WorkoutSegment> segments, int index) =>
      segments.take(index).fold(0.0, (sum, s) => sum + s.duration);

  double chargeFor(int index, WorkoutSegment segment) {
    if (biomeFor(segment) == ArcadeBiome.volcano) {
      if (cleared.contains(index)) return 1;
      final target = drones.snapshot();
      return target.isBoss && target.sector == index ? target.damage : 0;
    }
    return ((_charge[index] ?? 0) / math.max(1, segment.duration * .65)).clamp(
      0,
      1,
    );
  }

  void willSkip() {
    road.willSkip();
    _skip = true;
    streakSeconds = 0;
  }

  void update({
    required List<WorkoutSegment> segments,
    required double seconds,
    required bool playing,
    required double watts,
    required double target,
    required bool freshSignal,
    double ftp = 200,
    bool endless = false,
  }) {
    road.update(
      segments: segments,
      seconds: seconds,
      watts: watts,
      ftp: ftp,
      playing: playing,
    );
    _cues.clear();
    cueRevision++;
    // Unlimited rides can replace their sole segment when extending duration.
    final sameUnlimitedRide =
        _segments?.length == 1 &&
        segments.length == 1 &&
        _segments!.first.type == SegmentType.freeRide &&
        segments.first.type == SegmentType.freeRide &&
        seconds > 0;
    if ((!identical(_segments, segments) && !sameUnlimitedRide) ||
        (_lastTime != null && seconds < _lastTime!)) {
      _points = 0;
      drones.reset();
      story = ArcadeStory.random();
      openingSeen = false;
      streakSeconds = 0;
      _offTargetSeconds = 0;
      _charge.clear();
      cleared.clear();
      bossesDefeated = 0;
      bestCombo = 1;
      reward = null;
      finished = false;
      _lastTime = null;
      _wasPlaying = false;
      _skip = false;
      _energySeconds = 0;
    }
    // Adopt the cast shown before Play, including when the controller rewinds
    // a completed workout on restart. Cancelled cutscenes never reset rewards.
    if (playing && _stagedOpening != null) {
      story = _stagedOpening!;
      openingSeen = true;
      _stagedOpening = null;
    }
    _segments = segments;
    final previous = _lastTime;
    final wasPlaying = _wasPlaying;
    _lastTime = seconds;
    _wasPlaying = playing;
    hasSignal = freshSignal;
    if (segments.isEmpty) return;
    final index = segmentIndex(segments, seconds);
    final free = segments[index].type == SegmentType.freeRide;
    // More watts never earns a bigger reward. Recovery is part of the mission.
    onTarget =
        freshSignal &&
        watts > 0 &&
        (free ||
            (target > 0 &&
                (watts - target).abs() <= math.max(10, target * .10)));
    if (seconds > _rewardUntil) reward = null;
    final delta = previous == null ? 0.0 : seconds - previous;
    final currentBiome = biomeFor(segments[index]);
    final chapter = story.frame(
      seconds: seconds,
      total: segments.fold<double>(0, (sum, segment) => sum + segment.duration),
      endless: endless,
      bosses: bossesDefeated,
      sectors: cleared.length,
      openingSeen: openingSeen,
    );
    final combatEvents = drones.update(
      seconds: wasPlaying ? delta : 0,
      playing: playing && droneInteractionEnabled && freshSignal,
      enabled:
          (currentBiome == ArcadeBiome.volcano && !cleared.contains(index)) ||
          (chapter.phase == ArcadeStoryPhase.chase &&
              (currentBiome == ArcadeBiome.coast ||
                  currentBiome == ArcadeBiome.neon)),
      onTarget: onTarget,
      sector: index,
      style: currentBiome == ArcadeBiome.volcano
          ? ArcadeDroneStyle.golem
          : currentBiome == ArcadeBiome.neon
          ? ArcadeDroneStyle.sentinel
          : ArcadeDroneStyle.wheel,
      skipped: _skip,
      bossHits: (segments[index].duration / 30).ceil().clamp(1, 6),
    );
    if (!_skip &&
        playing &&
        !wasPlaying &&
        seconds == 0 &&
        biomeFor(segments[index]) == ArcadeBiome.volcano) {
      _cues.add(ArcadeCue.bossApproach);
    }
    if (_skip || !wasPlaying || delta <= 0 || delta > 1.5) {
      if (_skip || delta > 1.5) streakSeconds = 0;
      _skip = false;
      _applyDroneEvents(combatEvents, seconds);
      return;
    }
    if (playing &&
        previous != null &&
        segmentIndex(segments, previous) != index &&
        biomeFor(segments[index]) == ArcadeBiome.volcano) {
      _cues.add(ArcadeCue.bossApproach);
    }
    if (onTarget) {
      final oldCombo = combo;
      streakSeconds += delta;
      if (combo > oldCombo) _cues.add(ArcadeCue.combo);
      final oldEnergy = (_energySeconds / 3).floor();
      _energySeconds += delta;
      if ((_energySeconds / 3).floor() > oldEnergy) {
        _cues.add(ArcadeCue.pickup);
      }
      _offTargetSeconds = 0;
      bestCombo = math.max(bestCombo, combo);
      _points += delta * 10 * combo;
      // Assign each slice to the interval actually ridden, including boundaries.
      var cursor = previous!;
      while (cursor < seconds) {
        final i = segmentIndex(segments, cursor);
        final end = segmentStart(segments, i) + segments[i].duration;
        final slice = math.min(seconds, end) - cursor;
        if (slice <= 0) break;
        _charge[i] = (_charge[i] ?? 0) + slice;
        if (biomeFor(segments[i]) != ArcadeBiome.volcano &&
            !cleared.contains(i) &&
            chargeFor(i, segments[i]) >= 1) {
          cleared.add(i);
          _cues.add(ArcadeCue.sectorClear);
          _points += 150;
          reward = 'SECTOR SECURED  +150';
          _rewardUntil = seconds + 5;
        }
        cursor += slice;
      }
    } else {
      _offTargetSeconds += delta;
      // Give riders a few seconds to settle after target changes.
      if (_offTargetSeconds > 3) streakSeconds = 0;
    }
    final total = segments.fold(0, (sum, s) => sum + s.duration);
    if (!playing && seconds >= total && total > 0) finished = true;
    _applyDroneEvents(combatEvents, seconds);
  }
}
