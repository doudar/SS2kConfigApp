import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/workout_uploads.dart';
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

  WorkoutExportDialog chooser({
    bool strava = true,
    bool intervals = true,
    WorkoutExportChoice initialChoice = const WorkoutExportChoice(
      uploadToStrava: true,
      uploadToIntervals: true,
    ),
  }) => WorkoutExportDialog(
    workoutName: 'Long threshold intervals and a well-earned cooldown',
    duration: '01:12:34',
    averagePower: 218,
    averageCadence: 88,
    stravaConnected: strava,
    intervalsConnected: intervals,
    initialChoice: initialChoice,
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

  Future<void> tapVisible(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('choose both, either or neither app before saving', (
    tester,
  ) async {
    for (final strava in [true, false]) {
      for (final intervals in [true, false]) {
        WorkoutExportChoice? choice;
        await open(
          tester,
          chooser(),
          onResult: (value) => choice = value as WorkoutExportChoice?,
        );
        if (!strava) await tapVisible(tester, 'Strava');
        if (!intervals) await tapVisible(tester, 'Intervals.icu');
        expect(choice, isNull);
        expect(find.text('Save your ride'), findsOneWidget);
        await tapVisible(
          tester,
          strava || intervals ? 'Save & upload' : 'Save FIT file',
        );
        expect(choice!.uploadToStrava, strava);
        expect(choice!.uploadToIntervals, intervals);
        expect(choice!.discard, isFalse);
      }
    }
  });

  testWidgets('next ride remembers choices, including save only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    for (final intervals in [true, false]) {
      WorkoutExportChoice? choice;
      await open(
        tester,
        chooser(),
        onResult: (value) => choice = value as WorkoutExportChoice?,
      );
      await tapVisible(tester, 'Strava');
      if (!intervals) await tapVisible(tester, 'Intervals.icu');
      await tapVisible(tester, intervals ? 'Save & upload' : 'Save FIT file');
      await choice!.savePreferences(
        prefs,
        stravaConnected: true,
        intervalsConnected: true,
      );
      await open(
        tester,
        chooser(initialChoice: WorkoutExportChoice.loadPreferences(prefs)),
      );
      final boxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(boxes[0].value, isFalse);
      expect(boxes[1].value, intervals);
      await tapVisible(tester, 'Discard workout');
    }
  });

  testWidgets(
    'disconnected app is never selected even with a saved preference',
    (tester) async {
      WorkoutExportChoice? choice;
      await open(
        tester,
        chooser(strava: false),
        onResult: (value) => choice = value as WorkoutExportChoice?,
      );
      expect(find.text('Strava'), findsNothing);
      await tapVisible(tester, 'Save & upload');
      expect(choice!.uploadToStrava, isFalse);
      expect(choice!.uploadToIntervals, isTrue);
    },
  );

  test(
    'disconnected and discarded choices preserve remembered preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await const WorkoutExportChoice(
        uploadToStrava: true,
      ).savePreferences(prefs, stravaConnected: true, intervalsConnected: true);
      await const WorkoutExportChoice().savePreferences(
        prefs,
        stravaConnected: false,
        intervalsConnected: true,
      );
      await const WorkoutExportChoice(
        discard: true,
      ).savePreferences(prefs, stravaConnected: true, intervalsConnected: true);
      final remembered = WorkoutExportChoice.loadPreferences(prefs);
      expect(remembered.uploadToStrava, isTrue);
      expect(remembered.uploadToIntervals, isFalse);
    },
  );

  test('all uploads run once and report independent failures', () async {
    for (final failFirst in [false, true]) {
      final calls = <String>[];
      final progress = <String>[];
      final result = await uploadWorkoutToApps({
        'Strava': () async {
          calls.add('Strava');
          if (failFirst) throw Exception('offline');
          return true;
        },
        'Intervals.icu': () async {
          calls.add('Intervals.icu');
          return failFirst;
        },
      }, onUploading: progress.add);
      expect(calls, ['Strava', 'Intervals.icu']);
      expect(progress, calls);
      expect(result, {'Strava': !failFirst, 'Intervals.icu': failFirst});
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
        const WorkoutSavedDialog(
          filePath: path,
          uploadResults: {'Strava': true, 'Intervals.icu': false},
        ),
        onResult: (value) => result = value,
      );
      expect(find.text('workout_2026-09-04T12-00-00.fit'), findsOneWidget);
      expect(find.text('Uploaded to Strava'), findsOneWidget);
      expect(
        find.text(
          'Could not upload to Intervals.icu. Your saved file is safe.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Saved location'));
      await tester.pumpAndSettle();
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
