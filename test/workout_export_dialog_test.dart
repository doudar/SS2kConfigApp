import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_export_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget dialog, {
    double textScale = 1,
    Brightness brightness = Brightness.light,
    void Function(Object?)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<Object>(
                  context: context,
                  builder: (_) => dialog,
                );
                onResult?.call(result);
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  WorkoutExportDialog chooser({bool strava = true, bool intervals = true}) =>
      WorkoutExportDialog(
        workoutName: 'Long threshold intervals and a well-earned cooldown',
        duration: '01:12:34',
        averagePower: 218,
        averageCadence: 88,
        stravaConnected: strava,
        intervalsConnected: intervals,
      );

  testWidgets(
    'save chooser fits narrow, short and desktop layouts with large text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final size in [
        const Size(320, 568),
        const Size(844, 330),
        const Size(1200, 800),
      ]) {
        for (final brightness in Brightness.values) {
          tester.view.physicalSize = size;
          await open(tester, chooser(), textScale: 2, brightness: brightness);
          expect(find.text('218 W'), findsOneWidget);
          expect(find.text('88 rpm'), findsOneWidget);
          await tester.ensureVisible(find.text('Discard workout'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Discard workout'));
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets('each destination returns the existing export action', (
    tester,
  ) async {
    for (final entry in {
      'Save FIT file': 'save',
      'Strava': 'strava',
      'Intervals.icu': 'intervals',
      'Discard workout': 'discard',
    }.entries) {
      Object? choice;
      await open(tester, chooser(), onResult: (value) => choice = value);
      await tester.ensureVisible(find.text(entry.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(choice, entry.value);
    }
  });

  testWidgets('disconnected services are omitted', (tester) async {
    await open(tester, chooser(strava: false, intervals: false));
    expect(find.text('Strava'), findsNothing);
    expect(find.text('Intervals.icu'), findsNothing);
    expect(find.text('Save FIT file'), findsOneWidget);
  });

  testWidgets('saved file exposes its path and explicit share decision', (
    tester,
  ) async {
    const path =
        r'C:\Users\Rider\Documents\workouts\workout_2026-09-04T12-00-00.fit';
    for (final share in [false, true]) {
      Object? result;
      await open(
        tester,
        const WorkoutSavedDialog(filePath: path),
        onResult: (value) => result = value,
      );
      expect(find.text('workout_2026-09-04T12-00-00.fit'), findsOneWidget);
      await tester.tap(find.text('Saved location'));
      await tester.pumpAndSettle();
      expect(find.text(path), findsOneWidget);
      final action = find.text(share ? 'Share file' : 'Done');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(result, share);
      expect(tester.takeException(), isNull);
    }
  });
}
