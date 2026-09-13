import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/utils/bleConstants.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/shifter_sound.dart';
import 'package:ss2kconfigapp/widgets/shifter_gear_indicator.dart';

class _ShiftDeviceData extends DeviceData {
  final connection = DeviceTransportStateController()
    ..markConnected(DeviceTransportKind.dircon);
  final updates = StreamController<CharacteristicChangeEvent>.broadcast();
  final statuses = StreamController<List<int>>.broadcast();
  final writes = <Map>[];
  final acknowledgements = <Completer<void>>[];
  String? readBack = '12';
  String? readBackWatts;

  void cache(String name, String value) =>
      customCharacteristic.firstWhere((c) => c['vName'] == name)['value'] =
          value;

  Map get gear => customCharacteristic.firstWhere(
    (c) => c['vName'] == shifterPositionVname,
  );

  void reportGear(String value) {
    gear['value'] = value;
    updates.add(
      CharacteristicChangeEvent(
        vName: shifterPositionVname,
        reference: '0x17',
        value: value,
        type: 'int',
      ),
    );
  }

  @override
  ValueNotifier<DeviceTransportState> get transportState => connection;
  @override
  bool get isTransportActive =>
      connection.value.phase == DeviceTransportPhase.connected;
  @override
  Stream<CharacteristicChangeEvent> get characteristicChanges => updates.stream;
  @override
  Stream<List<int>> get machineStatusStream => statuses.stream;
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
    if (name == shifterPositionVname && readBack != null) reportGear(readBack!);
    if (name == simulatedTargetWattsVname && readBackWatts != null) {
      simulatedTargetWatts = readBackWatts!;
    }
  }

  @override
  Future<void> writeToSS2kStrict(
    BluetoothDevice device,
    Map c, {
    String s = '',
  }) {
    writes.add(c);
    final pending = Completer<void>();
    acknowledgements.add(pending);
    return pending.future;
  }

  @override
  void dispose() {
    updates.close();
    statuses.close();
    connection.dispose();
    super.dispose();
  }
}

