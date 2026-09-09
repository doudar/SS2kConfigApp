import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_drones.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_levels.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  test('six story levels each have a distinct fixed boss and world', () {
    expect(ArcadeLevel.values.map((l) => l.id).toSet(), hasLength(6));
    expect(ArcadeLevel.values.map((l) => l.bossStyle).toSet(), hasLength(6));
    expect(ArcadeLevel.values.every((l) => l.bossStyle.isBoss), isTrue);
    for (final level in ArcadeLevel.values) {
      expect(ArcadeLevel.forStoryVariant(level.storyVariant), same(level));
    }
    expect(ArcadeDifficulty.forRideSeconds(479.99), 0);
    expect(ArcadeDifficulty.forRideSeconds(480), 1);
    expect(ArcadeDifficulty.forRideSeconds(2400), 5);
    expect(ArcadeDifficulty.forRideSeconds(86400), 5);
    for (final invalid in [-1.0, double.nan, double.infinity]) {
      expect(ArcadeDifficulty.forRideSeconds(invalid), 0);
    }
  });

  late ArcadeSession game;
  late List<WorkoutSegment> segments;
  setUp(() {
    game = ArcadeSession();
    segments = [
      WorkoutSegment(
        type: SegmentType.steadyState,
        duration: 7200,
        powerLow: .7,
      ),
    ];
  });
  void update(double seconds, {double? ridden, bool playing = true}) =>
      game.update(
        segments: segments,
        seconds: seconds,
        playing: playing,
        watts: 140,
        target: 140,
        freshSignal: true,
        riddenSeconds: ridden,
      );

  test(
    'difficulty increases without changing the story; skips do not advance it',
    () {
      game.stageOpening(ArcadeStory(4));
      update(0, ridden: 0);
      final story = game.story;
      final level = game.level;
      update(479, ridden: 479);
      expect(game.difficultyIndex, 0);
      game.willSkip();
      update(1800, ridden: 479);
      expect(game.difficultyIndex, 0);
      update(1801, ridden: 480);
      expect(game.difficultyIndex, 1);
      expect(game.story, same(story));
      expect(game.level, same(level));
      update(1801, ridden: 480, playing: false);
      expect(game.riddenSeconds, 480);
    },
  );

  test('resuming restores story plus independent difficulty', () {
    game.restoreStoryPreference(4);
    update(3200, ridden: 1930, playing: false);
    expect(game.story.variant, 4);
    expect(game.openingSeen, true);
    expect(game.level.bossStyle, ArcadeDroneStyle.frostWarden);
    expect(game.difficultyIndex, 4);
    expect(game.score, 0);
  });

  test(
    'late preferences restore the cast without replaying the first-minute heist',
    () {
      update(20, ridden: 20, playing: false);
      game.restoreStoryPreference(5);
      expect(game.story.variant, 5);
      expect(game.openingSeen, true);
      final frame = game.story.frame(
        seconds: 20,
        total: 7200,
        endless: false,
        bosses: 0,
        sectors: 0,
        openingSeen: game.openingSeen,
      );
      expect(frame.phase, ArcadeStoryPhase.chase);
    },
  );

  test('fresh rides exclude last started story and reset difficulty', () {
    game.restoreStoryPreference(2);
    update(0, playing: false);
    expect(game.story.variant, isNot(2));
    final opening = game.story;
    game.stageOpening(opening);
    update(0);
    for (var i = 1; i <= 480; i++) {
      update(i.toDouble());
    }
    expect(game.difficultyIndex, 1);
    game.willSkip();
    update(2000);
    expect(game.riddenSeconds, 480);
    update(2000, playing: false);
    update(0, ridden: 0, playing: false);
    expect(game.difficultyIndex, 0);
    expect(game.story.variant, isNot(opening.variant));
    expect(game.score, 0);
  });

  test(
    'each story summons its boss at any difficulty without changing ERG',
    () {
      for (final level in ArcadeLevel.values) {
        final bossGame = ArcadeSession()..droneInteractionEnabled = true;
        final bossSegments = [
          WorkoutSegment(
            type: SegmentType.steadyState,
            duration: 3600,
            powerLow: 1.2,
          ),
        ];
        bossGame.stageOpening(ArcadeStory(level.storyVariant));
        bossGame.update(
          segments: bossSegments,
          seconds: 0,
          riddenSeconds: 2000,
          playing: true,
          watts: 240,
          target: 240,
          freshSignal: true,
        );
        expect(bossGame.drones.snapshot().style, level.bossStyle);
        expect(bossGame.drones.snapshot().levelIndex, 4);
        expect(bossSegments.single.powerLow, 1.2);
        expect(bossGame.drones.snapshot().requiredHits, 6);
      }
    },
  );
}
