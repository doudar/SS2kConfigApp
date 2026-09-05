import 'dart:math' as math;

enum ArcadeDroneStyle { wheel, sentinel, golem }

enum ArcadeDronePhase {
  dormant,
  entering,
  hovering,
  ready,
  firing,
  exploding,
  departing,
  rearming,
}

enum ArcadeDroneEvent {
  ready,
  fired,
  destroyed,
  escaped,
  bossHit,
  bossDestroyed,
  bossCounter,
}

class ArcadeDroneFrame {
  const ArcadeDroneFrame({
    required this.phase,
    required this.style,
    required this.serial,
    required this.age,
    required this.clock,
    required this.charge,
    required this.lockClock,
    required this.departureEntry,
    this.entrySide = 0,
    this.hoverX = 0,
    this.hoverY = 0,
    this.shotHit = false,
    this.aimX = 0,
    this.aimY = 0,
    this.stolePoints = false,
    this.sector = 0,
    this.hits = 0,
    this.requiredHits = 1,
  });
  final ArcadeDronePhase phase;
  final ArcadeDroneStyle style;
  final int serial, entrySide;
  final int sector, hits, requiredHits;
  bool get isBoss => style == ArcadeDroneStyle.golem;
  double get damage => (hits / requiredHits).clamp(0.0, 1.0);
  bool get defeated => isBoss && hits >= requiredHits;
  String get targetName => isBoss ? 'Gear Golem' : 'drone';
  final double age, clock, charge, lockClock, departureEntry, hoverX, hoverY;

  /// Shot endpoint in viewport fractions, so resizing preserves its direction.
  final double aimX, aimY;
  final bool shotHit, stolePoints;
  bool get visible =>
      phase != ArcadeDronePhase.dormant && phase != ArcadeDronePhase.rearming;
  bool get ready => phase == ArcadeDronePhase.ready;
  double get secondsLeft => math.max(
    0.0,
    (ready ? ArcadeDrones.readySeconds : ArcadeDrones.hoverSeconds) - age,
  );
  String get status => isBoss
      ? switch (phase) {
          ArcadeDronePhase.hovering =>
            'GOLEM SHIELD ${((1 - damage) * 100).ceil()}% · CHARGE BLASTER',
          ArcadeDronePhase.ready =>
            'TAP THE GOLEM! · ${secondsLeft.ceil()}s · ${requiredHits - hits} HITS LEFT',
          ArcadeDronePhase.firing =>
            shotHit ? 'DIRECT HIT!' : 'MISSED THE GOLEM!',
          ArcadeDronePhase.exploding =>
            defeated ? 'GEAR GOLEM DEFEATED!' : 'ARMOR CRACKED · RECHARGE!',
          ArcadeDronePhase.departing =>
            stolePoints ? 'GOLEM COUNTERATTACK!' : 'LEAVING THE FORGE',
          _ => 'CHARGE YOUR BLASTER',
        }
      : switch (phase) {
          ArcadeDronePhase.entering => 'DRONE INBOUND · CHARGE YOUR BLASTER',
          ArcadeDronePhase.hovering =>
            'BLASTER ${(charge * 100).floor()}% · ${secondsLeft.ceil()}s TO CHARGE',
          ArcadeDronePhase.ready =>
            'TAP THE DRONE! · ${secondsLeft.ceil()}s · MISS COSTS ${ArcadeDrones.theftPoints} PTS',
          ArcadeDronePhase.firing => shotHit ? 'GOOD SHOT!' : 'MISSED!',
          ArcadeDronePhase.exploding => 'DRONE DOWN!',
          ArcadeDronePhase.departing =>
            stolePoints ? 'DRONE STOLE POINTS!' : 'DRONE RETREATING',
          _ => 'SKIES CLEAR',
        };
}

