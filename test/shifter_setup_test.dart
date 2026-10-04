import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/widgets/setting_tile.dart';
import 'package:ss2kconfigapp/widgets/workout_dialog.dart';

class _SetupDeviceData extends DeviceData {
  final connection = DeviceTransportStateController()
    ..markConnected(DeviceTransportKind.dircon);
  final requests = <String>[];

  @override
  ValueNotifier<DeviceTransportState> get transportState => connection;
  @override
  bool get isTransportActive =>
      connection.value.phase == DeviceTransportPhase.connected;
  @override
  void startConnectionMonitor(
    BluetoothDevice device, {
    Future<void> Function()? onReconnected,
  }) {}
  @override
  Future<void> ensureFtmsNotifications(BluetoothDevice device) async {}
  @override
  Future<void> checkFtmsHealth(BluetoothDevice device) async {}

  @override
  Future<void> requestSetting(
    BluetoothDevice device,
    String name, {
    int? extraByte,
  }) async {
    requests.add(name);
  }

  void cache(String name, String value) {
    customCharacteristic.firstWhere((c) => c['vName'] == name)['value'] = value;
  }

  @override
  void dispose() {
    connection.dispose();
    super.dispose();
  }
}

void main() {
  final device = BluetoothDevice.fromId('shifter-setup-test');
  late _SetupDeviceData data;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'shifter_shift_sound_enabled': false,
    });
    data = _SetupDeviceData();
    DeviceDataManager.updateDataForDevice(device, data);
    // Values are null until read, so seed what a connected SS2k reports.
    data
      ..cache(gearPresetVname, '0')
      ..cache(gearTeethVname, '[]')
      ..cache(shiftStepVname, '1500');
    const codec = StandardMessageCodec();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => codec.encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() {
    DeviceDataManager.clearDataForDevice(device);
    data.dispose();
  });

  Future<void> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: ShifterScreen(device: device)));
    await tester.pump();
    data.requests.clear();
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Shifter settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('keeps setup off the shifter and shows it in a modal', (
    tester,
  ) async {
    data.cache(shiftStepVname, '1200');
    await host(tester);

    expect(find.byType(SettingTile), findsNothing);
    await openSettings(tester);

    expect(find.byType(WorkoutDialog), findsOneWidget);
    expect(find.text('Shifter settings'), findsOneWidget);
    expect(find.byType(SettingTile), findsNWidgets(2));
    expect(find.text('Simulated Groupset'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('Shift Step'), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);

    await tester.tap(find.text('Back to shifting'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutDialog), findsNothing);
    await leave(tester);
  });

  testWidgets('omits settings that are unsupported or not yet read', (
    tester,
  ) async {
    data.cache(gearTeethVname, noFirmSupport);
    await host(tester);
    await openSettings(tester);

    expect(find.byType(SettingTile), findsOneWidget);
    expect(find.text('Simulated Groupset'), findsNothing);
    expect(find.text('Shift Step'), findsOneWidget);

    data.customCharacteristic.firstWhere(
      (c) => c['vName'] == shiftStepVname,
    )['value'] = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: ShifterScreen(device: device)));
    await tester.pump();
    expect(find.byTooltip('Shifter settings'), findsNothing);
    await leave(tester);
  });

  testWidgets('re-reads the gear after a setting editor closes', (
    tester,
  ) async {
    await host(tester);
    await openSettings(tester);

    await tester.tap(find.text('Simulated Groupset'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingEditScreen), findsOneWidget);
    expect(data.requests, isNot(contains(shifterPositionVname)));

    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingEditScreen), findsNothing);
    // The modal stays open so several settings can be changed in one visit.
    expect(find.byType(WorkoutDialog), findsOneWidget);
    expect(data.requests, contains(shifterPositionVname));
    await leave(tester);
  });
}
