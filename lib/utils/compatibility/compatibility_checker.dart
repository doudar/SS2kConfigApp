/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble_sensor_services.dart';
import '../constants.dart';
import 'sensor_decoders.dart';

/// What a nearby device would be to a SmartSpin2k, judged from its
/// advertisement alone.
enum CompatibilityDeviceKind {
  /// Advertises the Fitness Machine Service.
  smartBike,

  /// Advertises the Cycling Power Service.
  powerMeter,

  /// Advertises an Echelon service.
  echelon,

  /// Advertises a service the firmware accepts but this check cannot verify
  /// (Spinner Chrono, Flywheel).
  unverified,
}

/// Classifies a scan result the way the firmware's `getDeviceServiceInfo`
/// would: only advertised services count, and FTMS wins when present (the IC4
/// workaround). Returns null for anything that could not be a SmartSpin2k's
/// power meter — including other SmartSpin2ks, heart-rate straps, remotes and
/// cadence-only sensors.
CompatibilityDeviceKind? classifyCompatibilityCandidate(
  AdvertisementData advertisement,
) {
  final services = advertisement.serviceUuids.toSet();
  bool has(String uuid) => services.contains(Guid(uuid));

  if (has(csUUID)) return null;
  if (has(bleFitnessMachineServiceUuid)) {
    return CompatibilityDeviceKind.smartBike;
  }
  if (has(bleCyclingPowerServiceUuid)) {
    return CompatibilityDeviceKind.powerMeter;
  }
  if (has(bleEchelonServiceUuid) || has(bleEchelonSecondaryServiceUuid)) {
    return CompatibilityDeviceKind.echelon;
  }
  if (has(blePelotonUartServiceUuid)) return CompatibilityDeviceKind.unverified;
  // The firmware only takes the Nordic UART service as a Flywheel bike when it
  // is advertised under this exact name; any other UART device is ignored.
  if (has(bleFlywheelUartServiceUuid) &&
      advertisement.advName == bleFlywheelName) {
    return CompatibilityDeviceKind.unverified;
  }
  return null;
}

enum CompatibilityStage { connecting, listening, passed, failed }

enum CompatibilityFailure {
  /// Could not connect, or the connection dropped during the test.
  connectionFailed,

  /// Connected, but the device has no data characteristic the firmware can
  /// subscribe to.
  noSupportedData,

  /// The device's data is only readable after pairing, which the firmware
  /// never does.
  needsPairing,

  /// Pedalling produced no power and no cadence.
  noData,
  noPower,
  noCadence,
}

@immutable
class CompatibilityCheckState {
  const CompatibilityCheckState({
    this.stage = CompatibilityStage.connecting,
    this.power = 0,
    this.cadence = 0,
    this.powerSeen = false,
    this.cadenceSeen = false,
    this.failure,
  });

  final CompatibilityStage stage;

  /// Latest values that passed the firmware's acceptance range, or 0.
  final int power;
  final int cadence;
  final bool powerSeen;
  final bool cadenceSeen;
  final CompatibilityFailure? failure;

  CompatibilityCheckState copyWith({
    CompatibilityStage? stage,
    int? power,
    int? cadence,
    bool? powerSeen,
    bool? cadenceSeen,
    CompatibilityFailure? failure,
  }) => CompatibilityCheckState(
    stage: stage ?? this.stage,
    power: power ?? this.power,
    cadence: cadence ?? this.cadence,
    powerSeen: powerSeen ?? this.powerSeen,
    cadenceSeen: cadenceSeen ?? this.cadenceSeen,
    failure: failure ?? this.failure,
  );
}

enum _Feed { cyclingPower, csc, echelon, ftms }

/// The service/characteristic pairs the firmware subscribes to on a power
/// meter (`SUPPORTED_SERVICES` in `BLE_Common.cpp`), restricted to the ones
/// this check can decode.
final List<({Guid service, Guid characteristic, _Feed feed})> _dataFeeds = [
  (
    service: Guid(bleCyclingPowerServiceUuid),
    characteristic: Guid(bleCyclingPowerMeasurementUuid),
    feed: _Feed.cyclingPower,
  ),
  (
    service: Guid(bleCyclingSpeedCadenceServiceUuid),
    characteristic: Guid(bleCscMeasurementUuid),
    feed: _Feed.csc,
  ),
  (
    service: Guid(bleEchelonSecondaryServiceUuid),
    characteristic: Guid(bleEchelonDataUuid),
    feed: _Feed.echelon,
  ),
  (
    service: Guid(ftmsServiceUUID),
    characteristic: Guid(ftmsIndoorBikeDataUUID),
    feed: _Feed.ftms,
  ),
];

/// Services a web scan filters on: the ones a bike or power meter advertises.
final List<Guid> compatibilityWebScanServices = [
  Guid(bleFitnessMachineServiceUuid),
  Guid(bleCyclingPowerServiceUuid),
  Guid(bleEchelonServiceUuid),
];

