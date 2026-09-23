import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/power_table_screen.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/shifter_sound.dart';

class _Data extends DeviceData {
  final connection = DeviceTransportStateController()
    ..markConnected(DeviceTransportKind.dircon);
  final updates = StreamController<CharacteristicChangeEvent>.broadcast();

  @override
  ValueNotifier<DeviceTransportState> get transportState => connection;
  @override
  bool get isTransportActive =>
      connection.value.phase == DeviceTransportPhase.connected;
  @override
  Stream<CharacteristicChangeEvent> get characteristicChanges => updates.stream;
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

  void report(String value) => updates.add(
    CharacteristicChangeEvent(
      vName: shifterPositionVname,
      reference: '0x17',
      value: value,
      type: 'int',
    ),
  );

  @override
  void dispose() {
    updates.close();
    connection.dispose();
    super.dispose();
  }
}

class _Output implements ShifterSoundOutput {
  int plays = 0;
  bool disposed = false;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> play() async => plays++;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  testWidgets('gear cues ignore initial, duplicate and reconnect readings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final device = BluetoothDevice.fromId('power-table-sound');
    final data = _Data();
    final output = _Output();
    DeviceDataManager.updateDataForDevice(device, data);
    addTearDown(() {
      DeviceDataManager.clearDataForDevice(device);
      data.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PowerTableScreen(
          device: device,
          shiftSound: ShifterSound(output: output),
        ),
      ),
    );
    await tester.pump();

    Future<void> report(String gear) async {
      data.report(gear);
      await tester.pump();
      await tester.pump();
    }

    await report('12');
    expect(output.plays, 0);
    await report('13');
    expect(output.plays, 1);
    await report('13');
    await report(noFirmSupport);
    expect(output.plays, 1);
    await tester.tap(find.byTooltip('Mute shift sounds'));
    await tester.pump();
    await report('14');
    expect(output.plays, 1);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        ShifterSound.preferenceKey,
      ),
      isFalse,
    );
    await tester.tap(find.byTooltip('Enable shift sounds'));
    await tester.pump();
    data.connection.markDisconnected(explicit: false);
    await report('15');
    data.connection.markConnected(DeviceTransportKind.dircon);
    await report('16');
    expect(output.plays, 1);
    await report('17');
    expect(output.plays, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(output.disposed, isTrue);
  });
}
