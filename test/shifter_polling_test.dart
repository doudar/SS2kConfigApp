import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';

class _PollingDeviceData extends DeviceData {
  final connection = DeviceTransportStateController()
    ..markConnected(DeviceTransportKind.dircon);
  final requests = <String>[];
  Completer<void>? pendingRead;

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
    if (name == inclineVname) await pendingRead?.future;
  }

  @override
  void dispose() {
    connection.dispose();
    super.dispose();
  }
}

void main() {
  final device = BluetoothDevice.fromId('shifter-polling-test');
  final details = [
    inclineVname,
    targetPositionVname,
    simulatedTargetWattsVname,
  ];
  late _PollingDeviceData data;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'shifter_shift_sound_enabled': false,
    });
    data = _PollingDeviceData();
    DeviceDataManager.updateDataForDevice(device, data);
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

  Future<void> host(
    WidgetTester tester, {
    GlobalKey<NavigatorState>? navigator,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ShifterScreen(device: device),
      ),
    );
    await tester.pump();
    data.requests.clear();
  }

  testWidgets('requests only non-streamed details once every two seconds', (
    tester,
  ) async {
    await host(tester);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(data.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(data.requests, details);
    await tester.pump(const Duration(seconds: 2));
    expect(data.requests, [...details, ...details]);
    await tester.pumpWidget(const SizedBox());
    data.requests.clear();
    await tester.pump(const Duration(seconds: 4));
    expect(data.requests, isEmpty);
  });

  testWidgets('a slow response never queues overlapping poll batches', (
    tester,
  ) async {
    await host(tester);
    data.pendingRead = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    expect(data.requests, [inclineVname]);
    await tester.pump(const Duration(seconds: 6));
    expect(data.requests, [inclineVname]);
    data.pendingRead!.complete();
    await tester.pump();
    expect(data.requests, details);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('polling pauses while disconnected and resumes on reconnect', (
    tester,
  ) async {
    await host(tester);
    data.connection.markDisconnected(explicit: false);
    await tester.pump(const Duration(seconds: 4));
    expect(data.requests, isEmpty);
    data.connection.markConnected(DeviceTransportKind.dircon);
    await tester.pump();
    expect(data.requests, [
      shifterPositionVname,
      FTMSModeVname,
      BLE_hMinVname,
      BLE_hMaxVname,
      shiftStepVname,
      maxBrakeWattsVname,
    ]);
    data.requests.clear();
    await tester.pump(const Duration(seconds: 2));
    expect(data.requests, details);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('polling pauses behind another route and in the background', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await host(tester, navigator: navigator);
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(data.requests, isEmpty);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(data.requests, details);
    data.requests.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 4));
    expect(data.requests, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(data.requests, details);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a replaced connection aborts the old batch after its pending read',
    (tester) async {
      await host(tester);
      data.pendingRead = Completer<void>();
      await tester.pump(const Duration(seconds: 2));
      data.connection.markDisconnected(explicit: false);
      data.connection.markConnected(DeviceTransportKind.dircon);
      await tester.pump();
      data.requests.clear();
      data.pendingRead!.complete();
      await tester.pump();
      expect(data.requests, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(data.requests, details);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('degraded links and unsupported details do not waste reads', (
    tester,
  ) async {
    await host(tester);
    data.customResponsesDegraded.value = true;
    await tester.pump(const Duration(seconds: 4));
    expect(data.requests, isEmpty);
    data.customResponsesDegraded.value = false;
    data.customCharacteristic.firstWhere(
      (c) => c['vName'] == inclineVname,
    )['value'] = noFirmSupport;
    await tester.pump(const Duration(seconds: 2));
    expect(data.requests, [targetPositionVname, simulatedTargetWattsVname]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving during a pending read stops the rest of the batch', (
    tester,
  ) async {
    await host(tester);
    data.pendingRead = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    data.pendingRead!.complete();
    await tester.pump();
    expect(data.requests, [inclineVname]);
    expect(tester.takeException(), isNull);
  });
}
