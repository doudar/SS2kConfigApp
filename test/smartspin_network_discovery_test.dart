import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/dircon_discovery.dart';
import 'package:ss2kconfigapp/utils/smartspin_scan_result.dart';
import 'package:ss2kconfigapp/widgets/scan_result_tile.dart';

import 'support/fake_dircon_session.dart';

const endpoint = DirConEndpoint(
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
    serviceUuids: smartSpin ? [Guid(csUUID)] : [Guid('180d')],
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
      expect(DirConEndpoint.fromService(service(uuids: '1826,180d')), isNull);
      expect(DirConEndpoint.fromService(service(hosts: [])), isNull);
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
}