/// Only accepted, interactive workout time advances combat. Randomness is
/// sampled per encounter, never on painter frames or repeated callbacks.
class ArcadeDrones {
  ArcadeDrones({math.Random? random}) : _random = random ?? math.Random();
  final math.Random _random;
  static const energySeconds = 6.0, entrySeconds = 1.8;
  static const readySeconds = 8.0, hoverSeconds = 24.0;
  static const shotSeconds = .45,
      explosionSeconds = 1.1,
      departureSeconds = 1.4;
  static const minGapSeconds = 18.0, maxGapSeconds = 38.0;
  static const theftPoints = 50;
  ArcadeDronePhase _phase = ArcadeDronePhase.dormant;
  ArcadeDroneStyle _style = ArcadeDroneStyle.wheel;
  double _age = 0, _clock = 0, _energy = 0, _lockClock = 0, _departureEntry = 1;
  double _waitSeconds = minGapSeconds,
      _hoverX = 0,
      _hoverY = 0,
      _aimX = 0,
      _aimY = 0;
  int _serial = 0, _entrySide = 0;
  int _encounterSector = 0, _hits = 0, _requiredHits = 1;
  bool get _isBoss => _style == ArcadeDroneStyle.golem;
  int? _sector;
  bool _playing = false, _shotHit = false, _stolePoints = false;
  int destroyed = 0;
  bool get canFire => _playing && _phase == ArcadeDronePhase.ready;

  void reset() {
    _phase = ArcadeDronePhase.dormant;
    _age = _clock = _energy = _lockClock = 0;
    _departureEntry = 1;
    _serial = destroyed = 0;
    _hits = 0;
    _requiredHits = 1;
    _style = ArcadeDroneStyle.wheel;
    _sector = null;
    _playing = _shotHit = _stolePoints = false;
    _aimX = _aimY = 0;
  }

  void _enter(ArcadeDronePhase phase) {
    _phase = phase;
    _age = 0;
  }

  void _schedule() {
    _waitSeconds =
        minGapSeconds + _random.nextDouble() * (maxGapSeconds - minGapSeconds);
    _enter(ArcadeDronePhase.rearming);
  }

  void _arrive(ArcadeDroneStyle style, int sector, int bossHits) {
    _style = style;
    _encounterSector = sector;
    _hits = 0;
    _requiredHits = _isBoss ? bossHits.clamp(1, 6) : 1;
    _serial++;
    _entrySide = _random.nextInt(3);
    _hoverX = (_random.nextDouble() - .5) * 90;
    _hoverY = (_random.nextDouble() - .5) * 35;
    _energy = 0;
    _shotHit = _stolePoints = false;
    _enter(_isBoss ? ArcadeDronePhase.hovering : ArcadeDronePhase.entering);
  }

  void _depart({required bool theft}) {
    _departureEntry = _phase == ArcadeDronePhase.entering
        ? (_age / entrySeconds).clamp(0.0, 1.0)
        : 1;
    if (_phase != ArcadeDronePhase.firing) _lockClock = _clock;
    _energy = 0;
    _stolePoints = theft;
    _enter(ArcadeDronePhase.departing);
  }

  double get _duration => switch (_phase) {
    ArcadeDronePhase.entering => entrySeconds,
    ArcadeDronePhase.hovering => _isBoss ? double.infinity : hoverSeconds,
    ArcadeDronePhase.ready => readySeconds,
    ArcadeDronePhase.firing => shotSeconds,
    ArcadeDronePhase.exploding => explosionSeconds,
    ArcadeDronePhase.departing => departureSeconds,
    ArcadeDronePhase.rearming => _waitSeconds,
    _ => double.infinity,
  };

  /// Commit a hit-test of the displayed frame. Stale/double taps do nothing.
  List<ArcadeDroneEvent> fire({
    required int serial,
    required bool hit,
    required double aimX,
    required double aimY,
    required double shownClock,
  }) {
    if (!canFire ||
        serial != _serial ||
        !aimX.isFinite ||
        !aimY.isFinite ||
        !shownClock.isFinite)
      return [];
    _shotHit = hit;
    _aimX = aimX;
    _aimY = aimY;
    _lockClock = shownClock.clamp(_clock, _clock + .1);
    _energy = 0;
    _enter(ArcadeDronePhase.firing);
    return [ArcadeDroneEvent.fired];
  }

