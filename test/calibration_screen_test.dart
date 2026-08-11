import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/calibration_screen.dart';
import 'package:ss2kconfigapp/utils/bledata.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/widgets/homing_proximity_gauge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BluetoothDevice device;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    device = BluetoothDevice.fromId('AA:BB:CC:DD:EE:01');
    final bleData = BLEDataManager.forDevice(device)..isSimulated = true;
    bleData.customCharacteristic.firstWhere(
      (c) => c['vName'] == homingSensitivityVname,
    )['value'] = '50';
  });

  tearDown(() {
    BLEDataManager.clearDataForDevice(device);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalibrationScreen(device: device, showDeviceHeader: false),
      ),
    );
    await tester.pumpAndSettle();
  }

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
    BLEDataManager.forDevice(device).customCharacteristic.firstWhere(
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

    await tester.pump(const Duration(seconds: 12));
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

  testWidgets('cadence stays visible until a reading exceeds 10 rpm', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'calibration_setup': 'physicalStops',
    });

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Stop Watching'), findsNothing);
    expect(find.text('Waiting for you to pedal'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Watch the knob')).dy,
      lessThan(tester.getTopLeft(find.text('CADENCE')).dy),
      reason: 'the guidance belongs above the live indicator',
    );
    expect(
      find.text('CADENCE'),
      findsOneWidget,
      reason: 'the simulated 0x01 acknowledgement has already arrived',
    );
    expect(find.byType(HomingProximityGauge), findsNothing);
    expect(find.text('Motor Load'), findsNothing);
    expect(find.textContaining('Baseline will be centered at'), findsNothing);
    expect(
      find.textContaining('SG falls as required torque rises'),
      findsNothing,
    );
    expect(
      find.textContaining('To cancel, press either shifter button'),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1300));

    expect(
      find.text('CADENCE'),
      findsOneWidget,
      reason:
          'homing-start traffic alone is not proof that cadence was detected',
    );
    expect(
      find.byIcon(Icons.check_circle),
      findsNothing,
      reason:
          'a homing-start acknowledgement is not proof that cadence was detected',
    );

    await tester.pump(const Duration(milliseconds: 4700));

    expect(
      find.text('CADENCE'),
      findsOneWidget,
      reason: 'end-stop progress cannot replace the required cadence reading',
    );
    expect(find.byType(HomingProximityGauge), findsNothing);
  });
}
