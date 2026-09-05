import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_intro.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_session.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    void Function(bool) completed, {
    bool reduced = false,
  }) async {
    final session = ArcadeSession()..effectsEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => completed(
                await ArcadeIntro.show(context, session, session.story),
              ),
              child: const Text('PLAY'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('PLAY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opening gates start; skip returns a single start decision', (
    tester,
  ) async {
    final decisions = <bool>[];
    await open(tester, decisions.add);
    expect(decisions, isEmpty);
    expect(find.text('Your workout starts after this scene.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('arcade-intro-start')));
    await tester.pumpAndSettle();
    expect(decisions, [true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back cancels instead of starting a ride', (tester) async {
    final decisions = <bool>[];
    await open(tester, decisions.add);
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(decisions, [false]);
  });

  testWidgets('opening dialogue follows the cast with reduced motion', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await open(tester, (_) {}, reduced: true);
    expect(find.bySemanticsLabel(RegExp('THE CREW:')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.bySemanticsLabel(RegExp('GEAR GOLEM:')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(
      find.bySemanticsLabel(RegExp('Help! Follow the sparks!')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.bySemanticsLabel(RegExp('YOU: Hang on, crew')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backgrounding pauses the opening; completion starts once', (
    tester,
  ) async {
    final decisions = <bool>[];
    await open(tester, decisions.add, reduced: true);
    await tester.pump(const Duration(seconds: 2));
    expect(decisions, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(decisions, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 17));
    await tester.pumpAndSettle();
    expect(decisions, [true]);
    expect(tester.takeException(), isNull);
  });

  test(
    'the opening cast survives a restart and is not repeated in the world',
    () {
      final game = ArcadeSession();
      final segments = [
        WorkoutSegment(
          type: SegmentType.steadyState,
          duration: 120,
          powerLow: .7,
        ),
      ];
      void sample(double seconds, bool playing) => game.update(
        segments: segments,
        seconds: seconds,
        playing: playing,
        watts: 140,
        target: 140,
        freshSignal: true,
      );
      sample(0, false);
      final opening = ArcadeStory(2);
      game.stageOpening(opening);
      sample(0, true);
      expect(identical(game.story, opening), isTrue);
      expect(game.openingSeen, isTrue);
      sample(1, true);
      sample(1, false);
      sample(1, true);
      expect(
        game.openingSeen,
        isTrue,
        reason: 'Resuming must not replay the cutscene',
      );
      expect(
        game.story
            .frame(
              seconds: 1,
              total: 120,
              endless: false,
              bosses: 0,
              sectors: 0,
              openingSeen: game.openingSeen,
            )
            .phase,
        ArcadeStoryPhase.chase,
      );
      final next = ArcadeStory(1);
      game.stageOpening(next);
      sample(0, true);
      expect(identical(game.story, next), isTrue);
      expect(game.openingSeen, isTrue);
      expect(game.score, 0);
    },
  );

  test('a cancelled opening leaves the existing quest intact', () {
    final game = ArcadeSession();
    final original = game.story;
    game.stageOpening(ArcadeStory(1));
    game.cancelStagedOpening();
    expect(identical(game.story, original), isTrue);
    expect(game.openingSeen, isFalse);
  });
}
