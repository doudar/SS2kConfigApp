import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/dircon_discovery.dart';
import 'package:ss2kconfigapp/utils/smartspin_scan_result.dart';
import 'package:ss2kconfigapp/widgets/scan_result_tile.dart';

import 'support/fake_dircon_session.dart';
import 'support/fake_ble_platform.dart';

const endpoint = DirConEndpoint(
  isSmartSpin: true,
  id: 'aabbccddeeff',
  name: 'My Bike',
  host: '192.168.1.50',
  port: 8082,
);

ScanResult ble({
  String id = 'opaque-apple-uuid',
  String name = 'My Bike',
  String? ip,
  bool smartSpin = true,
  bool ftms = false,
}) => ScanResult(
  device: BluetoothDevice.fromId(id),
  timeStamp: DateTime(2026),
  rssi: -60,
  advertisementData: AdvertisementData(
    advName: name,
    appearance: null,
    connectable: true,
    txPowerLevel: null,
    serviceData: {},
    serviceUuids: smartSpin
        ? [Guid(csUUID)]
        : [Guid(ftms ? ftmsServiceUUID : '180d')],
    manufacturerData: ip == null
        ? {}
        : {
            0xffff: [0x53, 0x53, 1, ...ip.split('.').map(int.parse)],
          },
  ),
);

