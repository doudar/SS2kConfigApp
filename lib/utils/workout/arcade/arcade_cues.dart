import 'arcade_drones.dart';

/// Gameplay cues carry priorities so rewards win over routine feedback.
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
  heroRelief(3, 1250),
  wheelAttack(3, 700),
  sentinelAttack(3, 720),
  beetleAttack(3, 800),
  waspAttack(3, 620),
  orbAttack(3, 900),
  golemAttack(3, 1100),
  brambleAttack(3, 1000),
  duneScorpionAttack(3, 850),
  frostWardenAttack(3, 1100),
  stormRayAttack(3, 950),
  voidRegentAttack(3, 1200);

  const ArcadeCue(this.priority, this.milliseconds);
  final int priority;
  final int milliseconds;

  static ArcadeCue attackFor(ArcadeDroneStyle style) => switch (style) {
    ArcadeDroneStyle.wheel => wheelAttack,
    ArcadeDroneStyle.sentinel => sentinelAttack,
    ArcadeDroneStyle.beetle => beetleAttack,
    ArcadeDroneStyle.wasp => waspAttack,
    ArcadeDroneStyle.orb => orbAttack,
    ArcadeDroneStyle.golem => golemAttack,
    ArcadeDroneStyle.bramble => brambleAttack,
    ArcadeDroneStyle.duneScorpion => duneScorpionAttack,
    ArcadeDroneStyle.frostWarden => frostWardenAttack,
    ArcadeDroneStyle.stormRay => stormRayAttack,
    ArcadeDroneStyle.voidRegent => voidRegentAttack,
  };
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
    ArcadeCue.wheelAttack => .24,
    ArcadeCue.sentinelAttack => .22,
    ArcadeCue.beetleAttack => .26,
    ArcadeCue.waspAttack => .22,
    ArcadeCue.orbAttack => .24,
    ArcadeCue.golemAttack => .30,
    ArcadeCue.brambleAttack => .28,
    ArcadeCue.duneScorpionAttack => .27,
    ArcadeCue.frostWardenAttack => .25,
    ArcadeCue.stormRayAttack => .27,
    ArcadeCue.voidRegentAttack => .28,
  };
}
