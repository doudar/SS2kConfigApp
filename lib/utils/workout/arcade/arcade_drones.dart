import 'dart:math' as math;

enum ArcadeDroneStyle { wheel, sentinel }

enum ArcadeDronePhase {
  dormant,
  entering,
  hovering,
  firing,
  exploding,
  departing,
  rearming,
}

enum ArcadeDroneEvent { fired, destroyed }

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
  });
  final ArcadeDronePhase phase;
  final ArcadeDroneStyle style;
  final int serial;
  final double age;
  final double clock;
  final double charge;
  final double lockClock;
  final double departureEntry;
  bool get visible =>
      phase != ArcadeDronePhase.dormant && phase != ArcadeDronePhase.rearming;
  String get status => switch (phase) {
    ArcadeDronePhase.entering => 'DRONE INBOUND',
    ArcadeDronePhase.hovering =>
      'BLASTER ${(charge * 100).floor()}% · HOLD TARGET TO FIRE',
    ArcadeDronePhase.firing => 'TARGET LOCKED · FIRING!',
    ArcadeDronePhase.exploding => 'DRONE DOWN!',
    ArcadeDronePhase.departing => 'DRONE RETREATING',
    _ => 'BLASTER REARMING',
  };
}

/// Combat advances on accepted workout time, never on painter callbacks.
/// One drone at a time keeps flight paths and reward feedback easy to follow.
class ArcadeDrones {
  static const energySeconds = 6.0;
  static const entrySeconds = 1.8;
  static const shotSeconds = .45;
  static const explosionSeconds = 1.1;
  static const departureSeconds = 1.4;
  static const rearmSeconds = 1.2;
  ArcadeDronePhase _phase = ArcadeDronePhase.dormant;
  ArcadeDroneStyle _style = ArcadeDroneStyle.wheel;
  double _age = 0, _clock = 0, _energy = 0, _lockClock = 0, _departureEntry = 1;
  int _serial = 0;
  int? _sector;
  bool _playing = false;
  int destroyed = 0;

  void reset() {
    _phase = ArcadeDronePhase.dormant;
    _age = _clock = _energy = _lockClock = 0;
    _departureEntry = 1;
    _serial = destroyed = 0;
    _sector = null;
    _playing = false;
  }

  void _enter(ArcadeDronePhase phase) {
    _phase = phase;
    _age = 0;
  }

  double get _duration => switch (_phase) {
    ArcadeDronePhase.entering => entrySeconds,
    ArcadeDronePhase.firing => shotSeconds,
    ArcadeDronePhase.exploding => explosionSeconds,
    ArcadeDronePhase.departing => departureSeconds,
    ArcadeDronePhase.rearming => rearmSeconds,
    _ => double.infinity,
  };

  List<ArcadeDroneEvent> update({
    required double seconds,
    required bool playing,
    required bool enabled,
    required bool onTarget,
    required int sector,
    required ArcadeDroneStyle style,
    bool skipped = false,
  }) {
    final events = <ArcadeDroneEvent>[];
    final changed = _sector != null && _sector != sector;
    _sector = sector;
    _playing = playing;
    if ((!enabled || changed || skipped) &&
        (_phase == ArcadeDronePhase.entering ||
            _phase == ArcadeDronePhase.hovering)) {
      // Preserve the old drone's exact flight position as it retreats.
      _departureEntry = _phase == ArcadeDronePhase.entering
          ? (_age / entrySeconds).clamp(0.0, 1.0)
          : 1;
      _lockClock = _clock;
      _energy = 0;
      _enter(ArcadeDronePhase.departing);
    }
    if (!playing) return events;
    if (_phase == ArcadeDronePhase.dormant && enabled) {
      _style = style;
      _serial++;
      _energy = 0;
      _enter(ArcadeDronePhase.entering);
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
      final untilShot = charging && _phase == ArcadeDronePhase.hovering
          ? math.max(0.0, energySeconds - _energy)
          : double.infinity;
      final step = math.min(
        remaining,
        math.min(math.max(0.0, _duration - _age), untilShot),
      );
      _age += step;
      _clock += step;
      if (charging) _energy = math.min(energySeconds, _energy + step);
      remaining -= step;
      if (_phase == ArcadeDronePhase.hovering &&
          _energy >= energySeconds - 1e-9) {
        _lockClock = _clock;
        _energy = 0;
        _enter(ArcadeDronePhase.firing);
        events.add(ArcadeDroneEvent.fired);
      } else if (_age >= _duration - 1e-9) {
        switch (_phase) {
          case ArcadeDronePhase.entering:
            _enter(ArcadeDronePhase.hovering);
          case ArcadeDronePhase.firing:
            _enter(ArcadeDronePhase.exploding);
            destroyed++;
            events.add(ArcadeDroneEvent.destroyed);
          case ArcadeDronePhase.exploding:
          case ArcadeDronePhase.departing:
            _enter(
              enabled ? ArcadeDronePhase.rearming : ArcadeDronePhase.dormant,
            );
          case ArcadeDronePhase.rearming:
            if (enabled) {
              _style = style;
              _serial++;
              _energy = 0;
              _enter(ArcadeDronePhase.entering);
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
    );
  }
}
