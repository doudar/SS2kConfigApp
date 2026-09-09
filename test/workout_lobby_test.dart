import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby.dart';
import 'package:ss2kconfigapp/utils/workout/workout_lobby_choice.dart';

WorkoutLobbyChoice choice(String name, String blocks) => WorkoutLobbyChoice(
  content:
      '<workout_file><name>$name</name><workout>$blocks</workout></workout_file>',
  source: 'YOUR LIBRARY',
);

void main() {
  testWidgets(
    'selection returns to Start; FTP and browsing do not start a ride',
    (tester) async {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final easy = choice(
        'Recovery Spin',
        '<SteadyState Duration="120" Power="0.5"/>',
      );
      final hard = choice(
        'Tempo Tuesday',
        '<Warmup Duration="60" PowerLow="0.4" PowerHigh="0.7"/><SteadyState Duration="120" Power="0.85"/>',
      );
      var selected = easy;
      var ftp = 200.0;
      var starts = 0;
      var browses = 0;
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => WorkoutLobby(
                name: selected.name,
                segments: selected.workout.segments,
                endless: selected.name == 'Free Ride',
                ftp: ftp,
                onStart: () => starts++,
                onFtp: (value) => update(() => ftp = value),
                onSelect: (value) => update(() => selected = value),
                onBrowse: () => browses++,
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
      expect(find.text('First interval · 100 W · 2:00'), findsOneWidget);
      await tester.ensureVisible(find.text('Tempo Tuesday'));
      await tester.tap(find.text('Tempo Tuesday'));
      await tester.pumpAndSettle();
      expect(selected, hard);
      expect(starts, 0);
      expect(loads, 1);
      expect(find.text('First interval · 80→140 W · 1:00'), findsOneWidget);
      expect(
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('workout-lobby')),
            )
            .controller!
            .offset,
        0,
      );
      await tester.tap(find.text('FTP 200 W · Adjust'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(250);
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(ftp, 250);
      expect(find.text('First interval · 100→175 W · 1:00'), findsOneWidget);
      await tester.ensureVisible(find.text('Browse workouts'));
      await tester.tap(find.text('Browse workouts'));
      expect(browses, 1);
      expect(starts, 0);
      await tester.ensureVisible(find.text('Choose free ride'));
      await tester.tap(find.text('Choose free ride'));
      await tester.pumpAndSettle();
      expect(find.text('Open-ended'), findsOneWidget);
      expect(find.text('First interval · Free ride'), findsOneWidget);
      expect(starts, 0);
      await tester.tap(find.text('START WORKOUT'));
      expect(starts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty and failed shelves keep browse available and Start disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkoutLobby(
              name: '',
              segments: const [],
              endless: false,
              ftp: 200,
              onStart: () => fail('An empty workout cannot start'),
              onFtp: (_) {},
              onSelect: (_) {},
              onBrowse: () {},
              loadChoices: () async => throw Exception('Unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose your next ride'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('workout-lobby-start')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Browse workouts'));
      expect(find.text('Browse workouts').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lobby fits phones, landscape and desktop with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = choice(
      'Tempo Tuesday',
      '<Warmup Duration="300" PowerLow="0.4" PowerHigh="0.7"/><SteadyState Duration="600" Power="0.85"/><SteadyState Duration="120" Power="0.5"/><SteadyState Duration="600" Power="0.85"/><Cooldown Duration="300" PowerLow="0.4" PowerHigh="0.7"/>',
    );
    final recovery = choice(
      'Recovery Spin',
      '<SteadyState Duration="1200" Power="0.5"/>',
    );
    const capture = bool.fromEnvironment('WORKOUT_LOBBY_SCREENSHOTS');
    if (capture) {
      await tester.runAsync(() async {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Roboto')..addFont(
              File(
                'C:/Windows/Fonts/segoeui.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      });
    }
    for (final size in [
      const Size(320, 420),
      const Size(844, 280),
      const Size(1200, 800),
      const Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(capture ? 1 : 1.5),
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: WorkoutLobby(
                  name: capture
                      ? selected.name
                      : 'A long workout title that should wrap safely on small screens',
                  segments: selected.workout.segments,
                  endless: false,
                  ftp: 200,
                  onStart: () {},
                  onFtp: (_) {},
                  onSelect: (_) {},
                  onBrowse: () {},
                  loadChoices: () async => [selected, recovery],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (capture && size.height > 700) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/workout-lobby-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('START WORKOUT'));
      expect(find.text('START WORKOUT').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
