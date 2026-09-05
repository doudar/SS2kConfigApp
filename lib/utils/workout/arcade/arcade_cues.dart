/// Gameplay cues, ordered by importance so rewards win over routine feedback.
enum ArcadeCue {
  pickup(1, 180),
  bolt(1, 240),
  combo(2, 600),
  droneHit(2, 1800),
  bossApproach(3, 1100),
  sectorClear(4, 850),
  bossDefeat(5, 1800),
  crewHello(3, 950),
  crewAlarm(3, 1100),
  golemLaugh(4, 2100),
  heroReady(3, 1100),
  crewCheer(4, 1800),
  heroRelief(3, 1250);

  const ArcadeCue(this.priority, this.milliseconds);
  final int priority;
  final int milliseconds;
  // The drone impact reuses the existing burst/fanfare at a lower volume.
  String get asset =>
      'sounds/arcade_fx_${this == ArcadeCue.droneHit ? 'bossDefeat' : name}.wav';
  double get volume => switch (this) {
    ArcadeCue.pickup => .20,
    ArcadeCue.bolt => .14,
    ArcadeCue.combo => .18,
    ArcadeCue.droneHit => .22,
    ArcadeCue.bossApproach => .28,
    ArcadeCue.sectorClear => .34,
    ArcadeCue.bossDefeat => .38,
    ArcadeCue.crewHello => .32,
    ArcadeCue.crewAlarm => .34,
    ArcadeCue.golemLaugh => .42,
    ArcadeCue.heroReady => .36,
    ArcadeCue.crewCheer => .36,
    ArcadeCue.heroRelief => .32,
  };
}
