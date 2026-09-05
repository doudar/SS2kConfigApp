import 'dart:math' as math;

enum ArcadeStoryPhase { opening, chase, homecoming }

/// One cast per workout, retained when switching views or pausing.
class ArcadeStory {
  ArcadeStory(this.variant);
  factory ArcadeStory.random() => ArcadeStory(math.Random().nextInt(3));
  final int variant;

  String get title => switch (variant % 3) {
    0 => 'THE STOLEN SUN',
    1 => 'THE LAST LANTERN',
    _ => 'THE GREAT WHEEL HEIST',
  };
  String get crew => switch (variant % 3) {
    0 => 'the Sunwheel mechanics',
    1 => 'the Lantern Couriers',
    _ => 'the Little Spokes crew',
  };
  String get home => switch (variant % 3) {
    0 => 'SUNWHEEL VILLAGE',
    1 => 'LANTERN HARBOR',
    _ => 'LITTLE SPOKES WORKSHOP',
  };
  String get stolen => switch (variant % 3) {
    0 => 'the village sun dynamo',
    1 => 'the harbor beacon',
    _ => 'every wheel in the workshop',
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
      ? 'The Gear Golem is broken. $crew are home. You brought the light back.'
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
    ArcadeStoryPhase.chase => 'CHASE THE GEAR GOLEM',
    ArcadeStoryPhase.homecoming => 'THE ROAD HOME',
  };

  String get caption => switch (phase) {
    ArcadeStoryPhase.opening when progress < .28 =>
      'A quiet morning. ${story.crew} are getting ready to ride.',
    ArcadeStoryPhase.opening when progress < .65 =>
      'The Gear Golem stole ${story.stolen} and trapped ${story.crew}!',
    ArcadeStoryPhase.opening =>
      'Follow the sparks! Warm up at your target; your interval energy breaks its gears.',
    ArcadeStoryPhase.chase =>
      'Stay with your target. Every secured sector opens the way to ${story.crew}.',
    ArcadeStoryPhase.homecoming when progress < .5 =>
      bosses > 0
          ? 'The forge has fallen. ${story.crew} are following your light home.'
          : sectors > 0
          ? 'An escape route is open. Guide ${story.crew} home.'
          : 'The crew found shelter ahead. Ride with them toward home.',
    ArcadeStoryPhase.homecoming =>
      '${story.home} is just ahead. Follow your target and finish the ride together.',
  };
}
