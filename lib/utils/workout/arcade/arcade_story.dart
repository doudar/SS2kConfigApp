import 'dart:math' as math;
import 'arcade_drones.dart';
import 'arcade_levels.dart';

enum ArcadeStoryPhase { opening, chase, homecoming }

/// One cast per workout, retained when switching views or pausing.
class ArcadeStory {
  ArcadeStory(int variant) : variant = variant % 6;
  factory ArcadeStory.random({int? excluding}) {
    final random = math.Random();
    if (excluding == null) return ArcadeStory(random.nextInt(6));
    final previous = excluding % 6;
    final choice = random.nextInt(5);
    return ArcadeStory(choice >= previous ? choice + 1 : choice);
  }
  final int variant;
  ArcadeLevel get level => ArcadeLevel.forStoryVariant(variant);
  String get bossName => level.bossStyle.targetName;

  String get title => switch (variant) {
    0 => 'THE STOLEN SUN',
    1 => 'THE LAST LANTERN',
    2 => 'THE GREAT WHEEL HEIST',
    3 => 'THE VERDANT VAULT',
    4 => 'HEART OF WINTER',
    _ => 'THE MIDNIGHT RELAY',
  };
  String get crew => switch (variant) {
    0 => 'the Sunwheel mechanics',
    1 => 'the Lantern Couriers',
    2 => 'the Little Spokes crew',
    3 => 'the Ruin Pathfinders',
    4 => 'the Frostline Rangers',
    _ => 'the Moonlight Messengers',
  };
  String get home => switch (variant) {
    0 => 'SUNWHEEL VILLAGE',
    1 => 'LANTERN HARBOR',
    2 => 'LITTLE SPOKES WORKSHOP',
    3 => 'THE VERDANT REFUGE',
    4 => 'FROSTLINE STATION',
    _ => 'MOONLIGHT DEPOT',
  };
  String get stolen => switch (variant) {
    0 => 'the village sun dynamo',
    1 => 'the harbor beacon',
    2 => 'every wheel in the workshop',
    3 => 'the seedlight core',
    4 => 'the mountain hearth',
    _ => 'the last starwheel',
  };
  String get _restoration => switch (variant) {
    0 => 'Sunwheel Village has its sunshine back',
    1 => 'the harbor beacon shines again',
    2 => 'the workshop wheels are rolling again',
    3 => 'the seedlight is bringing the gardens back to life',
    4 => 'the mountain hearth is keeping everyone warm',
    _ => 'the starwheel is lighting the way through the night',
  };

  ArcadeStoryFrame frame({
    required double seconds,
    required double total,
    required bool endless,
    required int bosses,
    required int sectors,
    bool openingSeen = false,
  }) {
    final time = seconds.isFinite ? math.max(0.0, seconds) : 0.0;
    final duration = total.isFinite ? math.max(0.0, total) : 0.0;
    // Short rides get shorter chapters; neither depends on segment labels.
    final chapter = endless ? 60.0 : math.min(60.0, duration / 3);
    final phase = !openingSeen && chapter > 0 && time < chapter
        ? ArcadeStoryPhase.opening
        : !endless && chapter > 0 && time >= duration - chapter
        ? ArcadeStoryPhase.homecoming
        : ArcadeStoryPhase.chase;
    final progress = chapter <= 0
        ? 0.0
        : switch (phase) {
            ArcadeStoryPhase.opening => (time / chapter).clamp(0.0, 1.0),
            ArcadeStoryPhase.homecoming =>
              ((time - duration + chapter) / chapter).clamp(0.0, 1.0),
            ArcadeStoryPhase.chase => 0.0,
          };
    return ArcadeStoryFrame(this, phase, progress, bosses, sectors);
  }

  String ending(int bosses, int sectors) => bosses > 0
      ? '$bossName is defeated. $crew are home, and $_restoration.'
      : sectors > 0
      ? 'Your energy opened an escape route. $crew made it home!'
      : '$crew found shelter. Every journey starts somewhere. Tonight, you ride home together.';
}

class ArcadeStoryFrame {
  const ArcadeStoryFrame(
    this.story,
    this.phase,
    this.progress,
    this.bosses,
    this.sectors,
  );
  final ArcadeStory story;
  final ArcadeStoryPhase phase;
  final double progress;
  final int bosses;
  final int sectors;

  String get heading => switch (phase) {
    ArcadeStoryPhase.opening => story.title,
    ArcadeStoryPhase.chase => 'CHASE ${story.bossName.toUpperCase()}',
    ArcadeStoryPhase.homecoming => 'THE ROAD HOME',
  };

  String get caption => switch (phase) {
    ArcadeStoryPhase.opening when progress < .28 =>
      'A new ride begins. ${story.crew} are getting ready to ride.',
    ArcadeStoryPhase.opening when progress < .65 =>
      '${story.bossName} stole ${story.stolen} and trapped ${story.crew}!',
    ArcadeStoryPhase.opening =>
      'Follow the sparks! Warm up at your target; your interval energy breaks the guardian’s armor.',
    ArcadeStoryPhase.chase =>
      'Stay with your target. Every secured sector opens the way to ${story.crew}.',
    ArcadeStoryPhase.homecoming when progress < .5 =>
      bosses > 0
          ? '${story.bossName} has fallen. ${story.crew} are following your light home.'
          : sectors > 0
          ? 'An escape route is open. Guide ${story.crew} home.'
          : 'The crew found shelter ahead. Ride with them toward home.',
    ArcadeStoryPhase.homecoming =>
      '${story.home} is just ahead. Follow your target and finish the ride together.',
  };
}
