import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/snackbar.dart';
import 'package:ss2kconfigapp/widgets/device_header.dart';

import 'support/fake_ble_platform.dart';

class _HeaderData extends DeviceData {
  final connection = DeviceTransportStateController();
  final actions = <String>[];
  Completer<void>? disconnectGate;
  bool failDisconnect = false;

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
  Future<void> checkFtmsHealth(BluetoothDevice device) async {}
  @override
  Future<void> setupConnection(
    BluetoothDevice device, {
    bool forceRefresh = false,
    bool markTransportConnected = true,
    bool sweepSettings = true,
  }) async {}
  @override
  Future<void> requestSetting(
    BluetoothDevice device,
    String name, {
    int? extraByte,
  }) async {}
  @override
  Future<void> disconnectPreferred(BluetoothDevice device) async {
    actions.add('disconnect');
    await disconnectGate?.future;
    if (failDisconnect) throw StateError('could not close connection');
    connection.markDisconnected(explicit: true);
    customResponseReceived.value = false;
    customResponsesDegraded.value = false;
  }

  @override
  Future<void> connectPreferred(
    BluetoothDevice device, {
    bool waitForSetup = false,
  }) async {
    actions.add('connect');
    connection.markConnected(DeviceTransportKind.bluetooth);
  }

  @override
  void dispose() {
    connection.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlusPlatform.instance = FakeBlePlatform();
  final device = BluetoothDevice.fromId('header-connection');
  late _HeaderData data;

  setUp(() {
    data = _HeaderData();
    DeviceDataManager.updateDataForDevice(device, data);
  });
  tearDown(() {
    DeviceDataManager.clearDataForDevice(device);
    data.dispose();
  });

  Future<void> host(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: Snackbar.snackBarKeyC,
        home: Scaffold(
          body: SizedBox(width: 320, child: DeviceHeader(device: device)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('cached firmware cannot conceal silence in a new BLE session', (
    tester,
  ) async {
    data.firmwareVersion.value = '26.9.15';
    data.connection.markConnected(DeviceTransportKind.bluetooth);
    await host(tester);
    expect(
      find.text('Bluetooth connected · waiting for device'),
      findsOneWidget,
    );
    expect(find.text('26.9.15'), findsNothing);

    data.customResponseReceived.value = true;
    await tester.pump();
    expect(find.text('26.9.15'), findsOneWidget);
    data.customResponsesDegraded.value = true;
    await tester.pump();
    expect(
      find.text('Bluetooth Connected, no data received'),
      findsOneWidget,
    );

    data.customResponsesDegraded.value = false;
    await tester.pump();
    expect(find.text('26.9.15'), findsOneWidget);
    data.connection.markDisconnected(explicit: false);
    await tester.pump();
    expect(find.text('Disconnected'), findsOneWidget);
    data.connection.markReconnecting();
    await tester.pump();
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('network sessions do not wait for a BLE response', (
    tester,
  ) async {
    data.firmwareVersion.value = '26.9.15';
    data.connection.markConnected(DeviceTransportKind.dircon);
    await host(tester);
    expect(find.text('26.9.15'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('reboot requires a responsive connection', (tester) async {
    await host(tester);
    Future<void> expectRebootEnabled(bool enabled) async {
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<VoidCallback>>(
        find.ancestor(
          of: find.text('Reboot SS2k'),
          matching: find.byType(PopupMenuItem<VoidCallback>),
        ),
      );
      expect(item.enabled, enabled);
      Navigator.of(tester.element(find.text('Reboot SS2k'))).pop();
      await tester.pumpAndSettle();
    }

    await expectRebootEnabled(false);
    data.connection.markConnected(DeviceTransportKind.bluetooth);
    await tester.pump();
    await expectRebootEnabled(false);
    data.customResponseReceived.value = true;
    await tester.pump();
    await expectRebootEnabled(true);
    data.customResponsesDegraded.value = true;
    await tester.pump();
    await expectRebootEnabled(false);
    data.customResponsesDegraded.value = false;
    await tester.pump();
    await expectRebootEnabled(true);
    await unmount(tester);
  });

  testWidgets('Reconnect waits for disconnect and prevents duplicate actions', (
    tester,
  ) async {
    data.connection.markConnected(DeviceTransportKind.bluetooth);
    data.disconnectGate = Completer<void>();
    await host(tester);
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect'));
    await tester.pumpAndSettle();
    expect(data.actions, ['disconnect']);
    expect(find.text('Connecting…'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    final reconnectItem = tester.widget<PopupMenuItem<VoidCallback>>(
      find.ancestor(
        of: find.text('Reconnect'),
        matching: find.byType(PopupMenuItem<VoidCallback>),
      ),
    );
    expect(reconnectItem.enabled, isFalse);
    // Close the menu before allowing the new session to start.
    Navigator.of(tester.element(find.text('Reconnect'))).pop();
    await tester.pumpAndSettle();
    data.disconnectGate!.complete();
    await tester.pumpAndSettle();
    expect(data.actions, ['disconnect', 'connect']);
    expect(
      find.text('Bluetooth connected · waiting for device'),
      findsOneWidget,
    );
    expect(find.text('Connect: Success'), findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'failed disconnect reports failure without starting another connection',
    (tester) async {
      data.connection.markConnected(DeviceTransportKind.bluetooth);
      data.failDisconnect = true;
      await host(tester);
      await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(data.actions, ['disconnect']);
      expect(find.textContaining('Reconnect Error:'), findsOneWidget);
      await unmount(tester);
    },
  );
}
