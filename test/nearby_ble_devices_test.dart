import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_scan_results_protocol.dart';
import 'package:ss2kconfigapp/utils/ble_sensor_services.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/nearby_ble_devices.dart';

ScanResult _result({
  required String id,
  required String name,
  required List<String> services,
  Map<int, List<int>> manufacturerData = const {},
}) {
  return ScanResult(
    device: BluetoothDevice.fromId(id),
    timeStamp: DateTime(2026),
    advertisementData: AdvertisementData(
      advName: name,
      appearance: null,
      connectable: true,
      serviceUuids: services.map(Guid.new).toList(),
      serviceData: const {},
      txPowerLevel: null,
      manufacturerData: manufacturerData,
    ),
    rssi: -55,
  );
}

void main() {
  setUp(NearbyBleDevices.instance.clear);
  tearDown(NearbyBleDevices.instance.clear);

  test('matches firmware filtering, service priority, and public name', () {
    final candidate = NearbyBleDevices.fromScanResult(
      _result(
        id: 'C2:11:22:33:44:A2',
        name: 'SmartTestS3',
        services: ['180d', '1818'],
      ),
    );

    expect(candidate?.name, 'SmartTestS3 a2');
    expect(candidate?.uuid, '0x1818');
  });

  test('uses manufacturer suffix for firmware-classified private address', () {
    final candidate = NearbyBleDevices.fromScanResult(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HEART RATE',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x0f],
        },
      ),
    );

    expect(candidate?.name, 'COROS HEART RATE 0f');
    expect(candidate?.uuid, '0x180d');
  });

  test('retains the most recently observed name without interpreting it', () {
    final cache = NearbyBleDevices.instance;
    cache.observe(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HR C9340F',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );
    cache.observe(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HEART RATE C9340F',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );
    // Until firmware supplies its authoritative name, use exactly what the
    // phone most recently received.
    cache.observe(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HR C9340F',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );

    expect(cache.devices, hasLength(1));
    expect(cache.devices.single.name, 'COROS HR C9340F 68');
  });

  test('reconciles different names by unique firmware suffix and category', () {
    final cache = NearbyBleDevices.instance;
    cache.observe(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HR C9340F',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );

    final reconciled = cache.reconcileFirmwareDevice(
      const BleScanDevice(name: 'COROS HEART RATE C9340F 68', uuid: '0x180d'),
    );

    expect(reconciled.address, '42:11:22:33:44:55');
    expect(cache.devices, hasLength(1));
    expect(cache.devices.single.name, 'COROS HEART RATE C9340F 68');
  });

  test('does not reconcile an ambiguous suffix', () {
    final cache = NearbyBleDevices.instance;
    for (final id in ['42:11:22:33:44:55', '43:11:22:33:44:66']) {
      cache.observe(
        _result(
          id: id,
          name: id.startsWith('42') ? 'COROS HR C9340F' : 'Other HRM',
          services: ['180d'],
          manufacturerData: {
            0x1234: [0x90, 0x68],
          },
        ),
      );
    }

    final reconciled = cache.reconcileFirmwareDevice(
      const BleScanDevice(name: 'COROS HEART RATE C9340F 68', uuid: '0x180d'),
    );

    expect(reconciled.address, isNull);
    expect(cache.devices, hasLength(2));
    expect(
      cache.devices.map((device) => device.name),
      isNot(contains('COROS HEART RATE C9340F 68')),
    );
  });

  test('exact name wins even when another peer shares the suffix', () {
    final cache = NearbyBleDevices.instance;
    cache.observe(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HEART RATE C9340F',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );
    cache.observe(
      _result(
        id: '43:11:22:33:44:66',
        name: 'Other HRM',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );

    final reconciled = cache.reconcileFirmwareDevice(
      const BleScanDevice(name: 'COROS HEART RATE C9340F 68', uuid: '0x180d'),
    );

    expect(reconciled.address, '42:11:22:33:44:55');
  });

  test('prefers FTMS just like the firmware IC4 workaround', () {
    final candidate = NearbyBleDevices.fromScanResult(
      _result(
        id: 'C2:11:22:33:44:66',
        name: 'Bike',
        services: ['1818', '1826'],
      ),
    );

    expect(candidate?.uuid, '0x1826');
  });

  test('picker categories include every firmware-supported power service', () {
    expect(isHeartRateDeviceServiceUuid('0x180d'), isTrue);
    expect(isPowerMeterDeviceServiceUuid('0x1818'), isTrue);
    expect(isPowerMeterDeviceServiceUuid('0x1816'), isTrue);
    expect(isPowerMeterDeviceServiceUuid('0x1826'), isTrue);
    expect(
      isPowerMeterDeviceServiceUuid('0bf669f1-45f2-11e7-9598-0800200c9a66'),
      isTrue,
    );
    expect(
      isPowerMeterDeviceServiceUuid('a026ee07-0a7d-4ab3-97fa-f1500f9feb8b'),
      isTrue,
    );
    expect(isPowerMeterDeviceServiceUuid('0x1812'), isFalse);
  });

  test('filters unsupported devices and unsafe opaque platform IDs', () {
    expect(
      NearbyBleDevices.fromScanResult(
        _result(
          id: 'C2:11:22:33:44:77',
          name: 'Unsupported',
          services: ['180f'],
        ),
      ),
      isNull,
    );
    expect(
      NearbyBleDevices.fromScanResult(
        _result(
          id: 'F1D0C3CB-6A90-4F01-884B-22FCE78F9F80',
          name: 'Apple-visible sensor',
          services: ['180d'],
        ),
      ),
      isNull,
    );
  });

  test(
    'firmware discoveries seed later iOS connections without an address',
    () {
      final cache = NearbyBleDevices.instance;
      final iosSmartSpin = BluetoothDevice.fromId(
        'F1D0C3CB-6A90-4F01-884B-22FCE78F9F80',
      );

      final reconciled = cache.reconcileFirmwareDevice(
        const BleScanDevice(name: 'COROS HEART RATE C9340F 68', uuid: '0x180d'),
      );
      final seeds = cache.scanDevicesFor(iosSmartSpin).toList();

      expect(reconciled.address, isNull);
      expect(cache.devices, isEmpty);
      expect(seeds, hasLength(1));
      expect(seeds.single.name, 'COROS HEART RATE C9340F 68');
      expect(seeds.single.uuid, '0x180d');
      expect(seeds.single.address, isNull);
    },
  );

  test('seeds a connection, excludes itself, and merges firmware names', () {
    final cache = NearbyBleDevices.instance;
    final smartSpin = BluetoothDevice.fromId('C2:11:22:33:44:88');
    cache.observe(
      _result(
        id: smartSpin.remoteId.str,
        name: 'SmartBenchS3',
        services: [csUUID, '1818'],
      ),
    );
    cache.observe(
      _result(id: 'C2:11:22:33:44:A2', name: 'Power Meter', services: ['1818']),
    );

    final data = DeviceDataManager.forDevice(smartSpin);
    addTearDown(() {
      DeviceDataManager.clearDataForDevice(smartSpin);
      data.dispose();
    });

    final foundDevices = data.customCharacteristic.firstWhere(
      (characteristic) => characteristic['vName'] == foundDevicesVname,
    );
    var encoded = foundDevices['value'] as String;
    expect(encoded, contains('Power Meter a2'));
    expect(encoded, isNot(contains('SmartBenchS3')));

    // Results tied to the same phone-visible address replace the earlier
    // observation even when the reported service or name casing changes.
    data.mergeAppDiscoveredBleDevices(const [
      BleScanDevice(
        name: 'POWER METER A2',
        uuid: '0x1826',
        address: 'C2:11:22:33:44:A2',
      ),
    ]);
    encoded = foundDevices['value'] as String;
    final decoded = jsonDecode(encoded) as List<dynamic>;
    final group = decoded.single as Map<String, dynamic>;
    final matching = group.values.where(
      (entry) =>
          entry is Map &&
          entry['name'].toString().toLowerCase() == 'power meter a2',
    );
    expect(matching, hasLength(1));
    expect((matching.single as Map)['UUID'], '0x1826');

    cache.observe(
      _result(
        id: '42:11:22:33:44:55',
        name: 'COROS HR C9340F',
        services: ['180d'],
        manufacturerData: {
          0x1234: [0x90, 0x68],
        },
      ),
    );
    data.mergeAppDiscoveredBleDevices(cache.scanDevicesFor(smartSpin));
    encoded = foundDevices['value'] as String;
    expect(encoded, contains('COROS HR C9340F 68'));

    cache.reconcileFirmwareDevice(
      const BleScanDevice(name: 'COROS HEART RATE C9340F 68', uuid: '0x180d'),
    );
    data.mergeAppDiscoveredBleDevices(cache.scanDevicesFor(smartSpin));
    encoded = foundDevices['value'] as String;
    expect(encoded, contains('COROS HEART RATE C9340F 68'));
    expect(encoded, isNot(contains('COROS HR C9340F 68')));
  });
}