/// Services the check reads or writes after connecting that are not in
/// [compatibilityWebScanServices] (CSC, and the Echelon data/command service).
/// Web Bluetooth only grants access to services named in the scan filters or
/// in `optionalServices`, so these have to be requested up front.
final List<Guid> compatibilityWebOptionalServices = [
  for (final service in {for (final feed in _dataFeeds) feed.service})
    if (!compatibilityWebScanServices.contains(service)) service,
];

/// Connects straight to a bike or power meter and checks it the way a
/// SmartSpin2k would when it is the saved power meter: every data
/// characteristic the firmware uses is subscribed, and the device passes once
/// both power and cadence have arrived within the firmware's accepted ranges.
///
/// Deliberately independent of `DeviceData`, which is built around a
/// SmartSpin2k and would register this device as one.
class CompatibilityChecker {
  CompatibilityChecker(
    this.device, {
    this.connectTimeout = const Duration(seconds: 10),
    this.listenTimeout = const Duration(minutes: 3),
    this.connectAttempts = 3,
    this.retryDelay = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _cyclingPowerCadence = CrankCadenceCalculator(clock: clock),
       _cscCadence = CrankCadenceCalculator(clock: clock);

  final BluetoothDevice device;
  final Duration connectTimeout;

  /// How many times to try connecting and setting up notifications before
  /// giving up. The firmware keeps reconnecting to a saved power meter, so a
  /// single dropped or stalled link on a weak signal says nothing about the
  /// device.
  final int connectAttempts;
  final Duration retryDelay;

  /// How long to wait for pedalling to produce both values. Generous because
  /// the connection is made before the rider is necessarily on the bike.
  final Duration listenTimeout;

  final ValueNotifier<CompatibilityCheckState> state = ValueNotifier(
    const CompatibilityCheckState(),
  );

  static const Duration _notifyEnableTimeout = Duration(seconds: 5);
  static const List<int> _echelonStartCommand = [0xF0, 0xB0, 0x01, 0x01, 0xA2];

  final CrankCadenceCalculator _cyclingPowerCadence;
  final CrankCadenceCalculator _cscCadence;
  final EchelonDecoder _echelon = EchelonDecoder();
  final List<StreamSubscription<List<int>>> _subscriptions = [];
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _listenTimer;
  bool _disposed = false;
  Future<void>? _running;

  bool get _finished =>
      _disposed ||
      state.value.stage == CompatibilityStage.passed ||
      state.value.stage == CompatibilityStage.failed;

  Future<void> run() => _running ??= _run();

  Future<void> _run() async {
    for (var attempt = 1; ; attempt++) {
      if (_disposed) return;
      try {
        await device.connect(
          license: License.nonprofit,
          timeout: connectTimeout,
        );
        // A dispose that landed mid-connect has already released, before this
        // link existed. Release again so the device is not left connected.
        if (_finished) return _release();
        final services = await device.discoverServices();
        if (_finished) return _release();
        await _subscribe(services);
        return;
      } catch (e) {
        debugPrint('[COMPAT] ${device.remoteId} attempt $attempt: $e');
        if (_finished) return;
        if (attempt >= connectAttempts) {
          _fail(CompatibilityFailure.connectionFailed);
          return;
        }
        await _release();
        await Future<void>.delayed(retryDelay);
        if (_finished) return;
      }
    }
  }

  Future<void> _subscribe(List<BluetoothService> services) async {
    var subscribed = 0;
    var needsPairing = false;
    var echelonSubscribed = false;
    Object? subscribeError;

    for (final feed in _dataFeeds) {
      final characteristic = _find(services, feed.service, feed.characteristic);
      if (characteristic == null) continue;
      final properties = characteristic.properties;
      if (!properties.notify && !properties.indicate) continue;
      if (properties.notifyEncryptionRequired ||
          properties.indicateEncryptionRequired) {
        needsPairing = true;
        continue;
      }

      final subscription = characteristic.onValueReceived.listen(
        (value) => _onData(feed.feed, value),
      );
      try {
        await characteristic.setNotifyValue(true).timeout(_notifyEnableTimeout);
      } catch (e) {
        debugPrint('[COMPAT] subscribe ${characteristic.uuid} failed: $e');
        await subscription.cancel();
        if (_isPairingError(e)) {
          needsPairing = true;
        } else {
          subscribeError = e;
        }
        continue;
      }
      if (_finished) {
        await subscription.cancel();
        return _release();
      }
      device.cancelWhenDisconnected(subscription);
      _subscriptions.add(subscription);
      subscribed++;
      if (feed.feed == _Feed.echelon) echelonSubscribed = true;
    }

    if (subscribed == 0) {
      if (needsPairing) {
        _fail(CompatibilityFailure.needsPairing);
        return;
      }
      // A failed subscribe says nothing about the device; let run() retry.
      if (subscribeError != null) throw subscribeError;
      _fail(CompatibilityFailure.noSupportedData);
      return;
    }
    // Carry on with what subscribed (as the firmware does), unless the link
    // went away, in which case the attempt is retried.
    if (subscribeError != null && !device.isConnected) throw subscribeError;

    if (echelonSubscribed) {
      // Echelon bikes stay silent until told to start reporting; the firmware
      // drops a bike that lacks the command characteristic.
      final command = _find(
        services,
        Guid(bleEchelonSecondaryServiceUuid),
        Guid(bleEchelonWriteUuid),
      );
      if (command == null) {
        _fail(CompatibilityFailure.noSupportedData);
        return;
      }
      await command.write(_echelonStartCommand);
      if (_finished) return _release();
    }

    _connectionSubscription = device.connectionState.listen((connection) {
      if (connection == BluetoothConnectionState.disconnected) {
        _fail(CompatibilityFailure.connectionFailed);
      }
    });
    _listenTimer = Timer(listenTimeout, _onListenTimeout);
    _update(state.value.copyWith(stage: CompatibilityStage.listening));
  }

  /// Whether a failed notification enable means the characteristic needs an
  /// encrypted (paired) link. The code is the GATT/ATT status: 5
  /// insufficient authentication, 8 insufficient authorization, 12
  /// insufficient key size, 15 insufficient encryption. Android adds 137
  /// (GATT_AUTH_FAIL); Apple's CBATTError codes mirror ATT.
  static bool _isPairingError(Object error) {
    if (error is! FlutterBluePlusException) return false;
    final code = error.code;
    if (code == null) return false;
    switch (error.platform) {
      case ErrorPlatform.android:
        return code == 5 ||
            code == 8 ||
            code == 12 ||
            code == 15 ||
            code == 137;
      case ErrorPlatform.apple:
        return code == 5 || code == 8 || code == 12 || code == 15;
      default:
        return false;
    }
  }

  static BluetoothCharacteristic? _find(
    List<BluetoothService> services,
    Guid serviceUuid,
    Guid characteristicUuid,
  ) {
    for (final service in services) {
      if (service.uuid != serviceUuid) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == characteristicUuid) return characteristic;
      }
    }
    return null;
  }

