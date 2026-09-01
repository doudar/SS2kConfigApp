// Plan 3: transport-neutral screens re-initialize once per connected session on
// either transport, driven by ConnectedEpochWatcher rather than by the raw
// `BluetoothDevice.connectionState` stream.
//
// This file installs a fake FlutterBluePlusPlatform, so per
// test/support/fake_ble_platform.dart's lifecycle rules it must stay in its own
// file. `testWidgets` runs in a fake-async zone, so every step that needs real
// asynchrony — anything that awaits DeviceData — runs inside `tester.runAsync`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/screens/ble_log_screen.dart';
import 'package:ss2kconfigapp/screens/settings_category_screen.dart';
import 'package:ss2kconfigapp/screens/shifter_screen.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/widgets/device_header.dart';
import 'package:ss2kconfigapp/widgets/setting_tile.dart';

import 'support/fake_ble_platform.dart';
import 'support/fake_dircon_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Installed before anything can touch FlutterBluePlus, so its one-time
  // initialization binds to this fake rather than to a real platform.
  final blePlatform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = blePlatform;

  // These screens reach for platform plugins that have no implementation under
  // the test binding: ShifterScreen takes a wakelock, its power-table chart
  // reads a stored axis preference, and BleLogScreen resolves a documents
  // directory. Left unmocked they throw out of initState and fail the test
  // before it can assert anything about transports.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '.',
    );

    // wakelock_plus speaks pigeon, not a MethodChannel, so it needs a raw
    // message handler replying with the codec's list-wrapped result.
    const codec = StandardMessageCodec();
    const prefix =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi';
    messenger.setMockMessageHandler(
      '$prefix.toggle',
      (message) async => codec.encodeMessage(<Object?>[null]),
    );
    messenger.setMockMessageHandler(
      '$prefix.isEnabled',
      (message) async => codec.encodeMessage(<Object?>[false]),
    );
  });

  final List<DeviceData> openDeviceData = [];
  final List<BluetoothDevice> registeredDevices = [];

  /// Registers [data] as the manager's entry for [device] so the widget under
  /// test picks it up through `DeviceDataManager.forDevice`, and queues both
  /// for teardown.
  void inject(BluetoothDevice device, DeviceData data) {
    DeviceDataManager.updateDataForDevice(device, data);
    openDeviceData.add(data);
    registeredDevices.add(device);
  }

  tearDown(() {
    for (final data in openDeviceData) {
      data.stopConnectionMonitor();
      data.dispose();
    }
    openDeviceData.clear();
    for (final device in registeredDevices) {
      DeviceDataManager.clearDataForDevice(device);
    }
    registeredDevices.clear();
    blePlatform.reset();
  });

  /// Pumps the widget tree down so the widget's timers are cancelled by its own
  /// `dispose`, rather than left pending into the next test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Disposal cancels the header's periodic timers, but work it had already
    // started keeps its own — notably _refreshDeviceInfo's deliberate
    // one-second pause. Drain those, or the test ends on "A Timer is still
    // pending even after the widget tree was disposed".
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Advances the fake clock and real time together until [condition] holds.
  ///
  /// The tree under test straddles two clocks: `DeviceData` was built inside
  /// `runAsync` so its timers are real, while anything a widget starts runs on
  /// `testWidgets`' fake clock. Waiting on only one of them deadlocks — a real
  /// `waitUntil` never lets a widget's awaits resume, and a bare `pump` never
  /// lets DeviceData's do. So alternate.
  Future<bool> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    return condition();
  }

  Future<void> pumpHeader(
    WidgetTester tester,
    BluetoothDevice device, {
    bool firmwareOnlyRefresh = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DeviceHeader(
              device: device,
              firmwareOnlyRefresh: firmwareOnlyRefresh,
            ),
          ),
        ),
      ),
    );
  }

  /// A BLE-connected DeviceData registered with the manager.
  Future<BleHarness> connectBle(WidgetTester tester) async {
    final harness = await tester.runAsync(
      () => BleHarness.connect(blePlatform),
    );
    inject(harness!.device, harness.deviceData);
    return harness;
  }

  /// A DIRCON-connected DeviceData registered with the manager. When
  /// [withParallelGatt] the GATT link is up alongside DIRCON, which is what
  /// makes a later socket drop a *promotion* of the existing BLE session.
  Future<({BluetoothDevice device, DeviceData data, FakeDirConConnector conn})>
  connectDirCon(WidgetTester tester, {bool withParallelGatt = false}) async {
    final connector = FakeDirConConnector();
    final device = BluetoothDevice.fromId('00:00:00:00:00:D${_dirConId++}');
    final data = DeviceData(dirConConnector: connector.call)
      ..advertisedIpAddress = '192.168.1.50';
    inject(device, data);

    await tester.runAsync(() async {
      await FlutterBluePlus.isSupported;
      if (withParallelGatt) blePlatform.markConnected(device.remoteId);
      await data.connectPreferred(device, waitForSetup: true);
    });
    expect(data.transportState.value.transport, DeviceTransportKind.dircon);
    return (device: device, data: data, conn: connector);
  }

  IconData headerIcon(WidgetTester tester) {
    // The signal indicator is the only Icon inside DeviceHeader's 26x26 badge;
    // the expand_more chevron is the other Icon in the collapsed header.
    final icons = tester
        .widgetList<Icon>(find.descendant(
          of: find.byType(DeviceHeader),
          matching: find.byType(Icon),
        ))
        .where((i) => i.icon != Icons.expand_more)
        .toList();
    expect(icons, hasLength(1), reason: 'expected exactly one signal icon');
    return icons.single.icon!;
  }

  /// Every custom-characteristic write, as its setting reference byte.
  List<int> ccReferences() => blePlatform.writeCalls
      .where((c) => c.characteristicUuid.str.toLowerCase() ==
          Guid(ccUUID).str.toLowerCase())
      .where((c) => c.value.length > 1)
      .map((c) => c.value[1])
      .toList();

  group('DeviceHeader transport icon', () {
    testWidgets('paints the router icon on a connected DIRCON session', (
      tester,
    ) async {
      final s = await connectDirCon(tester);
      await pumpHeader(tester, s.device);
      await tester.pump(const Duration(milliseconds: 1));

      expect(headerIcon(tester), Icons.router);
      await unmount(tester);
    });

    testWidgets('paints an RSSI band icon after a DIRCON to BLE failover', (
      tester,
    ) async {
      // The regression this pins: the old icon branched on
      // `deviceData.isDirConConnected` and `widget.device.isConnected`. After a
      // failover the GATT link is live while the DIRCON flag has cleared, and
      // the two disagreed — the header kept painting the router icon for a
      // session that was now Bluetooth. Only the transport state is
      // authoritative.
      final s = await connectDirCon(tester, withParallelGatt: true);
      await pumpHeader(tester, s.device);
      await tester.pump(const Duration(milliseconds: 1));
      expect(headerIcon(tester), Icons.router);

      // Wi-Fi dies. The firmware sees no FIN/RST; the app sees the socket go.
      s.conn.first.dropConnection();
      final failedOver = await pumpUntil(
        tester,
        () =>
            s.data.transportState.value.transport ==
                DeviceTransportKind.bluetooth &&
            s.data.transportState.value.phase ==
                DeviceTransportPhase.connected,
      );
      expect(failedOver, isTrue, reason: 'the failover never completed');

      expect(headerIcon(tester), isNot(Icons.router));
      expect(headerIcon(tester), isNot(Icons.signal_cellular_off_sharp));
      await unmount(tester);
    });

    testWidgets('paints signal_cellular_off_sharp when not connected', (
      tester,
    ) async {
      final harness = await connectBle(tester);
      await pumpHeader(tester, harness.device);
      await tester.pump(const Duration(milliseconds: 1));
      expect(headerIcon(tester), isNot(Icons.signal_cellular_off_sharp));

      blePlatform.markDisconnected(harness.device.remoteId);
      await pumpUntil(tester, () => !harness.deviceData.isTransportActive);

      expect(headerIcon(tester), Icons.signal_cellular_off_sharp);
      await unmount(tester);
    });
  });

  group('DeviceHeader connected-session initialization', () {
    testWidgets('entering while already connected still runs setup', (
      tester,
    ) async {
      // ConnectedEpochWatcher deliberately does not replay on attach, unlike
      // the fbp stream it replaces. Without DeviceHeader's explicit
      // post-attach call this is zero writes and the header never sets up.
      final harness = await connectBle(tester);
      blePlatform.clearObservations();

      await pumpHeader(tester, harness.device);
      await pumpUntil(tester, () => ccReferences().isNotEmpty);

      expect(
        ccReferences(),
        isNotEmpty,
        reason: 'the header must run its own first-load pass on entry',
      );
      await unmount(tester);
    });

    testWidgets('a reconnect runs the sweep once, not once per signal', (
      tester,
    ) async {
      // The header used to be wired to both the connected-epoch signal and
      // startConnectionMonitor's onReconnected callback, which fire at
      // different points of the same reconnect. Plan 3 drops onReconnected
      // here, leaving the watcher as the sole owner.
      final harness = await connectBle(tester);
      await pumpHeader(tester, harness.device);
      await pumpUntil(tester, () => ccReferences().isNotEmpty);

      blePlatform.markDisconnected(harness.device.remoteId);
      await pumpUntil(tester, () => !harness.deviceData.isTransportActive);

      blePlatform.clearObservations();
      blePlatform.markConnected(harness.device.remoteId);
      await pumpUntil(tester, () => harness.deviceData.isTransportActive);
      // Let the whole reconnect settle, including _refreshDeviceInfo's
      // deliberate one-second pause, so a second pass would have landed.
      await pumpUntil(tester, () => false, timeout: const Duration(seconds: 4));

      final refs = ccReferences();
      final counts = <int, int>{};
      for (final r in refs) {
        counts[r] = (counts[r] ?? 0) + 1;
      }
      // A doubled initialization re-requests every setting. One pass may still
      // touch the firmware-version reference twice: the sweep reads it, then
      // _refreshDeviceInfo asks for it again on purpose.
      final repeated = counts.entries.where((e) => e.value > 2).toList();
      expect(
        repeated,
        isEmpty,
        reason: 'setting references requested more than twice: $repeated',
      );
      await unmount(tester);
    });

    testWidgets('disposing mid-initialization does not throw', (tester) async {
      final harness = await connectBle(tester);
      await pumpHeader(tester, harness.device);
      // Tear down while the post-attach initialization is still in flight.
      await unmount(tester);
      await pumpUntil(tester, () => false,
          timeout: const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('ShifterScreen', () {
    /// `0x17` — the gear-position setting reference the screen re-requests.
    const shifterReference = 0x17;

    testWidgets('re-requests the gear position on a new connected epoch', (
      tester,
    ) async {
      final harness = await connectBle(tester);
      await tester.pumpWidget(
        MaterialApp(home: ShifterScreen(device: harness.device)),
      );
      await pumpUntil(tester, () => false,
          timeout: const Duration(seconds: 1));

      blePlatform.markDisconnected(harness.device.remoteId);
      await pumpUntil(tester, () => !harness.deviceData.isTransportActive);

      blePlatform.clearObservations();
      blePlatform.markConnected(harness.device.remoteId);
      await pumpUntil(tester, () => harness.deviceData.isTransportActive);
      await pumpUntil(
        tester,
        () => ccReferences().contains(shifterReference),
        timeout: const Duration(seconds: 4),
      );
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        ccReferences().where((r) => r == shifterReference),
        hasLength(1),
        reason: 'a new connected epoch must re-confirm the gear with the device exactly once',
      );
      await unmount(tester);
    });

    testWidgets('re-requests the gear position after a DIRCON to BLE failover', (
      tester,
    ) async {
      // Over DIRCON the old raw-stream listener did nothing at all: it returned
      // early on `isDirConConnected`, and the stream it listened to never fires
      // for a network transport. A failover is a new connected session, and the
      // optimistic writes from the old one have to be invalidated.
      final s = await connectDirCon(tester, withParallelGatt: true);
      await tester.pumpWidget(
        MaterialApp(home: ShifterScreen(device: s.device)),
      );
      await pumpUntil(tester, () => false,
          timeout: const Duration(seconds: 1));

      blePlatform.clearObservations();
      s.conn.first.dropConnection();
      final failedOver = await pumpUntil(
        tester,
        () =>
            s.data.transportState.value.transport ==
                DeviceTransportKind.bluetooth &&
            s.data.transportState.value.phase ==
                DeviceTransportPhase.connected,
      );
      expect(failedOver, isTrue, reason: 'the failover never completed');
      await pumpUntil(
        tester,
        () => ccReferences().contains(shifterReference),
        timeout: const Duration(seconds: 4),
      );

      // Unlike the plain-BLE reconnect above, a DIRCON->BLE failover always
      // runs a full settings resweep on the new BLE session
      // (_sweepSettingsInBackground in device_data.dart), independently of
      // ShifterScreen. The gear reference is one of the ~48 references that
      // sweep reads, so it is legitimately touched twice here: once by that
      // sweep, once by the screen's own epoch-driven re-confirm.
      expect(
        ccReferences().where((r) => r == shifterReference),
        hasLength(2),
        reason:
            'the failover session must re-confirm the gear over BLE exactly once, '
            'plus the one touch from the fallback settings resweep',
      );
      await unmount(tester);
    });
  });

  group('BleLogScreen', () {
    /// `0x30` — the BLE log stream characteristic's setting reference byte.
    const logStreamReference = 0x30;

    bool loggingActive(WidgetTester tester) =>
        find.textContaining('Log streaming is active').evaluate().isNotEmpty;

    testWidgets('clears logging-enabled state on disconnect', (tester) async {
      final harness = await connectBle(tester);
      await tester.pumpWidget(
        MaterialApp(home: BleLogScreen(device: harness.device)),
      );
      await pumpUntil(tester, () => false,
          timeout: const Duration(seconds: 1));

      blePlatform.markDisconnected(harness.device.remoteId);
      await pumpUntil(tester, () => !harness.deviceData.isTransportActive);

      // The banner is the observable side of _loggingEnabled being cleared.
      expect(find.textContaining('disconnected'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('a reconnect over BLE re-enables log streaming', (
      tester,
    ) async {
      final harness = await connectBle(tester);
      await tester.pumpWidget(
        MaterialApp(home: BleLogScreen(device: harness.device)),
      );
      await pumpUntil(tester, () => loggingActive(tester),
          timeout: const Duration(seconds: 4));

      blePlatform.markDisconnected(harness.device.remoteId);
      await pumpUntil(tester, () => !harness.deviceData.isTransportActive);
      expect(loggingActive(tester), isFalse);

      blePlatform.clearObservations();
      blePlatform.markConnected(harness.device.remoteId);
      await pumpUntil(tester, () => harness.deviceData.isTransportActive);
      await pumpUntil(tester, () => loggingActive(tester),
          timeout: const Duration(seconds: 4));

      expect(
        ccReferences().where((r) => r == logStreamReference),
        isNotEmpty,
        reason: 'a new connected epoch must re-enable log streaming with the device',
      );
      await unmount(tester);
    });

    testWidgets('a DIRCON to BLE failover re-enables log streaming', (
      tester,
    ) async {
      final s = await connectDirCon(tester, withParallelGatt: true);
      await tester.pumpWidget(
        MaterialApp(home: BleLogScreen(device: s.device)),
      );
      await pumpUntil(tester, () => false,
          timeout: const Duration(seconds: 1));

      blePlatform.clearObservations();
      s.conn.first.dropConnection();
      final failedOver = await pumpUntil(
        tester,
        () =>
            s.data.transportState.value.transport ==
                DeviceTransportKind.bluetooth &&
            s.data.transportState.value.phase ==
                DeviceTransportPhase.connected,
      );
      expect(failedOver, isTrue, reason: 'the failover never completed');
      await pumpUntil(tester, () => loggingActive(tester),
          timeout: const Duration(seconds: 4));

      expect(
        ccReferences().where((r) => r == logStreamReference),
        isNotEmpty,
        reason: 'the failover session must re-enable log streaming over BLE',
      );
      await unmount(tester);
    });

    testWidgets(
      'a reconnect mid-enable is retried once the in-flight attempt finishes',
      (tester) async {
        // Regression test for the race the exactly-once retry queue fixes:
        // epoch N's enable write is still parked when epoch N+1 arrives.
        // Without a queued retry, epoch N+1's own attempt is dropped by the
        // non-reentrancy guard and epoch N's write lands too late to count
        // (sessionChanged), leaving the screen permanently not streaming.
        final harness = await connectBle(tester);

        blePlatform.holdWriteGate(ccUUID);
        blePlatform.clearObservations();

        await tester.pumpWidget(
          MaterialApp(home: BleLogScreen(device: harness.device)),
        );
        await pumpUntil(
          tester,
          () => blePlatform.writeGateWaiters(ccUUID) == 1,
        );

        blePlatform.markDisconnected(harness.device.remoteId);
        await pumpUntil(tester, () => !harness.deviceData.isTransportActive);
        blePlatform.markConnected(harness.device.remoteId);
        await pumpUntil(tester, () => harness.deviceData.isTransportActive);

        // Give the epoch-N+1 arrival's own enable attempt a chance to run
        // and observe "in progress" — it must queue, not park a second write.
        await pumpUntil(tester, () => false,
            timeout: const Duration(milliseconds: 200));
        expect(
          blePlatform.writeGateWaiters(ccUUID),
          1,
          reason:
              'the epoch-N+1 attempt must queue behind the in-flight write, not start its own',
        );

        blePlatform.releaseWriteGate(ccUUID);

        // Epoch N's write lands stale and is discarded; only the queued retry
        // for the current epoch can bring logging up.
        await pumpUntil(tester, () => loggingActive(tester),
            timeout: const Duration(seconds: 4));

        await unmount(tester);
      },
    );
  });

  group('deleted no-op listeners', () {
    testWidgets('a charReceived notification still rebuilds the settings tiles',
        (tester) async {
      // Step 6 deleted SettingsCategoryScreen's connection-state listener,
      // whose whole body was an unconditional setState. The tile list has to
      // keep rebuilding from the signals that remain — charReceived and
      // characteristicChanges — or that deletion cost real behaviour.
      final harness = await connectBle(tester);
      final data = harness.deviceData;
      for (final c in data.customCharacteristic) {
        if (c['isSetting'] == true && c['settingType'] == SettingType.basic) {
          c['value'] = '1';
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsCategoryScreen(
            device: harness.device,
            title: 'Basic',
            settingType: SettingType.basic,
          ),
        ),
      );
      // Let the screen's own setup traffic finish first; the fake answers
      // custom-characteristic reads on a microtask, which flips charReceived
      // back to true under any pump.
      await pumpUntil(tester, () => false,
          timeout: const Duration(seconds: 1));

      data.charReceived.value = false;
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.byType(SettingTile),
        findsNothing,
        reason: 'the tile list is gated on charReceived',
      );

      data.charReceived.value = true;
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        find.byType(SettingTile),
        findsWidgets,
        reason: 'charReceived must still drive the tile list rebuild',
      );
      await unmount(tester);
    });
  });
}

int _dirConId = 1;
