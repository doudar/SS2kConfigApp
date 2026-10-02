import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/dircon_discovery.dart';
import 'package:ss2kconfigapp/utils/dircon_client.dart';
import 'package:ss2kconfigapp/utils/smartspin_scan_result.dart';

import 'support/fake_ble_platform.dart';
import 'support/fake_dircon_session.dart';

const endpoint = DirConEndpoint(
  id: 'trainer',
  name: 'SmartSpin2k',
  host: '192.168.1.51',
  port: 8081,
);

// Keep settings traffic out of transport timing assertions.
class _RecoveryData extends DeviceData {
  _RecoveryData({
    required DirConConnector dirConConnector,
    required DirConEndpointLookup dirConEndpointLookup,
  }) : super(
         dirConConnector: dirConConnector,
         dirConEndpointLookup: dirConEndpointLookup,
       );

  @override
  Future<void> requestSettings(BluetoothDevice device) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;
  setUpAll(() async {
    await FlutterBluePlus.isSupported;
  });
  var serial = 0;
  late BluetoothDevice device;
  late DeviceData data;
  late FakeDirConConnector connector;
  var lookups = 0;
  Future<DirConEndpoint?> Function()? lookup;
  Completer<void>? connectionGate;

  Future<void> advanceUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 400 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(ready(), isTrue);
  }

  Future<void> fallBack(
    WidgetTester tester, {
    bool networkOnly = false,
    bool bleUnavailable = false,
    bool failedHandshake = false,
  }) async {
    await FlutterBluePlus.isSupported;
    platform.reset();
    device = BluetoothDevice.fromId('recovery-${serial++}');
    lookups = 0;
    lookup = null;
    connectionGate = null;
    connector = FakeDirConConnector([
      FakeDirConSession(),
      if (failedHandshake)
        FakeDirConSession()..initializeFailure = StateError('Not ready'),
      FakeDirConSession(host: endpoint.host),
      FakeDirConSession(host: endpoint.host),
    ]);
    data = _RecoveryData(
      dirConConnector: (host) async {
        final session = await connector.call(host);
        final gate = connectionGate;
        connectionGate = null;
        if (gate != null) await gate.future;
        return session;
      },
      dirConEndpointLookup: ({id, host, name}) async {
        lookups++;
        return lookup == null ? null : await lookup!();
      },
    )..advertisedIpAddress = '192.168.1.50';
    if (networkOnly) {
      const result = SmartSpinScanResult(network: endpoint);
      data.applyScanResult(result);
      device = result.device;
    } else if (bleUnavailable) {
      platform.connectFailure = StateError('Bluetooth unavailable');
    } else {
      platform.markConnected(device.remoteId);
    }
    var connected = false;
    final initial = data.connectPreferred(device, waitForSetup: true)
      ..then((_) => connected = true);
    await advanceUntil(tester, () => connected);
    await initial;
    var fallbackComplete = false;
    data.startConnectionMonitor(
      device,
      onReconnected: () async {
        fallbackComplete = true;
      },
    );
    connector.first.dropConnection();
    await advanceUntil(
      tester,
      () => networkOnly
          ? lookups == 1
          : bleUnavailable
          ? platform.connectCalls.isNotEmpty
          : data.transportState.value.transport ==
                    DeviceTransportKind.bluetooth &&
                data.isTransportActive &&
                fallbackComplete,
    );
    // Let fallback callbacks and the background sweep settle without reaching
    // the first three-second recovery timer.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(lookups, 1);
    platform.clearObservations();
  }

  Future<void> finish(WidgetTester tester) async {
    data.stopConnectionMonitor();
    data.dispose();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 20));
  }

  testWidgets('returns to DIRCON after Wi-Fi boots, without reconnecting BLE', (
    tester,
  ) async {
    await fallBack(tester);
    lookup = () async => endpoint;
    await tester.pump(const Duration(seconds: 2));
    expect(lookups, 1);
    await tester.pump(const Duration(seconds: 1));
    await advanceUntil(tester, () => data.isDirConConnected);
    expect(data.advertisedIpAddress, endpoint.host);
    expect(connector.hosts, ['192.168.1.50', endpoint.host]);
    expect(platform.connectCalls, isEmpty);
    expect(device.isConnected, isTrue);
    await tester.pump(const Duration(minutes: 2));
    expect(lookups, 2);
    await finish(tester);
  });

  testWidgets('unavailable Wi-Fi gets only three spaced checks and keeps BLE', (
    tester,
  ) async {
    await fallBack(tester);
    final epoch = data.transportState.value.epoch;
    for (final seconds in [3, 8, 15]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(lookups, 4); // Initial recovery plus three follow-ups.
    await tester.pump(const Duration(minutes: 5));
    expect(lookups, 4);
    expect(connector.hosts, ['192.168.1.50']);
    expect(data.transportState.value.epoch, epoch);
    expect(data.isTransportActive, isTrue);
    expect(platform.connectCalls, isEmpty);
    await finish(tester);
  });

  testWidgets('failed handshake leaves BLE streams intact and retries later', (
    tester,
  ) async {
    await fallBack(tester, failedHandshake: true);
    lookup = () async => endpoint;
    final epoch = data.transportState.value.epoch;
    final controlPoint = data.ftmsControlPointCharacteristic;
    await tester.pump(const Duration(seconds: 3));
    await advanceUntil(tester, () => connector.last.isClosed);
    expect(data.transportState.value.epoch, epoch);
    expect(data.ftmsControlPointCharacteristic, same(controlPoint));
    expect(data.isTransportActive, isTrue);
    await tester.pump(const Duration(seconds: 8));
    await advanceUntil(tester, () => data.isDirConConnected);
    expect(platform.connectCalls, isEmpty);
    await finish(tester);
  });

  for (final activity in ['workout', 'calibration', 'disconnect']) {
    testWidgets('$activity cancels an in-flight lookup and future checks', (
      tester,
    ) async {
      await fallBack(tester);
      final pending = Completer<DirConEndpoint?>();
      lookup = () => pending.future;
      await tester.pump(const Duration(seconds: 3));
      expect(lookups, 2);
      if (activity == 'workout') {
        data.setWorkoutTargetPower(150);
      } else if (activity == 'calibration') {
        data.beginInteractiveFtmsSession(device);
      } else {
        var done = false;
        final disconnect = data.disconnectPreferred(device)
          ..then((_) => done = true);
        await advanceUntil(tester, () => done);
        await disconnect;
      }
      pending.complete(endpoint);
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      expect(connector.hosts, ['192.168.1.50']);
      expect(lookups, 2);
      expect(data.isDirConConnected, isFalse);
      await finish(tester);
    });
  }

  testWidgets('slow discovery never overlaps another recovery check', (
    tester,
  ) async {
    await fallBack(tester);
    final pending = Completer<DirConEndpoint?>();
    lookup = () => pending.future;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(minutes: 2));
    expect(lookups, 2);
    pending.complete(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(lookups, 2);
    lookup = () async => null;
    await tester.pump(const Duration(seconds: 1));
    expect(lookups, 3);
    await finish(tester);
  });

  testWidgets('network-only device keeps recovering after a long reboot', (
    tester,
  ) async {
    await fallBack(tester, networkOnly: true);
    expect(data.isTransportActive, isFalse);
    for (final seconds in [3, 8, 15, 30, 30]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(lookups, 6);
    expect(platform.connectCalls, isEmpty);
    lookup = () async => endpoint;
    await tester.pump(const Duration(seconds: 30));
    await advanceUntil(tester, () => data.isDirConConnected);
    expect(platform.connectCalls, isEmpty);
    final recoveredLookups = lookups;
    await tester.pump(const Duration(minutes: 2));
    expect(lookups, recoveredLookups);
    await finish(tester);
  });

  testWidgets('disconnect cancels network-only backoff', (tester) async {
    await fallBack(tester, networkOnly: true);
    var done = false;
    final disconnect = data.disconnectPreferred(device)
      ..then((_) => done = true);
    await advanceUntil(tester, () => done);
    await disconnect;
    lookup = () async => endpoint;
    await tester.pump(const Duration(minutes: 5));
    expect(lookups, 1);
    expect(data.isTransportActive, isFalse);
    expect(platform.connectCalls, isEmpty);
    await finish(tester);
  });

  testWidgets('failed BLE fallback still recovers using DIRCON', (
    tester,
  ) async {
    await fallBack(tester, bleUnavailable: true);
    expect(data.isTransportActive, isFalse);
    lookup = () async => endpoint;
    await tester.pump(const Duration(seconds: 3));
    await advanceUntil(tester, () => data.isDirConConnected);
    expect(device.isConnected, isFalse);
    expect(platform.connectCalls, isEmpty, reason: 'no repeated BLE attempts');
    await finish(tester);
  });

  testWidgets('late candidate cannot overwrite an explicit reconnect', (
    tester,
  ) async {
    await fallBack(tester);
    lookup = () async => endpoint;
    final gate = Completer<void>();
    connectionGate = gate;
    await tester.pump(const Duration(seconds: 3));
    expect(connector.issued.length, 2);
    final stale = connector.last;
    var disconnected = false;
    final disconnect = data.disconnectPreferred(device)
      ..then((_) => disconnected = true);
    await advanceUntil(tester, () => disconnected);
    await disconnect;
    var connected = false;
    final reconnect = data.connectPreferred(device)
      ..then((_) => connected = true);
    await advanceUntil(tester, () => connected);
    await reconnect;
    final current = connector.last;
    gate.complete();
    await advanceUntil(tester, () => stale.isClosed);
    expect(data.isDirConConnected, isTrue);
    expect(current.isClosed, isFalse);
    expect(connector.issued.length, 3);
    await finish(tester);
  });

  testWidgets('dispose closes an in-flight candidate and stops retries', (
    tester,
  ) async {
    await fallBack(tester);
    lookup = () async => endpoint;
    final gate = Completer<void>();
    connectionGate = gate;
    await tester.pump(const Duration(seconds: 3));
    final candidate = connector.last;
    data.stopConnectionMonitor();
    data.dispose();
    gate.complete();
    await advanceUntil(tester, () => candidate.isClosed);
    await tester.pump(const Duration(minutes: 2));
    expect(lookups, 2);
  });
}
