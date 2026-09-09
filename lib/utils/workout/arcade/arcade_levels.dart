import 'arcade_drones.dart';

/// One story level is selected for the entire ride, independently of intensity.
/// IDs are stable presentation identifiers for future saved progression; they
/// are not workout IDs, competitive ranks, or changes to trainer resistance.
class ArcadeLevel {
  const ArcadeLevel._(
    this.index,
    this.id,
    this.title,
    this.description,
    this.accentArgb,
    this.bossStyle,
  );

  static const values = [
    ArcadeLevel._(
      0,
      'sunwheel',
      'Sunwheel Meadows',
      'Rolling groves and the first sparks of the chase.',
      0xff74ffd3,
      ArcadeDroneStyle.golem,
    ),
    ArcadeLevel._(
      1,
      'overgrown',
      'Overgrown Ruins',
      'Giant ferns reclaim an ancient cycling kingdom.',
      0xffa2e881,
      ArcadeDroneStyle.bramble,
    ),
    ArcadeLevel._(
      2,
      'copper',
      'Copper Dunes',
      'Sun-baked islands, sandstone and clockwork hunters.',
      0xffffcf79,
      ArcadeDroneStyle.duneScorpion,
    ),
    ArcadeLevel._(
      3,
      'frostline',
      'Frostline',
      'Crystal pines and frozen outposts above the clouds.',
      0xff8ee4ff,
      ArcadeDroneStyle.frostWarden,
    ),
    ArcadeLevel._(
      4,
      'stormworks',
      'Stormworks',
      'Wind-torn sky gardens and the lightning fleet.',
      0xffb99bff,
      ArcadeDroneStyle.stormRay,
    ),
    ArcadeLevel._(
      5,
      'eclipse',
      'Eclipse Citadel',
      'Luminous ruins in the Void Regent’s twilight realm.',
      0xffff95cf,
      ArcadeDroneStyle.voidRegent,
    ),
  ];

  final int index;
  final String id, title, description;
  final int accentArgb;
  final ArcadeDroneStyle bossStyle;
  int get number => index + 1;
  // Preserve the original three story IDs while adding a story for each boss.
  int get storyVariant => const [0, 3, 2, 4, 1, 5][index];
  static ArcadeLevel forStoryVariant(int variant) =>
      values[const [0, 4, 2, 1, 3, 5][variant % values.length]];
}

/// Enemy agility/variety grows during a ride; the story and scenery do not
/// change. Same charge time, aiming window and health budget at every tier.
class ArcadeDifficulty {
  static const secondsPerTier = 8 * 60;
  static int forRideSeconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return 0;
    return (seconds / secondsPerTier).floor().clamp(0, 5);
  }
}
