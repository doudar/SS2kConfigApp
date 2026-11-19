import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/calibration_screen.dart';
import 'package:ss2kconfigapp/utils/calibration_monitor.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/widgets/homing_proximity_gauge.dart';
import 'package:ss2kconfigapp/widgets/workout_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BluetoothDevice device;
  late int stopCues;

  setUp(() {
    stopCues = 0;
    SharedPreferences.setMockInitialValues({});
    device = BluetoothDevice.fromId('AA:BB:CC:DD:EE:01');
    final deviceData = DeviceDataManager.forDevice(device)..isSimulated = true;
    deviceData.customCharacteristic.firstWhere(
      (c) => c['vName'] == homingSensitivityVname,
    )['value'] = '50';
  });

  tearDown(() {
    CalibrationMonitor.debugDemoDispatchDelay = Duration.zero;
    DeviceDataManager.clearDataForDevice(device);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalibrationScreen(
          device: device,
          showDeviceHeader: false,
          stopCue: () async => stopCues++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Simulates the rider pedaling at [rpm].
  void pedal(int rpm) {
    final deviceData = DeviceDataManager.forDevice(device);
    deviceData.ftmsData.cadence = rpm;
    deviceData.debugEmitFtmsDataUpdate();
  }

  List<Object?> recordHaptics(WidgetTester tester) {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return haptics;
  }

  testWidgets('calibration fits the shared workout dialog on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutDialog(
            title: const Text('Calibrate Trainer'),
            listBody: true,
            showClose: true,
            content: CalibrationScreen(device: device, embedded: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Calibrate Trainer'), findsOneWidget);
    await tester.ensureVisible(find.text('No'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString('calibration_setup'),
      'physicalStops',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy users must answer the Bike+ question before starting', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Are you using a Peloton Bike+?'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Yes, Bike+'), findsOneWidget);
    expect(find.text('Your Power Table will reset'), findsOneWidget);
    expect(find.byIcon(Icons.show_chart), findsOneWidget);

    ElevatedButton startButton = tester.widget(
      find.widgetWithText(ElevatedButton, 'Start Calibration'),
    );
    expect(startButton.onPressed, isNull);

    final noChoice = find.text('No');
    await tester.ensureVisible(noChoice);
    await tester.pumpAndSettle();
    await tester.tap(noChoice);
    await tester.pumpAndSettle();

    startButton = tester.widget(
      find.widgetWithText(ElevatedButton, 'Start Calibration'),
    );
    expect(startButton.onPressed, isNotNull);
    expect(
      find.widgetWithText(OutlinedButton, 'Change'),
      findsNWidgets(2),
      reason: 'Both editable summary rows should use obvious buttons.',
    );
    expect(find.text('Homing Force 50', findRichText: true), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('calibration_setup'), 'physicalStops');
    expect(prefs.getString('bike_type'), isNull);
  });

  testWidgets('Homing Force can be changed from the first page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });
    await pumpScreen(tester);

    final changeButton = find.byKey(const Key('change_homing_force_button'));
    await tester.ensureVisible(changeButton);
    await tester.pumpAndSettle();
    await tester.tap(changeButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit Setting'), findsOneWidget);
    expect(find.text('Homing Force'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(slider.value);
    slider.onChanged!(70);
    await tester.pump();
    slider.onChangeEnd!(70);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('Homing Force 70', findRichText: true), findsOneWidget);
  });

  testWidgets('Homing Force editor stays disabled until its value loads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });
    DeviceDataManager.forDevice(device).customCharacteristic.firstWhere(
      (c) => c['vName'] == homingSensitivityVname,
    )['value'] = null;

    await pumpScreen(tester);

    expect(
      find.text('Homing Force Loading…', findRichText: true),
      findsOneWidget,
    );
    final changeButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('change_homing_force_button')),
    );
    expect(changeButton.onPressed, isNull);
    expect(find.text('Edit Setting'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved Bike+ profile shows resistance-data guidance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'bike_type': 'pelotonBikePlus'});

    await pumpScreen(tester);

    expect(find.text('Bike+ needs resistance data'), findsOneWidget);
    expect(find.text('Start with resistance data'), findsOneWidget);
    expect(find.textContaining('has no physical stops'), findsOneWidget);
    expect(find.textContaining('Brief contact with each stop'), findsNothing);

    await tester.tap(find.text('Start with resistance data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('CADENCE'), findsOneWidget);
    expect(find.byType(HomingProximityGauge), findsNothing);

    pedal(80);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Stop pedaling'), findsOneWidget);
    expect(
      find.text(
        "SmartSpin2k is turning the knob to learn your bike's full resistance range. This takes a few minutes.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('lowest and highest'), findsNothing);
    expect(
      find.textContaining('increase Homing Force'),
      findsNothing,
      reason: 'Homing Force does not apply to Bike+',
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 601));

    expect(find.text('Calibration saved'), findsOneWidget);
    expect(find.textContaining('Did the knob reach both ends'), findsNothing);
    expect(find.text('Device log'), findsOneWidget);
    expect(find.byTooltip('Copy log'), findsOneWidget);
  });

  testWidgets('the saved box reports the travel range the run found', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(milliseconds: 601));

    // The demo device homes to 'Max Position found: 24800'.
    expect(find.text('Calibration saved'), findsOneWidget);
    expect(
      find.textContaining('Travel range of 0 → 24,800 steps found.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Did the knob reach both ends'),
      findsOneWidget,
      reason: 'the range leads the callout, it does not replace the question',
    );
  });

  testWidgets('the start page says pedaling is brief and will be stopped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);

    expect(find.text('What will happen'), findsOneWidget);
    expect(find.text('Pedal for a few seconds.'), findsOneWidget);
    expect(
      find.text('Stop pedaling when this screen tells you.'),
      findsOneWidget,
    );
    expect(
      find.text(
        "SmartSpin2k turns the knob to find your bike's lowest and highest resistance.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('the rider is told to stop pedaling once homing starts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });
    final haptics = recordHaptics(tester);

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Start pedaling'), findsOneWidget);
    expect(find.text('Stop pedaling'), findsNothing);
    expect(find.text('Waiting for you to pedal'), findsOneWidget);
    expect(
      find.text('CADENCE'),
      findsOneWidget,
      reason: 'the simulated 0x01 acknowledgement has already arrived',
    );
    expect(
      tester.getTopLeft(find.text('Start pedaling')).dy,
      lessThan(tester.getTopLeft(find.text('Waiting for you to pedal')).dy),
      reason: 'the instruction leads the page, above the checklist',
    );
    expect(
      find.byType(HomingProximityGauge),
      findsNothing,
      reason: 'nothing is moving yet, so there is nothing to gauge',
    );
    expect(
      find.textContaining('To cancel, press either shifter button'),
      findsOneWidget,
    );
    expect(find.textContaining('increase Homing Force'), findsOneWidget);

    pedal(72);
    await tester.pump();
    // The demo device reports homing ~1.3 s after the start, but the app has
    // only seen cadence for ~1.35 s, less than the firmware's own gate.
    await tester.pump(const Duration(milliseconds: 1350));

    expect(
      find.text('Keep pedaling…'),
      findsOneWidget,
      reason: 'a homing signal this early is not trusted yet',
    );
    expect(find.text('Stop pedaling'), findsNothing);
    expect(haptics, isEmpty);
    expect(stopCues, 0);

    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Stop pedaling'), findsOneWidget);
    expect(find.text('Keep pedaling…'), findsNothing);
    expect(find.text('CADENCE'), findsNothing);
    expect(
      find.text(
        "SmartSpin2k is turning the knob to find your bike's lowest and highest resistance.",
      ),
      findsOneWidget,
    );
    expect(find.text('Pedaling detected — you can stop'), findsOneWidget);
    expect(find.text('Waiting for you to pedal'), findsNothing);
    expect(find.byType(HomingProximityGauge), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
    expect(stopCues, 1, reason: 'the chime reaches riders without haptics');

    await tester.pump(const Duration(milliseconds: 4700));

    expect(
      find.text('Stop pedaling'),
      findsOneWidget,
      reason: 'the instruction holds for the rest of the run',
    );
    expect(haptics, hasLength(1), reason: 'the cue fires once per run');
    expect(stopCues, 1);
  });

  testWidgets('a first cadence reading asks for more, not for a stop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    pedal(72);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Keep pedaling…'), findsOneWidget);
    expect(
      find.text('Waiting for you to pedal'),
      findsOneWidget,
      reason: 'the checklist does not repeat the card',
    );
    expect(find.text('72'), findsOneWidget);
    expect(
      find.text('Stop pedaling'),
      findsNothing,
      reason:
          'the firmware wants about two seconds of cadence; stopping on the '
          'first reading would reset its count',
    );
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byType(HomingProximityGauge), findsNothing);
  });

  testWidgets('without cadence, only a found end stop means stop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2700));

    expect(
      find.text('Start pedaling'),
      findsOneWidget,
      reason: 'a homing signal the app saw no cadence for may be a duplicate ack',
    );

    // The demo device finds its min end stop by 6 s.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Stop pedaling'), findsOneWidget);
    expect(stopCues, 1);
  });

  testWidgets('pedaling before the homing command goes out does not count', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });
    CalibrationMonitor.debugDemoDispatchDelay = const Duration(seconds: 6);

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    pedal(80);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5500));

    expect(
      find.text('Stop pedaling'),
      findsNothing,
      reason: 'the firmware has not seen the command, so it is not counting',
    );
    expect(stopCues, 0);

    // Dispatch lands at 6 s; the firmware wants two seconds from there.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Stop pedaling'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stop pedaling'), findsOneWidget);
    expect(stopCues, 1);
  });

  testWidgets('a cadence dropout restarts the count, as it does on the device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    pedal(80);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    pedal(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1700));

    expect(
      find.text('Stop pedaling'),
      findsNothing,
      reason: 'half a second of cadence never opened the firmware gate',
    );
    expect(stopCues, 0);

    pedal(80);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Stop pedaling'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Stop pedaling'), findsOneWidget);
    expect(stopCues, 1);
  });

  testWidgets('200 rpm is outside the firmware gate and never counts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    pedal(200);
    await tester.pump();
    // Past both the trust and sustained delays, before the demo min end stop.
    await tester.pump(const Duration(milliseconds: 4800));

    expect(find.text('Stop pedaling'), findsNothing);
    expect(stopCues, 0);
  });

  testWidgets('Try Again cues the stop again on the next run', (tester) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });
    final haptics = recordHaptics(tester);

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    pedal(80);
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(milliseconds: 601));
    expect(find.text('Calibration saved'), findsOneWidget);
    expect(stopCues, 1);

    await tester.tap(find.text('No, something looked wrong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Start pedaling'),
      findsOneWidget,
      reason: 'a retry starts from the beginning, not from the last run',
    );

    pedal(80);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Stop pedaling'), findsOneWidget);
    expect(stopCues, 2);
    expect(haptics, hasLength(2));
  });

  group('riderCanStopPedaling', () {
    bool canStop({
      CalibrationPhase phase = CalibrationPhase.waitingForCadence,
      bool minFound = false,
      bool homingStarted = false,
      bool cadenceTrusted = false,
      bool cadenceSustained = false,
    }) => riderCanStopPedaling(
      phase: phase,
      minFound: minFound,
      homingStarted: homingStarted,
      cadenceTrusted: cadenceTrusted,
      cadenceSustained: cadenceSustained,
    );

    test('nothing yet means keep pedaling', () {
      expect(canStop(), isFalse);
      expect(canStop(cadenceTrusted: true), isFalse);
    });

    test('an early homing signal waits for trusted cadence', () {
      expect(canStop(homingStarted: true), isFalse);
      expect(canStop(phase: CalibrationPhase.searchingMin), isFalse);
      expect(canStop(homingStarted: true, cadenceTrusted: true), isTrue);
      expect(
        canStop(phase: CalibrationPhase.searchingMin, cadenceTrusted: true),
        isTrue,
      );
    });

    test('proof that homing ran needs no cadence', () {
      expect(canStop(minFound: true), isTrue);
      expect(canStop(phase: CalibrationPhase.searchingMax), isTrue);
      expect(canStop(phase: CalibrationPhase.complete), isTrue);
    });

    test('sustained cadence stands in for a homing signal that never came', () {
      expect(canStop(cadenceSustained: true), isTrue);
    });
  });
}