class _SilentOutput implements ShifterSoundOutput {
  int plays = 0;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  final device = BluetoothDevice.fromId('shifter-confirmation-test');
  late _ShiftDeviceData data;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'shifter_shift_sound_enabled': false,
    });
    data = _ShiftDeviceData();
    data.gear['value'] = '12';
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

  Future<void> host(WidgetTester tester, {_SilentOutput? output}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShifterScreen(
          device: device,
          shiftSound: ShifterSound(output: output ?? _SilentOutput()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  ShifterGearIndicator indicator(WidgetTester tester) =>
      tester.widget(find.byType(ShifterGearIndicator));

  Future<void> shift(WidgetTester tester, {bool up = true}) async {
    await tester.ensureVisible(find.text(up ? 'Shift up' : 'Shift down'));
    await tester.tap(find.text(up ? 'Shift up' : 'Shift down'));
    await tester.pump();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('remote gear changes play once and respect mute', (tester) async {
    SharedPreferences.setMockInitialValues({ShifterSound.preferenceKey: true});
    final output = _SilentOutput();
    await host(tester, output: output);
    expect(output.plays, 0);
    data.reportGear('13');
    await flush(tester);
    expect(output.plays, 1);
    expect(indicator(tester).value, '13');
    data.reportGear('13');
    await flush(tester);
    expect(output.plays, 1);
    data.reportGear('12');
    await flush(tester);
    expect(output.plays, 2);
    await tester.tap(find.byTooltip('Mute shift sounds'));
    await flush(tester);
    data.reportGear('11');
    await flush(tester);
    expect(output.plays, 2);
    expect(indicator(tester).value, '11');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local confirmations do not repeat the shift sound', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({ShifterSound.preferenceKey: true});
    final output = _SilentOutput();
    await host(tester, output: output);
    await shift(tester);
    await flush(tester);
    expect(output.plays, 1);
    data.reportGear('13');
    await flush(tester);
    data.acknowledgements.single.complete();
    await flush(tester);
    data.reportGear('13');
    await flush(tester);
    expect(output.plays, 1);
    data.reportGear('14');
    await flush(tester);
    expect(output.plays, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('initial and reconnect gear snapshots are silent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({ShifterSound.preferenceKey: true});
    final output = _SilentOutput();
    data.readBack = '15';
    await host(tester, output: output);
    expect(output.plays, 0);
    data.connection.markDisconnected(explicit: false);
    await flush(tester);
    data.readBack = '20';
    data.connection.markConnected(DeviceTransportKind.dircon);
    await flush(tester);
    expect(output.plays, 0);
    data.reportGear('21');
    await flush(tester);
    expect(output.plays, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mute control persists when the shifter is reopened', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'shifter_shift_sound_enabled': true,
    });
    await host(tester);
    await tester.tap(find.byTooltip('Mute shift sounds'));
    await flush(tester);
    expect(find.byTooltip('Enable shift sounds'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('shifter_shift_sound_enabled'), isFalse);
    await tester.pumpWidget(const SizedBox());
    await host(tester);
    expect(find.byTooltip('Enable shift sounds'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'optimistic gear never overwrites cache or flashes old gear after acknowledgement',
    (tester) async {
      await host(tester);
      await shift(tester);
      expect(data.gear['value'], '12');
      expect(data.writes.single['value'], '13');
      expect(identical(data.writes.single, data.gear), isFalse);
      data.acknowledgements.single.complete();
      await flush(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(indicator(tester).value, '13');
      expect(indicator(tester).shifting, isTrue);
      data.reportGear('12');
      await flush(tester);
      expect(indicator(tester).value, '13');
      data.reportGear('13');
      await flush(tester);
      expect(indicator(tester).value, '13');
      expect(indicator(tester).shifting, isFalse);
      expect(data.gear['value'], '13');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('device rejection wins when the gear is read back', (
    tester,
  ) async {
    await host(tester);
    await shift(tester);
    data.acknowledgements.single.complete();
    data.reportGear('12');
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1));
    await flush(tester);
    expect(indicator(tester).value, '12');
    expect(indicator(tester).shifting, isFalse);
    expect(data.gear['value'], '12');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'rapid shifts retain the latest requested gear until its confirmation',
    (tester) async {
      await host(tester);
      await shift(tester);
      await shift(tester);
      expect(data.writes.map((c) => c['value']), ['13', '14']);
      expect(data.gear['value'], '12');
      data.acknowledgements.first.complete();
      data.reportGear('13');
      await flush(tester);
      expect(indicator(tester).value, '14');
      data.acknowledgements.last.complete();
      await flush(tester);
      expect(indicator(tester).value, '14');
      expect(indicator(tester).shifting, isTrue);
      data.reportGear('14');
      await flush(tester);
      expect(indicator(tester).value, '14');
      expect(indicator(tester).shifting, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed write restores only the last device-confirmed gear', (
    tester,
  ) async {
    await host(tester);
    await shift(tester);
    data.acknowledgements.single.completeError(
      StateError('No acknowledgement'),
    );
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 1));
    await flush(tester);
    expect(indicator(tester).value, '12');
    expect(indicator(tester).shifting, isFalse);
    expect(data.gear['value'], '12');
    expect(
      find.textContaining('did not confirm the requested shift'),
      findsOneWidget,
    );
    expect(find.textContaining('check your connection'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'disconnect cancels pending presentation and ignores old completion',
    (tester) async {
      await host(tester);
      await shift(tester);
      data.connection.markDisconnected(explicit: false);
      data.acknowledgements.single.complete();
      await flush(tester);
      expect(indicator(tester).value, '12');
      expect(indicator(tester).shifting, isFalse);
      expect(data.gear['value'], '12');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('missing confirmation leaves the device cache intact', (
    tester,
  ) async {
    await host(tester);
    data.readBack = null;
    await shift(tester);
    data.acknowledgements.single.complete();
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1));
    await flush(tester);
    expect(indicator(tester).value, '—');
    expect(indicator(tester).shifting, isFalse);
    expect(data.gear['value'], '12');
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('shifter_status'))).data,
      contains('did not confirm the requested shift'),
    );
    data.reportGear('13');
    await flush(tester);
    expect(indicator(tester).value, '13');
    expect(find.text('Ready to shift'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> rejectShift(WidgetTester tester) async {
    await shift(tester);
    data.acknowledgements.last.complete();
    await flush(tester);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1));
    await flush(tester);
  }

  testWidgets('rejected shift explains fresh zero cadence', (tester) async {
    data.lastFtmsUpdate = DateTime.now();
    data.ftmsData.cadence = 0;
    await host(tester);
    await rejectShift(tester);
    expect(find.textContaining('No cadence detected yet'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Ready to shift'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('shifter_status'))).data,
      contains('No cadence detected yet'),
    );
    expect(data.gear['value'], '12');
    await shift(tester);
    expect(find.textContaining('No cadence detected yet'), findsNothing);
    expect(find.text('Shifting…'), findsOneWidget);
    data.reportGear('13');
    data.acknowledgements.last.complete();
    await flush(tester);
    expect(find.text('Ready to shift'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('homing status explains rejection and clears on completion', (
    tester,
  ) async {
    await host(tester);
    data.statuses.add([
      FTMSStatusOpCodes.SPIN_DOWN_STATUS,
      FTMSSpinDownStatus.SPIN_DOWN_REQUESTED,
    ]);
    await flush(tester);
    await rejectShift(tester);
    expect(find.textContaining('Homing is active'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    data.statuses.add([
      FTMSStatusOpCodes.SPIN_DOWN_STATUS,
      FTMSSpinDownStatus.SUCCESS,
    ]);
    await tester.pump(const Duration(milliseconds: 300));
    await flush(tester);
    expect(find.text('Ready to shift'), findsOneWidget);
    await rejectShift(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('did not confirm the requested shift'),
      findsOneWidget,
    );
    expect(find.textContaining('Homing is active'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rejected shift explains calibrated travel limit', (
    tester,
  ) async {
    data.FTMSmode = FTMSOpCodes.SET_INDOOR_BIKE_SIMULATION;
    data.cache(BLE_hMinVname, '0');
    data.cache(BLE_hMaxVname, '1000');
    data.cache(targetPositionVname, '950');
    data.cache(shiftStepVname, '100');
    await host(tester);
    await rejectShift(tester);
    expect(find.textContaining('upper travel limit'), findsOneWidget);
    expect(indicator(tester).value, '12');
    expect(data.gear['value'], '12');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ERG watt change confirms a shift with unchanged gear', (
    tester,
  ) async {
    data.FTMSmode = FTMSOpCodes.SET_TARGET_POWER;
    data.simulatedTargetWatts = '200';
    await host(tester);
    data.readBackWatts = '210';
    await rejectShift(tester);
    await tester.pump(const Duration(milliseconds: 1));
    await flush(tester);
    expect(indicator(tester).shifting, isFalse);
    expect(indicator(tester).value, '12');
    expect(data.gear['value'], '12');
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
