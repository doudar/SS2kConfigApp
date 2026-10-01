import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_dialogue.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_cues.dart';

void main() {
  final story = ArcadeStory(0);
  ArcadeStoryFrame frame(
    double seconds, {
    double total = 600,
    bool endless = false,
    int bosses = 0,
    int sectors = 0,
  }) => story.frame(
    seconds: seconds,
    total: total,
    endless: endless,
    bosses: bosses,
    sectors: sectors,
  );

  test('opening, chase and homecoming follow the workout clock', () {
    expect(frame(0).phase, ArcadeStoryPhase.opening);
    expect(frame(20).caption, contains('stole'));
    expect(frame(50).caption, contains('Warm up'));
    expect(frame(60).phase, ArcadeStoryPhase.chase);
    expect(frame(539.9).phase, ArcadeStoryPhase.chase);
    expect(frame(540).phase, ArcadeStoryPhase.homecoming);
    expect(frame(600).progress, 1);
    expect(frame(10000).progress, 1);
    expect(frame(0).progress, 0, reason: 'A restart returns to the opening');
  });

  test(
    'short workouts have non-overlapping chapters; endless rides have no false finish',
    () {
      expect(frame(9, total: 30).phase, ArcadeStoryPhase.opening);
      expect(frame(10, total: 30).phase, ArcadeStoryPhase.chase);
      expect(frame(20, total: 30).phase, ArcadeStoryPhase.homecoming);
      expect(frame(7200, endless: true).phase, ArcadeStoryPhase.chase);
      expect(frame(0, total: 0).progress, 0);
      expect(
        frame(double.nan, total: double.infinity).progress.isFinite,
        isTrue,
      );
    },
  );

  test('six distinct stories retain the original three identities', () {
    final stories = [for (var i = 0; i < 6; i++) ArcadeStory(i)];
    expect(stories.map((s) => s.title).toSet(), hasLength(6));
    expect(stories.map((s) => s.crew).toSet(), hasLength(6));
    expect(stories.map((s) => s.stolen).toSet(), hasLength(6));
    expect(stories.map((s) => s.home).toSet(), hasLength(6));
    expect(stories.map((s) => s.bossName).toSet(), hasLength(6));
    expect(stories.take(3).map((s) => s.title), [
      'THE STOLEN SUN',
      'THE LAST LANTERN',
      'THE GREAT WHEEL HEIST',
    ]);
    expect(stories.take(3).map((s) => s.crew), [
      'the Sunwheel mechanics',
      'the Lantern Couriers',
      'the Little Spokes crew',
    ]);
    expect(stories.take(3).map((s) => s.stolen), [
      'the village sun dynamo',
      'the harbor beacon',
      'every wheel in the workshop',
    ]);
  });

  test('a boss victory is only described when earned', () {
    expect(story.ending(1, 1), contains('Gear Golem is defeated'));
    expect(story.ending(0, 1), contains('escape route'));
    expect(story.ending(0, 0), contains('shelter'));
    expect(frame(550, bosses: 0).caption, isNot(contains('has fallen')));
    expect(frame(550, bosses: 1).caption, contains('Gear Golem has fallen'));
  });

  test('a fresh story never immediately repeats the excluded ride', () {
    for (var previous = -6; previous < 12; previous++) {
      for (var attempt = 0; attempt < 20; attempt++) {
        final next = ArcadeStory.random(excluding: previous);
        expect(next.variant, inInclusiveRange(0, 5));
        expect(next.variant, isNot(previous % 6));
      }
    }
    expect(ArcadeStory(8).variant, 2);
    expect(ArcadeStory(-1).variant, 5);
  });

  test('every villain is consistent in dialogue, chase and earned ending', () {
    final speeches = <String>{};
    for (var variant = 0; variant < 6; variant++) {
      final quest = ArcadeStory(variant);
      final villain = ArcadeDialogue.opening(quest, 1);
      expect(villain.speaker, ArcadeSpeaker.golem);
      expect(villain.name, quest.bossName.toUpperCase());
      expect(villain.semantics, startsWith('${quest.bossName.toUpperCase()}:'));
      expect(villain.cue, ArcadeCue.golemLaugh);
      speeches.add(villain.text);
      expect(quest.level.storyVariant, variant);
      final chase = quest.frame(
        seconds: 120,
        total: 600,
        endless: false,
        bosses: 0,
        sectors: 1,
        openingSeen: true,
      );
      expect(chase.heading, contains(quest.bossName.toUpperCase()));
      expect(quest.ending(1, 1), contains('${quest.bossName} is defeated'));
      expect(quest.ending(0, 1), isNot(contains('defeated')));
      final crew = ArcadeDialogue.ending(2, recovered: true, story: quest);
      expect(crew.speaker, ArcadeSpeaker.crew);
      expect(crew.cue, ArcadeCue.crewCheer);
      expect(
        ArcadeDialogue.ending(2, recovered: false, story: quest).text,
        'Together all the way! Woo-hoo!',
      );
    }
    expect(speeches, hasLength(6));
  });
}
