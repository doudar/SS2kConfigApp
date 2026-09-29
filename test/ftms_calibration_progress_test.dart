import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/calibration_monitor.dart';
import 'package:ss2kconfigapp/widgets/ftms_calibration_progress.dart';

void main() {
  testWidgets(
    'mapping explains samples, elapsed time and movement on a small screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: FtmsCalibrationProgress(
                  stage: FtmsCalibrationStage.mapping,
                  samples: 1,
                  elapsed: Duration(minutes: 2, seconds: 16),
                  reading: HomingGaugeReading(
                    mode: HomingGaugeMode.ftmsResistance,
                    progress: 0.56,
                    current: 56,
                    target: 58,
                    stage: 'Maximum',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Building the resistance map'), findsOneWidget);
      expect(find.textContaining('1 of 3 samples confirmed'), findsOneWidget);
      expect(find.textContaining('Elapsed 2:16'), findsOneWidget);
      expect(find.text('Resistance 56 · Target 58'), findsOneWidget);
      expect(
        find.textContaining('Pauses and small reversals are normal'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
