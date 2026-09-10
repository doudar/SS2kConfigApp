import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/widgets/intervals_workout_folder_dialog.dart';

void main() {
  testWidgets(
    'Intervals folders have a size and support drill-down, back and selection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const workout = <String, dynamic>{
        'name': 'Threshold intervals',
        'workout_doc': {'steps': []},
        'moving_time': 3600,
        'icu_training_load': 70,
        'icu_intensity': .85,
      };
      for (final size in [
        const Size(320, 568),
        const Size(844, 330),
        const Size(1200, 800),
      ]) {
        tester.view.physicalSize = size;
        Map<String, dynamic>? selection;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selection = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => IntervalsWorkoutFolderDialog(
                        folder: {
                          'name': 'Training plan',
                          'children': [
                            {'name': 'Empty folder', 'children': []},
                            {
                              'name': 'Build week',
                              'children': [workout],
                            },
                          ],
                        },
                        thumbnailBuilder: (_, _) => const SizedBox(
                          width: 120,
                          height: 70,
                          child: Icon(Icons.show_chart),
                        ),
                      ),
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        );
        Future<void> tap(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await tap('OPEN');
        expect(tester.getSize(find.byType(ListView)).height, greaterThan(0));
        await tap('Empty folder');
        expect(find.text('No workouts in this folder yet.'), findsOneWidget);
        await tap('Go back');
        await tap('Build week');
        expect(find.text('01:00:00 • TL 70 • IF 0.85'), findsOneWidget);
        await tap('Threshold intervals');
        expect(selection, workout);
        expect(find.byType(IntervalsWorkoutFolderDialog), findsNothing);
      }
    },
  );
}
