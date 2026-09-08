import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_lobby.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_lobby_workout.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_rider_appearance.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_story.dart';

void main() {
  ArcadeLobbyWorkout workout(String name, String blocks) => ArcadeLobbyWorkout(
    content:
        '<workout_file><name>$name</name><workout>$blocks</workout></workout_file>',
    source: 'YOUR LIBRARY',
  );

  testWidgets(
    'loading a shelf choice changes the preview, never starts the ride',
    (tester) async {
      tester.view.physicalSize = const Size(390, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final easy = workout(
        'Forest ride',
        '<SteadyState Duration="120" Power="0.5"/>',
      );
      final hard = workout(
        'Forge ride',
        '<Warmup Duration="60" PowerLow="0.4" PowerHigh="0.7"/>'
            '<SteadyState Duration="120" Power="1.2"/>',
      );
      var selected = easy;
      var loads = 0;
      var starts = 0;
      var browses = 0;
      var customizations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ArcadeLobby(
                name: selected.name,
                segments: selected.workout.segments,
                endless: false,
                ftp: 200,
                story: ArcadeStory(0),
                rider: const ArcadeRiderAppearance(),
                onStart: () => starts++,
                onCustomize: () => customizations++,
                onFtp: () {},
                onBrowse: () => browses++,
                onSelect: (choice) => setState(() => selected = choice),
                loadChoices: () async {
                  loads++;
                  return [easy, hard];
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(starts, 0);
      expect(find.text('Forest ride'), findsOneWidget);
      expect(find.text('First sector · 100 W · 2:00'), findsOneWidget);
      await tester.ensureVisible(find.text('Forge ride'));
      await tester.tap(find.text('Forge ride'));
      await tester.pumpAndSettle();
      expect(selected, hard);
      expect(starts, 0);
      expect(
        loads,
        1,
      ); // Telemetry/selection rebuilds never reload the library.
      expect(find.text('First sector · 80→140 W · 1:00'), findsOneWidget);
      expect(find.text('1 forge sector'), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('arcade-lobby')),
      );
      expect(scroll.controller!.offset, 0);
      await tester.tap(find.text('START QUEST'));
      expect(starts, 1);
      await tester.ensureVisible(find.text('Browse workouts'));
      await tester.tap(find.text('Browse workouts'));
      expect(browses, 1);
      await tester.ensureVisible(find.text('Style your rider'));
      await tester.tap(find.text('Style your rider'));
      expect(customizations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lobby scrolls on small screens and supports large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = workout(
      'A long workout title that should wrap safely',
      '<SteadyState Duration="120" Power="0.5"/>'
          '<SteadyState Duration="120" Power="0.7"/>'
          '<SteadyState Duration="120" Power="0.9"/>'
          '<SteadyState Duration="120" Power="1.2"/>',
    );
    for (final size in [
      const Size(320, 420),
      const Size(844, 280),
      const Size(1200, 700),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: ArcadeLobby(
                name: selected.name,
                segments: selected.workout.segments,
                endless: false,
                ftp: 200,
                story: ArcadeStory(2),
                rider: const ArcadeRiderAppearance(),
                onStart: () {},
                onCustomize: () {},
                onFtp: () {},
                onSelect: (_) {},
                onBrowse: () {},
                loadChoices: () async => [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('START QUEST'));
      expect(find.text('START QUEST').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an empty lobby offers loading with Start disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArcadeLobby(
            name: '',
            segments: const [],
            endless: false,
            ftp: 200,
            story: ArcadeStory(0),
            rider: const ArcadeRiderAppearance(),
            onStart: null,
            onCustomize: () {},
            onFtp: () {},
            onSelect: (_) {},
            onBrowse: () {},
            loadChoices: () async => [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose your first quest'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('arcade-start-quest')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Browse workouts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
