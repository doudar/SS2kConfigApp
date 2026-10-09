import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ble_sensor_services.dart';
import 'package:ss2kconfigapp/utils/compatibility/compatibility_checker.dart';
import 'package:ss2kconfigapp/utils/constants.dart';

import 'support/fake_ble_platform.dart';

List<int> le16(int v) => [v & 0xff, (v >> 8) & 0xff];

AdvertisementData advertising(List<String> services, {String name = 'Bike'}) =>
    AdvertisementData(
      advName: name,
      txPowerLevel: null,
      appearance: null,
      connectable: true,
      manufacturerData: const {},
      serviceData: const {},
      serviceUuids: [for (final s in services) Guid(s)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;

  group('classifyCompatibilityCandidate', () {
    test('FTMS wins over an earlier Cycling Power match', () {
      expect(
        classifyCompatibilityCandidate(
          advertising([
            bleCyclingPowerServiceUuid,
            bleFitnessMachineServiceUuid,
          ]),
        ),
        CompatibilityDeviceKind.smartBike,
      );
    });

    test('power meter, Echelon and unverified bikes', () {
      expect(
        classifyCompatibilityCandidate(
          advertising([bleCyclingPowerServiceUuid]),
        ),
        CompatibilityDeviceKind.powerMeter,
      );
      expect(
        classifyCompatibilityCandidate(advertising([bleEchelonServiceUuid])),
        CompatibilityDeviceKind.echelon,
      );
      expect(
        classifyCompatibilityCandidate(
          advertising([blePelotonUartServiceUuid]),
        ),
        CompatibilityDeviceKind.unverified,
      );
    });

    test(
      'Flywheel UART only counts under the exact name the firmware wants',
      () {
        expect(
          classifyCompatibilityCandidate(
            advertising([bleFlywheelUartServiceUuid], name: bleFlywheelName),
          ),
          CompatibilityDeviceKind.unverified,
        );
        expect(
          classifyCompatibilityCandidate(
            advertising([bleFlywheelUartServiceUuid], name: 'Some UART gadget'),
          ),
          isNull,
        );
        expect(
          classifyCompatibilityCandidate(
            advertising([bleFlywheelUartServiceUuid], name: 'flywheel 1'),
          ),
          isNull,
        );
      },
    );

    test(
      'cadence sensors, heart-rate straps and SmartSpin2ks are excluded',
      () {
        expect(
          classifyCompatibilityCandidate(
            advertising([bleCyclingSpeedCadenceServiceUuid]),
          ),
          isNull,
        );
        expect(
          classifyCompatibilityCandidate(
            advertising([bleHeartRateServiceUuid]),
          ),
          isNull,
        );
        expect(
          classifyCompatibilityCandidate(
            advertising([csUUID, bleFitnessMachineServiceUuid]),
          ),
          isNull,
        );
      },
    );
  });

  test('web requests every service the check reads or writes', () {
    final requested = {
      ...compatibilityWebScanServices,
      ...compatibilityWebOptionalServices,
    };
    for (final service in [
      bleCyclingPowerServiceUuid, // data
      bleCyclingSpeedCadenceServiceUuid, // data
      bleEchelonSecondaryServiceUuid, // data and the start command
      ftmsServiceUUID, // data
    ]) {
      expect(requested, contains(Guid(service)), reason: service);
    }
    expect(
      compatibilityWebOptionalServices.toSet(),
      hasLength(compatibilityWebOptionalServices.length),
    );
    expect(
      compatibilityWebOptionalServices.toSet().intersection(
        compatibilityWebScanServices.toSet(),
      ),
      isEmpty,
    );
  });

  group('CompatibilityChecker', () {
    var nextId = 0x10;
    late BluetoothDevice device;
    late CompatibilityChecker checker;

    Future<CompatibilityChecker> start(
      List<FakeGattService> services, {
      Duration listenTimeout = const Duration(seconds: 5),
    }) async {
      await FlutterBluePlus.isSupported;
      platform.reset();
      platform.modelDisconnect = true;
      platform.discoveredServices = services;
      device = BluetoothDevice.fromId(
        '00:00:00:00:01:${(nextId++).toRadixString(16).toUpperCase()}',
      );
      checker = CompatibilityChecker(device, listenTimeout: listenTimeout);
      await checker.run();
      return checker;
    }

    void emit(String service, String characteristic, List<int> value) =>
        platform.emitNotification(
          device.remoteId,
          characteristic,
          value,
          serviceUuid: service,
        );

    Future<CompatibilityCheckState> verdict() async {
      await waitUntil(
        () =>
            checker.state.value.stage == CompatibilityStage.passed ||
            checker.state.value.stage == CompatibilityStage.failed,
      );
      return checker.state.value;
    }

    tearDown(() => checker.dispose());

    final ftms = FakeGattService(ftmsServiceUUID, [
      FakeGattCharacteristic(ftmsIndoorBikeDataUUID),
    ]);

    test('FTMS bike with power and cadence passes and is released', () async {
      await start([ftms]);
      expect(checker.state.value.stage, CompatibilityStage.listening);

      final flags = (1 << 2) | (1 << 6);
      emit(ftmsServiceUUID, ftmsIndoorBikeDataUUID, [
        ...le16(flags),
        ...le16(2000),
        ...le16(170),
        ...le16(160),
      ]);

      final state = await verdict();
      expect(state.stage, CompatibilityStage.passed);
      expect(state.power, 160);
      expect(state.cadence, 85);
      await waitUntil(() => platform.disconnectCalls.contains(device.remoteId));
    });

    test('CPS power with CSC cadence on the same device passes', () async {
      await start([
        const FakeGattService(bleCyclingPowerServiceUuid, [
          FakeGattCharacteristic(bleCyclingPowerMeasurementUuid),
        ]),
        const FakeGattService(bleCyclingSpeedCadenceServiceUuid, [
          FakeGattCharacteristic(bleCscMeasurementUuid),
        ]),
      ]);

      emit(bleCyclingPowerServiceUuid, bleCyclingPowerMeasurementUuid, [
        0,
        0,
        ...le16(150),
      ]);
      emit(bleCyclingSpeedCadenceServiceUuid, bleCscMeasurementUuid, [
        0x02,
        ...le16(10),
        ...le16(1024),
      ]);
      emit(bleCyclingSpeedCadenceServiceUuid, bleCscMeasurementUuid, [
        0x02,
        ...le16(11),
        ...le16(2048),
      ]);

      final state = await verdict();
      expect(state.stage, CompatibilityStage.passed);
      expect(state.cadence, 60);
    });

    test('power meter without crank data fails with noCadence', () async {
      await start([
        const FakeGattService(bleCyclingPowerServiceUuid, [
          FakeGattCharacteristic(bleCyclingPowerMeasurementUuid),
        ]),
      ], listenTimeout: const Duration(milliseconds: 200));

      emit(bleCyclingPowerServiceUuid, bleCyclingPowerMeasurementUuid, [
        0,
        0,
        ...le16(150),
      ]);

      final state = await verdict();
      expect(state.stage, CompatibilityStage.failed);
      expect(state.failure, CompatibilityFailure.noCadence);
      expect(state.powerSeen, isTrue);
    });

    test('out-of-range values do not count', () async {
      await start([ftms], listenTimeout: const Duration(milliseconds: 200));
      final flags = (1 << 2) | (1 << 6);
      emit(ftmsServiceUUID, ftmsIndoorBikeDataUUID, [
        ...le16(flags),
        ...le16(0),
        ...le16(0), // 0 rpm
        ...le16(3500), // above the firmware's 3000 W ceiling
      ]);

      final state = await verdict();
      expect(state.failure, CompatibilityFailure.noData);
    });

    test('connection failure after every attempt', () async {
      await FlutterBluePlus.isSupported;
      platform.reset();
      platform.connectFailure = PlatformException(code: 'connect');
      device = BluetoothDevice.fromId('00:00:00:00:02:01');
      platform.discoveredServices = [ftms];
      checker = CompatibilityChecker(device, retryDelay: Duration.zero);
      await checker.run();
      expect(
        checker.state.value.failure,
        CompatibilityFailure.connectionFailed,
      );
      expect(platform.connectCalls, hasLength(3));
    });

    test(
      'a failed first connection is retried, as the firmware would',
      () async {
        await FlutterBluePlus.isSupported;
        platform.reset();
        platform.modelDisconnect = true;
        platform.connectFailure = PlatformException(code: 'connect');
        device = BluetoothDevice.fromId('00:00:00:00:02:02');
        platform.discoveredServices = [ftms];
        checker = CompatibilityChecker(
          device,
          retryDelay: const Duration(milliseconds: 50),
        );
        final running = checker.run();
        await waitUntil(() => platform.connectCalls.isNotEmpty);
        platform.connectFailure = null;
        await running;

        expect(platform.connectCalls, hasLength(2));
        expect(checker.state.value.stage, CompatibilityStage.listening);
        emit(ftmsServiceUUID, ftmsIndoorBikeDataUUID, [
          0x44, 0x00, // cadence + power, speed present
          ...le16(0),
          ...le16(170), // 85 rpm
          ...le16(200),
        ]);
        expect((await verdict()).stage, CompatibilityStage.passed);
      },
    );

    test('no notifying data characteristic', () async {
      await start([
        FakeGattService(ftmsServiceUUID, [
          FakeGattCharacteristic(ftmsIndoorBikeDataUUID, notify: false),
        ]),
      ]);
      expect(checker.state.value.failure, CompatibilityFailure.noSupportedData);
    });

    test('data that needs pairing', () async {
      await start([
        FakeGattService(ftmsServiceUUID, [
          FakeGattCharacteristic(
            ftmsIndoorBikeDataUUID,
            notifyEncryptionRequired: true,
          ),
        ]),
      ]);
      expect(checker.state.value.failure, CompatibilityFailure.needsPairing);
    });

    group('when enabling notifications fails', () {
      Future<void> startWith(
        List<FakeGattService> services, {
        required String id,
        Duration retryDelay = Duration.zero,
      }) async {
        await FlutterBluePlus.isSupported;
        platform.reset();
        platform.modelDisconnect = true;
        platform.discoveredServices = services;
        device = BluetoothDevice.fromId(id);
        checker = CompatibilityChecker(device, retryDelay: retryDelay);
      }

      test('an authentication error on Android means needsPairing', () async {
        await startWith([ftms], id: '00:00:00:00:04:01');
        platform.failNotify(
          ftmsIndoorBikeDataUUID,
          FlutterBluePlusException(
            ErrorPlatform.android,
            'setNotifyValue',
            5,
            'GATT_INSUFFICIENT_AUTHENTICATION',
          ),
        );
        await checker.run();
        expect(checker.state.value.failure, CompatibilityFailure.needsPairing);
        expect(platform.connectCalls, hasLength(1));
      });

      test('an encryption error on Apple means needsPairing', () async {
        await startWith([ftms], id: '00:00:00:00:04:02');
        platform.failNotify(
          ftmsIndoorBikeDataUUID,
          FlutterBluePlusException(
            ErrorPlatform.apple,
            'setNotifyValue',
            15,
            'insufficient encryption',
          ),
        );
        await checker.run();
        expect(checker.state.value.failure, CompatibilityFailure.needsPairing);
        expect(platform.connectCalls, hasLength(1));
      });

      test('an error on every attempt is a connection failure', () async {
        await startWith([ftms], id: '00:00:00:00:04:03');
        platform.failNotify(ftmsIndoorBikeDataUUID, Exception('boom'));
        await checker.run();
        expect(
          checker.state.value.failure,
          CompatibilityFailure.connectionFailed,
        );
        expect(platform.connectCalls, hasLength(3));
      });

      test('an error on the first attempt only is retried', () async {
        await startWith([ftms], id: '00:00:00:00:04:04');
        platform.failNotify(
          ftmsIndoorBikeDataUUID,
          Exception('boom'),
          times: 1,
        );
        await checker.run();
        expect(platform.connectCalls, hasLength(2));
        expect(checker.state.value.stage, CompatibilityStage.listening);

        emit(ftmsServiceUUID, ftmsIndoorBikeDataUUID, [
          0x44, 0x00, //
          ...le16(0),
          ...le16(170),
          ...le16(200),
        ]);
        expect((await verdict()).stage, CompatibilityStage.passed);
      });

      test('one feed failing is tolerated while the link is up', () async {
        await startWith([
          const FakeGattService(bleCyclingPowerServiceUuid, [
            FakeGattCharacteristic(bleCyclingPowerMeasurementUuid),
          ]),
          ftms,
        ], id: '00:00:00:00:04:05');
        platform.failNotify(bleCyclingPowerMeasurementUuid, Exception('boom'));
        await checker.run();
        expect(checker.state.value.stage, CompatibilityStage.listening);
        expect(platform.connectCalls, hasLength(1));
      });
    });

    test('dispose during a pending connect cancels it and settles', () async {
      await FlutterBluePlus.isSupported;
      platform.reset();
      platform.modelDisconnect = true;
      platform.holdConnects = true;
      platform.discoveredServices = [ftms];
      device = BluetoothDevice.fromId('00:00:00:00:05:01');
      checker = CompatibilityChecker(device, retryDelay: Duration.zero);

      final running = checker.run();
      await waitUntil(() => platform.isConnectHeld(device.remoteId));

      await checker.dispose();
      await running;

      expect(platform.disconnectCalls, contains(device.remoteId));
      final connects = platform.connectCalls.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(platform.connectCalls, hasLength(connects));
      expect(connects, 1);
    });

    test('Echelon is told to start reporting, then passes', () async {
      await start([
        const FakeGattService(bleEchelonSecondaryServiceUuid, [
          FakeGattCharacteristic(bleEchelonWriteUuid, notify: false),
          FakeGattCharacteristic(bleEchelonDataUuid),
        ]),
      ]);

      final handshake = platform.writeCalls.where(
        (call) => call.characteristicUuid == Guid(bleEchelonWriteUuid),
      );
      expect(handshake.single.value, [0xF0, 0xB0, 0x01, 0x01, 0xA2]);

      emit(bleEchelonSecondaryServiceUuid, bleEchelonDataUuid, [
        0xF0, 0xD2, 0, 20, //
      ]);
      emit(bleEchelonSecondaryServiceUuid, bleEchelonDataUuid, [
        0xF0, 0xD1, 0, 0, 0, 0, 0, 0, 0, 0, 85, //
      ]);

      final state = await verdict();
      expect(state.stage, CompatibilityStage.passed);
      expect(state.power, 148);
      expect(state.cadence, 85);
    });

    test('a drop during the test is a connection failure', () async {
      await start([ftms]);
      platform.markDisconnected(device.remoteId);
      final state = await verdict();
      expect(state.failure, CompatibilityFailure.connectionFailed);
    });
  });
}