  void _onData(_Feed feed, List<int> value) {
    if (_finished) return;
    switch (feed) {
      case _Feed.cyclingPower:
        final measurement = decodeCyclingPowerMeasurement(value);
        if (measurement == null) return;
        _acceptPower(measurement.power);
        final crank = measurement.crank;
        if (crank != null) {
          _acceptCadence(_cyclingPowerCadence.add(crank));
        }
      case _Feed.csc:
        final crank = decodeCscCrankRevolutions(value);
        if (crank != null) _acceptCadence(_cscCadence.add(crank));
      case _Feed.echelon:
        _echelon.decode(value);
        final power = _echelon.power;
        final cadence = _echelon.cadence;
        if (power != null) _acceptPower(power);
        if (cadence != null) _acceptCadence(cadence.toDouble());
      case _Feed.ftms:
        final sample = decodeIndoorBikeData(value);
        if (sample == null) return;
        if (sample.power != null) _acceptPower(sample.power!);
        if (sample.cadence != null) {
          _acceptCadence(sample.cadence!.toDouble());
        }
    }
    final current = state.value;
    if (current.powerSeen && current.cadenceSeen) {
      _finish(current.copyWith(stage: CompatibilityStage.passed));
    }
  }

  // Acceptance ranges from the firmware's SensorCollector.
  void _acceptPower(int watts) {
    final accepted = watts > 0 && watts < 3000;
    _update(
      state.value.copyWith(
        power: accepted ? watts : 0,
        powerSeen: state.value.powerSeen || accepted,
      ),
    );
  }

  void _acceptCadence(double rpm) {
    final rounded = rpm.round();
    final accepted = rounded > 0 && rounded < 250;
    _update(
      state.value.copyWith(
        cadence: accepted ? rounded : 0,
        cadenceSeen: state.value.cadenceSeen || accepted,
      ),
    );
  }

  void _onListenTimeout() {
    final current = state.value;
    _fail(
      current.powerSeen
          ? CompatibilityFailure.noCadence
          : current.cadenceSeen
          ? CompatibilityFailure.noPower
          : CompatibilityFailure.noData,
    );
  }

  void _fail(CompatibilityFailure failure) {
    if (_finished) return;
    _finish(
      state.value.copyWith(stage: CompatibilityStage.failed, failure: failure),
    );
  }

  /// Records the verdict and lets go of the device so the user's other apps,
  /// or a SmartSpin2k, can connect to it straight away.
  void _finish(CompatibilityCheckState verdict) {
    _update(verdict);
    unawaited(_release());
  }

  void _update(CompatibilityCheckState next) {
    if (!_disposed) state.value = next;
  }

  /// Safe to run concurrently (a verdict and a dispose can overlap): each
  /// resource is taken before the first await.
  Future<void> _release({bool queue = true}) async {
    _listenTimer?.cancel();
    _listenTimer = null;
    final connection = _connectionSubscription;
    _connectionSubscription = null;
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    await connection?.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    try {
      await device.disconnect(queue: queue);
    } catch (e) {
      debugPrint('[COMPAT] disconnect ${device.remoteId}: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Skip the operation queue so an in-flight connect is cancelled rather
    // than waited out, then wait for run() so the device is never touched
    // again once this returns.
    await _release(queue: false);
    final running = _running;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    state.dispose();
  }
}
