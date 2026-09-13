import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';

class _DisplayDeviceData extends DeviceData {
  final updates = StreamController<CharacteristicChangeEvent>.broadcast();

  @override
  Stream<CharacteristicChangeEvent> get characteristicChanges => updates.stream;

  void notifyTargetChanged() => updates.add(
    CharacteristicChangeEvent(
      vName: FTMSModeVname,
      reference: '0x10',
      value: FTMSmode.toString(),
      type: 'int',
    ),
  );

  final connection = DeviceTransportStateController()
    ..markConnected(DeviceTransportKind.dircon);

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
  }) async {}

  @override
  void dispose() {
    updates.close();
    connection.dispose();
    super.dispose();
  }
}

void main() {
  final device = BluetoothDevice.fromId('shifter-target-display-test');
  late _DisplayDeviceData data;

  setUp(() {
    data = _DisplayDeviceData();
    DeviceDataManager.updateDataForDevice(device, data);
    const codec = StandardMessageCodec();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => codec.encodeMessage(<Object?>[null]),
        );
    for (final characteristic in data.customCharacteristic) {
      if (characteristic['vName'] == inclineVname) {
        characteristic['value'] = '4.5';
      } else if (characteristic['vName'] == targetPositionVname) {
        characteristic['value'] = '123';
      } else if (characteristic['vName'] == simulatedTargetWattsVname) {
        characteristic['value'] = '999';
      }
    }
  });

  tearDown(() {
    DeviceDataManager.clearDataForDevice(device);
    data.dispose();
  });

  Future<void> host(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: ShifterScreen(device: device)));
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('shows target power only for a positive ERG target', (
    tester,
  ) async {
    data.FTMSmode = FTMSOpCodes.SET_TARGET_POWER;
    data.simulatedTargetWatts = '250';
    await host(tester);

    expect(find.text('TARGET POWER'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('TARGET INCLINE'), findsNothing);
    expect(find.text('4.5'), findsNothing);
    expect(find.text('999'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('falls back to target incline when ERG target is zero', (
    tester,
  ) async {
    data.FTMSmode = FTMSOpCodes.SET_TARGET_POWER;
    data.simulatedTargetWatts = '0';
    await host(tester);

    expect(find.text('TARGET INCLINE'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('TARGET POWER'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('falls back to target incline outside ERG despite stale watts', (
    tester,
  ) async {
    data.FTMSmode = 0;
    data.simulatedTargetWatts = '250';
    await host(tester);

    expect(find.text('TARGET INCLINE'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('TARGET POWER'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switches between power and incline as live values change', (
    tester,
  ) async {
    data.FTMSmode = FTMSOpCodes.SET_TARGET_POWER;
    data.simulatedTargetWatts = '250';
    await host(tester);
    expect(find.text('TARGET POWER'), findsOneWidget);
    expect(find.text('TARGET INCLINE'), findsNothing);

    data.FTMSmode = 0;
    data.simulatedTargetWatts = '250';
    data.notifyTargetChanged();
    await tester.pump();
    await tester.pump();
    expect(find.text('TARGET INCLINE'), findsOneWidget);
    expect(find.text('TARGET POWER'), findsNothing);

    data.FTMSmode = FTMSOpCodes.SET_TARGET_POWER;
    data.simulatedTargetWatts = '0';
    data.notifyTargetChanged();
    await tester.pump();
    await tester.pump();
    expect(find.text('TARGET INCLINE'), findsOneWidget);
    expect(find.text('TARGET POWER'), findsNothing);

    data.simulatedTargetWatts = '300';
    data.notifyTargetChanged();
    await tester.pump();
    await tester.pump();
    expect(find.text('TARGET POWER'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('TARGET INCLINE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