BonsoirService service({
  List<String> hosts = const ['192.168.1.50'],
  String? uuids,
}) => BonsoirService.ignoreNorms(
  name: 'My Bike',
  type: DirConEndpoint.serviceType,
  port: 8082,
  hostAddresses: hosts,
  attributes: {
    'ble-service-uuids': uuids ?? '1826,${csUUID.toUpperCase()}',
    'mac-address': 'AA-BB-CC-DD-EE-FF',
    'serial-number': '414142424343',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;

  setUp(() async {
    await FlutterBluePlus.isSupported;
    platform.reset();
  });

  test(
    'recognizes renamed SS2k by UUID and uses resolved address and port',
    () {
      final found = DirConEndpoint.fromService(
        service(hosts: ['fe80::1', endpoint.host]),
      )!;
      expect(found.id, endpoint.id);
      expect(found.host, endpoint.host);
      expect(found.port, 8082);
      expect(found.name, 'My Bike');
      expect(
        DirConEndpoint.fromService(
          service(uuids: '0x180d,0x1826'),
        )!.isSmartSpin,
        isFalse,
      );
      expect(DirConEndpoint.fromService(service(uuids: '180d')), isNull);
      expect(DirConEndpoint.fromService(service(hosts: [])), isNull);
    },
  );

  test(
    'workout discovery keeps a same-named FTMS trainer separate from SmartSpin2k',
    () {
      final trainer = ble(id: 'ftms', smartSpin: false, ftms: true);
      final sensor = ble(id: 'sensor', smartSpin: false);
      final devices = SmartSpinScanResult.merge(
        [trainer, sensor],
        [endpoint],
        includeFtms: true,
      );
      expect(devices.map((d) => d.isSmartSpin), [true, false]);
      expect(devices.last.device, trainer.device);
      expect(devices.last.host, isNull);
      expect(SmartSpinScanResult.merge([trainer], []), isEmpty);
    },
  );

  for (final smartSpin in [false, true]) {
    test(
      'workout-only BLE setup, telemetry and acknowledged control (SmartSpin2k=$smartSpin)',
      () async {
        platform.discoveryIncludesCustomService = smartSpin;
        final result = SmartSpinScanResult(
          ble: ble(id: 'workout-$smartSpin', smartSpin: smartSpin, ftms: true),
        );
        final data = DeviceData();
        addTearDown(data.dispose);
        await data.connectFromScan(result, workoutOnly: smartSpin);
        expect(data.isTransportActive, isTrue);
        expect(data.hasPairedSession, isFalse);
        expect(
          platform.notifyCalls.any((c) => c.uuid == Guid(ccUUID).str),
          isFalse,
        );
        expect(platform.writeCalls, isEmpty);

        platform.emitNotification(
          result.device.remoteId,
          ftmsIndoorBikeDataUUID,
          [4, 0, 0xc4, 9, 160, 0],
        );
        platform.emitNotification(
          result.device.remoteId,
          ftmsIndoorBikeDataUUID,
          [0x41, 3, 210, 0, 1, 2, 3, 4, 5, 142],
        );
        await waitUntil(() => data.ftmsData.heartRate == 142);
        expect(data.ftmsData.speed, 25);
        expect(data.ftmsData.cadence, 80);
        expect(data.ftmsData.watts, 210);

        data.setWorkoutTargetPower(220, resetSimulationFirst: true);
        Future<void> acknowledge(int index, List<int> command) async {
          await waitUntil(() => platform.writes.length > index);
          expect(platform.writes[index], command);
          platform.emitNotification(
            result.device.remoteId,
            ftmsControlPointUUID,
            [0x80, command.first, 1],
          );
        }

        await acknowledge(0, [0]);
        await acknowledge(1, [7]);
        await acknowledge(2, [5, 220, 0]);
        data.endWorkoutControl();
        await acknowledge(3, [8, 1]);
        await data.disconnectPreferred(result.device);
      },
    );
  }

  test('FTMS starts before applying a superseding workout target', () async {
    final result = SmartSpinScanResult(ble: ble(smartSpin: false, ftms: true));
    platform.discoveryIncludesCustomService = false;
    final data = DeviceData();
    addTearDown(data.dispose);
    await data.connectFromScan(result);
    var nextWrite = 0;
    Future<void> acknowledge(
      List<int> command, {
      void Function()? beforeReply,
    }) async {
      await waitUntil(() => platform.writes.length > nextWrite);
      expect(platform.writes[nextWrite++], command);
      beforeReply?.call();
      platform.emitNotification(result.device.remoteId, ftmsControlPointUUID, [
        0x80,
        command.first,
        1,
      ]);
    }

    data.setWorkoutTargetPower(150);
    await acknowledge([0], beforeReply: () => data.setWorkoutTargetPower(175));
    await acknowledge([7], beforeReply: () => data.setWorkoutTargetPower(190));
    await acknowledge([5, 190, 0]);
    data.endWorkoutControl();
    await acknowledge([
      8,
      1,
    ], beforeReply: () => data.setWorkoutTargetPower(210));
    await acknowledge([7]);
    await acknowledge([5, 210, 0]);
    await data.disconnectPreferred(result.device);
  });

  test(
    'a refused control request leaves telemetry working and sends no target',
    () async {
      final result = SmartSpinScanResult(
        ble: ble(smartSpin: false, ftms: true),
      );
      platform.discoveryIncludesCustomService = false;
      final data = DeviceData();
      addTearDown(data.dispose);
      await data.connectFromScan(result);
      data.setWorkoutTargetPower(150);
      await waitUntil(() => platform.writes.isNotEmpty);
      platform.emitNotification(result.device.remoteId, ftmsControlPointUUID, [
        0x80,
        0,
        5,
      ]);
      await waitUntil(
        () => data.workoutControlNotice.value == 'Trainer control unavailable',
      );
      expect(platform.writes, [
        [0],
      ]);
      platform.emitNotification(
        result.device.remoteId,
        ftmsIndoorBikeDataUUID,
        [0x40, 0, 0, 0, 93, 0],
      );
      await waitUntil(() => data.ftmsData.watts == 93);
      await data.disconnectPreferred(result.device);
    },
  );

  for (final smartSpin in [true, false]) {
    test(
      'DirCon ERG rejection is temporary only for SmartSpin2k (SmartSpin2k=$smartSpin)',
      () async {
        final socket = FakeDirConSession();
        final data = DeviceData(dirConConnector: (_) async => socket);
        addTearDown(data.dispose);
        final result = SmartSpinScanResult(
          network: DirConEndpoint.fromService(
            service(uuids: smartSpin ? csUUID : ftmsServiceUUID),
          ),
        );
        await data.connectFromScan(result, workoutOnly: true);
        Future<void> reply(int index, List<int> command, int resultCode) async {
          await waitUntil(() => socket.writes.length > index);
          expect(socket.writes[index].value, command);
          socket.emitNotification(ftmsControlPointUUID, [
            0x80,
            command.first,
            resultCode,
          ]);
        }

        data.setWorkoutTargetPower(180);
        await reply(0, [0], 1);
        await reply(1, [7], 1);
        await reply(2, [5, 180, 0], 2);
        await waitUntil(
          () =>
              data.workoutControlNotice.value ==
              (smartSpin
                  ? 'ERG waiting for trainer sensors'
                  : 'ERG targets unsupported'),
        );
        if (smartSpin) {
          // The same target must be retried without reconnecting or changing watts.
          await reply(3, [5, 180, 0], 1);
          await waitUntil(() => data.workoutControlNotice.value == null);
        } else {
          data.setWorkoutTargetPower(190);
          await Future<void>.delayed(Duration.zero);
          expect(socket.writes, hasLength(3));
        }
        data.endWorkoutControl();
        await reply(smartSpin ? 4 : 3, [8, 1], 1);
        await data.disconnectPreferred(result.device);
      },
    );
  }

  test('workout reconnect retains FTMS-only access', () async {
    final result = SmartSpinScanResult(ble: ble(id: 'workout-reconnect'));
    final data = DeviceData();
    addTearDown(data.dispose);
    await data.connectFromScan(result, workoutOnly: true);
    final epoch = data.transportState.value.epoch;
    data.startConnectionMonitor(result.device);
    addTearDown(data.stopConnectionMonitor);
    platform.markDisconnected(result.device.remoteId);
    await waitUntil(
      () =>
          data.transportState.value.epoch > epoch &&
          data.controlPointNotificationsLive,
    );
    expect(data.workoutOnly, isTrue);
    expect(platform.writes, isEmpty);
    expect(
      platform.notifyCalls.any((c) => c.uuid == Guid(ccUUID).str),
      isFalse,
    );
    await data.disconnectPreferred(result.device);
  });

  test(
    'telemetry-only trainers work and other FTMS machines are rejected',
    () async {
      final result = SmartSpinScanResult(
        ble: ble(id: 'telemetry', smartSpin: false, ftms: true),
      );
      platform.discoveryIncludesCustomService = false;
      platform.discoveryIncludesControlPoint = false;
      final data = DeviceData();
      addTearDown(data.dispose);
      await data.connectFromScan(result, workoutOnly: true);
      expect(data.workoutControlNotice.value, 'Ride data only');
      data.setWorkoutTargetPower(140);
      expect(platform.writes, isEmpty);
      await data.disconnectPreferred(result.device);
      platform.discoveryIncludesIndoorBike = false;
      await expectLater(
        data.connectFromScan(result, workoutOnly: true),
        throwsStateError,
      );
      expect(data.isTransportActive, isFalse);
    },
  );

  test(
    'FTMS-only mDNS advertisements connect on their advertised port without BLE or pairing',
    () async {
      final socket = FakeDirConSession()..failCharacteristic(ccUUID);
      final data = DeviceData(dirConConnector: (_) async => socket);
      addTearDown(data.dispose);
      final advertised = DirConEndpoint.fromService(
        service(uuids: ftmsServiceUUID),
      )!;
      expect(advertised.isSmartSpin, isFalse);
      expect(
        DirConEndpoint.fromService(service(uuids: ''))!.isSmartSpin,
        isFalse,
      );
      expect(SmartSpinScanResult.merge([], [advertised]), isEmpty);
      final result = SmartSpinScanResult.merge([], [
        advertised,
      ], includeFtms: true).single;
      expect(result.isSmartSpin, isFalse);
      await data.connectFromScan(result);
      expect(data.advertisedDirConPort, 8082);
      expect(data.workoutOnly, isTrue);
      expect(platform.connectCalls, isEmpty);
      socket.emitNotification(ftmsIndoorBikeDataUUID, [0x40, 0, 0, 0, 175, 0]);
      await waitUntil(() => data.ftmsData.watts == 175);
      expect(data.isDirConConnected, isTrue);
      expect(socket.writes, isEmpty);
      expect(data.hasPairedSession, isFalse);
      socket.respondToWrites(ftmsControlPointUUID, [0x80, 0, 1]);
      data.setWorkoutTargetPower(200);
      await waitUntil(() => socket.writesFor(ftmsControlPointUUID).length == 2);
      socket.emitNotification(ftmsControlPointUUID, [0x80, 7, 1]);
      await waitUntil(() => socket.writesFor(ftmsControlPointUUID).length == 3);
      expect(socket.writesFor(ftmsControlPointUUID), [
        [0],
        [7],
        [5, 200, 0],
      ]);
      socket.emitNotification(ftmsControlPointUUID, [0x80, 5, 1]);
      await Future<void>.delayed(Duration.zero);
      await data.disconnectPreferred(result.device);
    },
  );

  test('both arrival orders merge by IP and prefer mDNS', () {
    final bluetooth = ble(name: 'Old Name', ip: endpoint.host);
    expect(SmartSpinScanResult.merge([bluetooth], []).single.network, isNull);
    expect(SmartSpinScanResult.merge([], [endpoint]).single.ble, isNull);
    final merged = SmartSpinScanResult.merge([bluetooth], [endpoint]).single;
    expect(merged.device, bluetooth.device);
    expect(merged.network, endpoint);
    expect(merged.name, 'My Bike');
    expect(merged.host, endpoint.host);
  });

  test(
    'legacy advertisements merge by unique name, conflicting IPs do not',
    () {
      expect(SmartSpinScanResult.merge([ble()], [endpoint]).length, 1);
      expect(
        SmartSpinScanResult.merge([ble(ip: '192.168.1.99')], [endpoint]).length,
        2,
      );
      expect(
        SmartSpinScanResult.merge(
          [ble(), ble(id: 'second')],
          [endpoint],
        ).length,
        3,
      );
      expect(
        SmartSpinScanResult.merge([ble(smartSpin: false)], [endpoint]).length,
        1,
      );
    },
  );

  test(
    'same-named SS2ks and duplicate mDNS updates retain distinct identities',
    () {
      const second = DirConEndpoint(
        isSmartSpin: true,
        id: 'other',
        name: 'My Bike',
        host: '192.168.1.51',
        port: 8081,
      );
      final results = SmartSpinScanResult.merge(
        [ble(ip: endpoint.host), ble(id: 'second', ip: second.host)],
        [endpoint, second, endpoint],
      );
      expect(results.length, 2);
      expect(results.every((r) => r.ble != null && r.network != null), isTrue);
      expect(SmartSpinScanResult.merge([ble()], [endpoint, second]).length, 3);
    },
  );

  test(
    'network-only connect and reconnect use Dircon without a BLE scan',
    () async {
      const moved = DirConEndpoint(
        isSmartSpin: true,
        id: 'aabbccddeeff',
        name: 'My Bike',
        host: '192.168.1.77',
        port: 9090,
      );
      final connector = FakeDirConConnector([
        FakeDirConSession(),
        FakeDirConSession(),
      ]);
      var lookups = 0;
      final data = DeviceData(
        dirConConnector: connector.call,
        dirConEndpointLookup: ({id, host, name}) async {
          lookups++;
          expect(id, endpoint.id);
          return moved;
        },
      );
      const result = SmartSpinScanResult(network: endpoint);
      data.applyScanResult(result);
      addTearDown(data.dispose);
      await data.connectPreferred(result.device, waitForSetup: true);
      expect(connector.hosts, [endpoint.host]);
      expect(data.advertisedDirConPort, endpoint.port);
      data.startConnectionMonitor(result.device);
      final reconnected = Completer<void>();
      data.startConnectionMonitor(
        result.device,
        onReconnected: () async {
          if (!reconnected.isCompleted) reconnected.complete();
        },
      );
      connector.first.dropConnection();
      await reconnected.future.timeout(const Duration(seconds: 5));
      expect(lookups, 1);
      expect(connector.hosts, [endpoint.host, moved.host]);
      expect(data.advertisedDirConPort, moved.port);
      expect(data.isDirConConnected, isTrue);
      data.stopConnectionMonitor();
      data.stopConnectionMonitor();
    },
  );

  test(
    'BLE reconnect also discovers and prefers a fresh mDNS endpoint',
    () async {
      final connector = FakeDirConConnector();
      final data = DeviceData(
        dirConConnector: connector.call,
        dirConEndpointLookup: ({id, host, name}) async => endpoint,
      );
      final result = SmartSpinScanResult(ble: ble());
      data.applyScanResult(result);
      addTearDown(data.dispose);
      expect(
        await data.reconnectAndSetup(result.device, maxAttempts: 1),
        isTrue,
      );
      expect(data.isDirConConnected, isTrue);
      expect(connector.hosts, [endpoint.host]);
    },
  );

  test(
    'network-only failure never falls back to a synthetic BLE identifier',
    () async {
      final connector = FakeDirConConnector()
        ..connectFailure = StateError('offline');
      final data = DeviceData(dirConConnector: connector.call);
      const result = SmartSpinScanResult(network: endpoint);
      data.applyScanResult(result);
      addTearDown(data.dispose);
      await expectLater(data.connectPreferred(result.device), throwsStateError);
      expect(connector.hosts, [endpoint.host]);
      expect(data.isTransportActive, isFalse);
    },
  );

  test(
    'late BLE discovery reuses an existing network connection on reopen',
    () async {
      final connector = FakeDirConConnector();
      final data = DeviceData(dirConConnector: connector.call);
      const result = SmartSpinScanResult(network: endpoint);
      data.applyScanResult(result);
      DeviceDataManager.updateDataForDevice(result.device, data);
      addTearDown(() {
        DeviceDataManager.clearDataForDevice(result.device);
        data.dispose();
      });
      await data.connectPreferred(result.device, waitForSetup: true);
      final merged = SmartSpinScanResult.merge(
        [ble(ip: endpoint.host)],
        [endpoint],
      ).single;
      final reused = DeviceDataManager.reuseConnectedIdentity(merged);
      expect(reused.device, result.device);
      data.applyScanResult(reused);
      expect(DeviceDataManager.forDevice(reused.device), same(data));
      expect(data.isTransportActive, isTrue);
      expect(connector.hosts, [endpoint.host]);
    },
  );

  for (final throughMerge in [true, false]) {
    test(
      'late BLE handle enables fallback without replacing state ($throughMerge)',
      () async {
        final connector = FakeDirConConnector();
        final data = DeviceData(
          dirConConnector: connector.call,
          dirConEndpointLookup: ({id, host, name}) async => null,
        );
        const initial = SmartSpinScanResult(network: endpoint);
        final bluetooth = ble(id: 'late-ble-$throughMerge', ip: endpoint.host);
        data.applyScanResult(initial);
        DeviceDataManager.updateDataForDevice(initial.device, data);
        addTearDown(() async {
          data.stopConnectionMonitor();
          data.dispose();
          DeviceDataManager.clearDataForDevice(initial.device);
          platform.markDisconnected(bluetooth.device.remoteId);
          await Future<void>.delayed(Duration.zero);
        });
        await data.connectPreferred(initial.device, waitForSetup: true);
        // Keep the background settings sweep out of this transport assertion.
        data.beginInteractiveFtmsSession(initial.device);
        final recovered = Completer<void>();
        data.startConnectionMonitor(
          initial.device,
          onReconnected: () async {
            if (!recovered.isCompleted) recovered.complete();
          },
        );
        data.ftmsData.watts = 217;
        final state = data.transportState.value;
        final services = data.services;
        final merged = SmartSpinScanResult.merge(
          [bluetooth],
          [endpoint],
        ).single;
        if (throughMerge) {
          // Merely discovering the advertisement must update the active session.
          final reused = DeviceDataManager.reuseConnectedIdentity(merged);
          expect(reused.device, initial.device);
          expect(DeviceDataManager.forDevice(reused.device), same(data));
        } else {
          // The tile's apply path must also work while DIRCON remains connected.
          data.applyScanResult(
            SmartSpinScanResult(
              ble: bluetooth,
              network: endpoint,
              connectedIdentity: initial.device,
            ),
          );
        }
        expect(data.resolveTransportDevice(initial.device), bluetooth.device);
        expect(data.transportState.value, same(state));
        expect(data.services, same(services));
        expect(data.ftmsData.watts, 217);
        expect(connector.first.isClosed, isFalse);
        expect(platform.connectCalls, isEmpty);
        connector.first.dropConnection();
        await recovered.future.timeout(const Duration(seconds: 5));
        expect(platform.connectCalls.map((c) => c.remoteId), [
          bluetooth.device.remoteId,
        ]);
        expect(
          data.transportState.value.transport,
          DeviceTransportKind.bluetooth,
        );
        expect(data.isTransportActive, isTrue);
        expect(
          data.ftmsControlPointCharacteristic!.remoteId,
          bluetooth.device.remoteId,
        );
        // The original open screen still addresses the same session after fallback.
        expect(
          DeviceDataManager.reuseConnectedIdentity(merged).device,
          initial.device,
        );
        await data.setupConnection(initial.device, sweepSettings: false);
        expect(data.resolveTransportDevice(initial.device), bluetooth.device);
        // Promotion must not add a second owner to the monitor's reference count.
        data.stopConnectionMonitor();
        platform.clearObservations();
        platform.markDisconnected(bluetooth.device.remoteId);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(platform.connectCalls, isEmpty);
      },
    );
  }

  testWidgets(
    'network-only scan tile displays blue router and enables connect',
    (tester) async {
      var tapped = false;
      const result = SmartSpinScanResult(network: endpoint);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanResultTile(result: result, onTap: () => tapped = true),
          ),
        ),
      );
      expect(find.text('My Bike'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.router));
      expect(icon.color, Colors.lightBlueAccent);
      await tester.tap(find.text('CONNECT'));
      expect(tapped, isTrue);
      await tester.pumpWidget(const SizedBox());
      DeviceDataManager.forDevice(result.device).dispose();
      DeviceDataManager.clearDataForDevice(result.device);
    },
  );

  testWidgets('FTMS trainer scan tile uses a bike icon', (tester) async {
    final result = SmartSpinScanResult(ble: ble(smartSpin: false, ftms: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScanResultTile(result: result)),
      ),
    );
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      const AssetImage('assets/ftms_trainer.png'),
    );
    await tester.pumpWidget(const SizedBox());
    DeviceDataManager.forDevice(result.device).dispose();
    DeviceDataManager.clearDataForDevice(result.device);
  });

  testWidgets(
    'BLE-only scan tile with advertised hotspot IP shows RSSI, not Dircon',
    (tester) async {
      final result = SmartSpinScanResult(ble: ble(ip: '192.168.4.1'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScanResultTile(result: result)),
        ),
      );
      expect(find.byIcon(Icons.router), findsNothing);
      await tester.tap(find.text('My Bike'));
      await tester.pumpAndSettle();
      expect(find.text('Dircon'), findsNothing);
      expect(find.text('RSSI'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      DeviceDataManager.forDevice(result.device).dispose();
      DeviceDataManager.clearDataForDevice(result.device);
    },
  );
}
