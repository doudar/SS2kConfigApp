import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/calibration_screen.dart';
import 'package:ss2kconfigapp/utils/bledata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BluetoothDevice device;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    device = BluetoothDevice.fromId('AA:BB:CC:DD:EE:01');
    BLEDataManager.forDevice(device).isSimulated = true;
  });

  tearDown(() {
    BLEDataManager.clearDataForDevice(device);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalibrationScreen(
          device: device,
          showDeviceHeader: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('legacy users must answer the Bike+ question before starting', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Are you using a Peloton Bike+?'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Yes, Bike+'), findsOneWidget);

    ElevatedButton startButton = tester.widget(find.widgetWithText(ElevatedButton, 'Start Calibration'));
    expect(startButton.onPressed, isNull);

    final noChoice = find.text('No');
    await tester.ensureVisible(noChoice);
    await tester.pumpAndSettle();
    await tester.tap(noChoice);
    await tester.pumpAndSettle();

    startButton = tester.widget(find.widgetWithText(ElevatedButton, 'Start Calibration'));
    expect(startButton.onPressed, isNotNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('calibration_setup'), 'physicalStops');
    expect(prefs.getString('bike_type'), isNull);
  });

  testWidgets('saved Bike+ profile shows resistance-data guidance', (tester) async {
    SharedPreferences.setMockInitialValues({'bike_type': 'pelotonBikePlus'});

    await pumpScreen(tester);

    expect(find.text('Bike+ needs resistance data'), findsOneWidget);
    expect(find.text('Start with resistance data'), findsOneWidget);
    expect(find.textContaining('has no physical stops'), findsOneWidget);
    expect(find.textContaining('Brief contact with each stop'), findsNothing);

    await tester.tap(find.text('Start with resistance data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(milliseconds: 601));

    expect(find.text('Calibration saved'), findsOneWidget);
    expect(find.textContaining('Did the knob reach both ends'), findsNothing);
    expect(find.text('Device log'), findsOneWidget);
    expect(find.byTooltip('Copy log'), findsOneWidget);
  });

  testWidgets('request acknowledgement keeps cadence visible until homing starts', (tester) async {
    SharedPreferences.setMockInitialValues({'calibration_setup': 'physicalStops'});

    await pumpScreen(tester);
    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Stop Watching'), findsNothing);
    expect(find.text('Waiting for you to pedal'), findsOneWidget);
    expect(find.text('CADENCE'), findsOneWidget,
        reason: 'the simulated 0x01 acknowledgement has already arrived');
    expect(find.textContaining('To cancel, press either shifter button'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('CADENCE'), findsNothing,
        reason: 'the correlated homing-start log now confirms progress');
  });
}
