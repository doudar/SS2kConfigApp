import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';

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

  test('three casts and stolen objects vary the story', () {
    final stories = [for (var i = 0; i < 3; i++) ArcadeStory(i)];
    expect(stories.map((s) => s.title).toSet(), hasLength(3));
    expect(stories.map((s) => s.crew).toSet(), hasLength(3));
    expect(stories.map((s) => s.stolen).toSet(), hasLength(3));
  });

  test('a boss victory is only described when earned', () {
    expect(story.ending(1, 1), contains('Golem is broken'));
    expect(story.ending(0, 1), contains('escape route'));
    expect(story.ending(0, 0), contains('shelter'));
    expect(frame(550, bosses: 0).caption, isNot(contains('forge has fallen')));
    expect(frame(550, bosses: 1).caption, contains('forge has fallen'));
  });
}