  List<ArcadeDroneEvent> update({
    required double seconds,
    required bool playing,
    required bool enabled,
    required bool onTarget,
    required int sector,
    required ArcadeDroneStyle style,
    bool skipped = false,
    int bossHits = 3,
  }) {
    final events = <ArcadeDroneEvent>[];
    final changed = _sector != null && _sector != sector;
    _sector = sector;
    _playing = playing;
    if ((!enabled || changed || skipped) &&
        (_phase == ArcadeDronePhase.entering ||
            _phase == ArcadeDronePhase.hovering ||
            _phase == ArcadeDronePhase.ready)) {
      // A workout transition is not a missed shot.
      _depart(theft: false);
    }
    if (!enabled && _phase == ArcadeDronePhase.rearming)
      _enter(ArcadeDronePhase.dormant);
    if (!playing) return events;
    // A hard interval starts its boss immediately, even if a drone's random
    // encounter gap was still counting down in the preceding sector.
    if (_phase == ArcadeDronePhase.rearming &&
        enabled &&
        style == ArcadeDroneStyle.golem) {
      _arrive(style, sector, bossHits);
    }
    if (_phase == ArcadeDronePhase.dormant && enabled) {
      if (style == ArcadeDroneStyle.golem) {
        _arrive(style, sector, bossHits);
      } else {
        _schedule();
      }
    }
    var remaining =
        !skipped && seconds.isFinite && seconds > 0 && seconds <= 1.5
        ? seconds
        : 0.0;
    while (remaining > 1e-9 && _phase != ArcadeDronePhase.dormant) {
      final charging =
          enabled &&
          onTarget &&
          (_phase == ArcadeDronePhase.entering ||
              _phase == ArcadeDronePhase.hovering);
      final untilReady = charging && _phase == ArcadeDronePhase.hovering
          ? math.max(0.0, energySeconds - _energy)
          : double.infinity;
      final step = math.min(
        remaining,
        math.min(math.max(0.0, _duration - _age), untilReady),
      );
      _age += step;
      _clock += step;
      if (charging) _energy = math.min(energySeconds, _energy + step);
      remaining -= step;
      if (_phase == ArcadeDronePhase.hovering &&
          _energy >= energySeconds - 1e-9) {
        _enter(ArcadeDronePhase.ready);
        events.add(ArcadeDroneEvent.ready);
      } else if (_age >= _duration - 1e-9) {
        switch (_phase) {
          case ArcadeDronePhase.entering:
            _enter(ArcadeDronePhase.hovering);
          case ArcadeDronePhase.hovering:
          case ArcadeDronePhase.ready:
            _depart(theft: true);
            events.add(
              _isBoss ? ArcadeDroneEvent.bossCounter : ArcadeDroneEvent.escaped,
            );
          case ArcadeDronePhase.firing:
            if (_shotHit) {
              _enter(ArcadeDronePhase.exploding);
              _hits++;
              if (_isBoss) {
                events.add(
                  _hits >= _requiredHits
                      ? ArcadeDroneEvent.bossDestroyed
                      : ArcadeDroneEvent.bossHit,
                );
              } else {
                destroyed++;
                events.add(ArcadeDroneEvent.destroyed);
              }
            } else {
              _depart(theft: true);
              events.add(
                _isBoss
                    ? ArcadeDroneEvent.bossCounter
                    : ArcadeDroneEvent.escaped,
              );
            }
          case ArcadeDronePhase.exploding:
          case ArcadeDronePhase.departing:
            if (_isBoss && _hits >= _requiredHits) {
              _enter(ArcadeDronePhase.dormant);
            } else if (_isBoss &&
                enabled &&
                !changed &&
                _encounterSector == sector &&
                style == ArcadeDroneStyle.golem) {
              _energy = 0;
              _stolePoints = false;
              _enter(ArcadeDronePhase.hovering);
            } else if (enabled && style == ArcadeDroneStyle.golem) {
              _arrive(style, sector, bossHits);
            } else if (enabled) {
              _schedule();
            } else {
              _enter(ArcadeDronePhase.dormant);
            }
          case ArcadeDronePhase.rearming:
            if (enabled) {
              _arrive(style, sector, bossHits);
            } else {
              _enter(ArcadeDronePhase.dormant);
            }
          default:
            break;
        }
      }
    }
    return events;
  }

  ArcadeDroneFrame snapshot({double aheadSeconds = 0}) {
    final ahead = _playing && aheadSeconds.isFinite
        ? aheadSeconds.clamp(0.0, .1)
        : 0.0;
    return ArcadeDroneFrame(
      phase: _phase,
      style: _style,
      serial: _serial,
      age: math.min(_duration, _age + ahead),
      clock: _clock + ahead,
      charge: (_energy / energySeconds).clamp(0.0, 1.0),
      lockClock: _lockClock,
      departureEntry: _departureEntry,
      entrySide: _entrySide,
      hoverX: _hoverX,
      hoverY: _hoverY,
      shotHit: _shotHit,
      aimX: _aimX,
      aimY: _aimY,
      stolePoints: _stolePoints,
      sector: _encounterSector,
      hits: _hits,
      requiredHits: _requiredHits,
    );
  }
}
