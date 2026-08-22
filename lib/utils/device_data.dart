/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'extra.dart';
import 'bleConstants.dart';
import 'ble_connection_retry.dart';
import 'ble_request_coalescer.dart';
import 'bleOTA.dart';
import 'connection_setup_coordinator.dart';
import 'device_transport_state.dart';
import 'dircon_client.dart';
import 'smartspin_advertisement.dart';
import 'workout_control_lane.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/snackbar.dart';

/// Event model for characteristic changes
class CharacteristicChangeEvent {
  final String vName;
  final String reference;
  final String value;
  final String type;

  CharacteristicChangeEvent({
    required this.vName,
    required this.reference,
    required this.value,
    required this.type,
  });
}

class _DirConRecoveryAdvertisementSession {
  _DirConRecoveryAdvertisementSession(this.device);

  final BluetoothDevice device;
  final Completer<SmartSpinAdvertisementData> _firstAdvertisement =
      Completer<SmartSpinAdvertisementData>();
  final StreamController<SmartSpinAdvertisementData> _updates =
      StreamController<SmartSpinAdvertisementData>.broadcast();
  StreamSubscription<List<ScanResult>>? _subscription;
  SmartSpinAdvertisementData? latest;
  bool _startedScan = false;
  bool _disposed = false;

  Future<void> start(Duration scanTimeout) async {
    _subscription = FlutterBluePlus.onScanResults.listen(
      _handleResults,
      onError: (Object error, StackTrace stackTrace) {
        if (!_firstAdvertisement.isCompleted) {
          _firstAdvertisement.completeError(error, stackTrace);
        }
        if (!_updates.isClosed) _updates.addError(error, stackTrace);
      },
    );

    _startedScan = !FlutterBluePlus.isScanningNow;
    if (_startedScan) {
      await FlutterBluePlus.startScan(
        withRemoteIds: [device.remoteId.str],
        timeout: scanTimeout,
        continuousUpdates: true,
        continuousDivisor: 1,
        oneByOne: true,
      );
    }
  }

  void _handleResults(List<ScanResult> results) {
    for (final result in results) {
      if (result.device.remoteId != device.remoteId) continue;
      final advertisement = SmartSpinAdvertisement.parse(
        result.advertisementData.manufacturerData,
      );
      if (advertisement == null) continue;

      latest = advertisement;
      if (!_firstAdvertisement.isCompleted) {
        _firstAdvertisement.complete(advertisement);
      }
      if (!_updates.isClosed) _updates.add(advertisement);
    }
  }

  Future<SmartSpinAdvertisementData> waitForFirst(Duration timeout) {
    return _firstAdvertisement.future.timeout(timeout);
  }

  Future<SmartSpinAdvertisementData> waitForAddressChange(
    String currentAddress,
    Duration timeout,
  ) async {
    final current = latest;
    if (current != null && current.ipAddress != currentAddress) return current;
    try {
      return await _updates.stream
          .firstWhere((update) => update.ipAddress != currentAddress)
          .timeout(timeout);
    } on TimeoutException {
      return latest!;
    }
  }

  Future<SmartSpinAdvertisementData> waitForUsableAddress(
    Duration timeout,
  ) async {
    final current = latest;
    if (current?.ipAddress != null) return current!;
    try {
      return await _updates.stream
          .firstWhere((update) => update.ipAddress != null)
          .timeout(timeout);
    } on TimeoutException {
      return latest!;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    if (!_updates.isClosed) await _updates.close();
    if (_startedScan && FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }
}

class DeviceDataManager {
  static final Map<String, DeviceData> _dataMap = {};

  static DeviceData forDevice(BluetoothDevice device) {
    if (!_dataMap.containsKey(device.remoteId.str)) {
      _dataMap[device.remoteId.str] = DeviceData();
    }
    return _dataMap[device.remoteId.str]!;
  }

  static void updateDataForDevice(BluetoothDevice device, DeviceData data) {
    _dataMap[device.remoteId.str] = data;
  }

  static void clearDataForDevice(BluetoothDevice device) {
    _dataMap.remove(device.remoteId.str);
  }
}

class FtmsData {
  late int cadence;
  late int watts;
  late int _targetERG;
  late int resistance;
  late int mode;
  late int heartRate;
  late int speed;

  int get targetERG => _targetERG;

  FtmsData({
    this.cadence = 0,
    this.watts = 0,
    int targetERG = 0,
    this.mode = 0, // 0 = no control, 1 = sim, 2 = ERG.
    this.resistance = 0,
    this.heartRate = 0,
    this.speed = 0,
  }) : _targetERG = targetERG;
}

class DeviceData {
  DeviceData() {
    _workoutControlLane = WorkoutControlLane(
      transportState: () => _transportStateController.value,
      isReady: _isWorkoutControlReady,
      dispatch: _dispatchWorkoutControlBatch,
    );
    _transportStateController.addListener(_handleTransportStateChanged);
  }

  String? advertisedIpAddress;
  DirConClient? _dirConClient;
  StreamSubscription<List<int>>? _dirConNotificationSubscription;
  StreamSubscription<List<int>>? _dirConFtmsSubscription;
  StreamSubscription<void>? _dirConDisconnectedSubscription;
  bool _dirConSetupComplete = false;
  bool _dirConReconnectInProgress = false;
  bool _initialConnectionInProgress = false;
  bool _workoutControlActive = false;
  int _ftmsSubscriptionBlocks = 0;
  int _ftmsBlockGeneration = 0;
  Timer? _ftmsPostConnectionTimer;
  bool _ftmsPostConnectionBlockActive = false;

  final DeviceTransportStateController _transportStateController =
      DeviceTransportStateController();
  late final WorkoutControlLane _workoutControlLane;
  bool _isDisposed = false;

  ValueListenable<DeviceTransportState> get transportState =>
      _transportStateController;
  bool get isDirConConnected =>
      _transportStateController.value.transport == DeviceTransportKind.dircon &&
      _transportStateController.value.phase == DeviceTransportPhase.connected;
  bool get isTransportActive =>
      _transportStateController.value.phase == DeviceTransportPhase.connected;
  bool get isFtmsSubscriptionBlocked => _ftmsSubscriptionBlocks > 0;
  String get activeTransportName =>
      switch (_transportStateController.value.transport) {
        DeviceTransportKind.dircon => 'DIRCON',
        DeviceTransportKind.bluetooth => 'Bluetooth',
        DeviceTransportKind.none => 'None',
      };

  bool isUserDisconnect = false;
  ValueNotifier<int> rssi = ValueNotifier(0);
  // DIRCON state changes do not emit a Bluetooth connection-state event.
  // Headers listen to this revision so their transport indicator stays fresh.
  final ValueNotifier<int> transportRevision = ValueNotifier(0);
  ValueNotifier<bool> charReceived = ValueNotifier(false);
  DateTime? lastFtmsUpdate;
  StreamSubscription<BluetoothConnectionState>? connectionStateSubscription;
  StreamSubscription<bool>? isConnectingSubscription;
  StreamSubscription<bool>? isDisconnectingSubscription;

  // Centralized auto-reconnect monitor
  StreamSubscription<BluetoothConnectionState>? _reconnectSubscription;
  bool _reconnecting = false;
  bool _reconnectRequested = false;
  Completer<bool>? _reconnectCompleter;
  int _connectionMonitorUsers = 0;
  final List<Future<void> Function()> _onReconnectedCallbacks = [];

  /// Start monitoring the connection and automatically reconnect on unexpected
  /// disconnects.  Safe to call multiple times – only one listener is created.
  /// [onReconnected] is an optional callback invoked after a successful
  /// reconnect so the caller can refresh services / UI.
  void startConnectionMonitor(
    BluetoothDevice device, {
    Future<void> Function()? onReconnected,
  }) {
    _connectionMonitorUsers++;
    if (onReconnected != null &&
        !_onReconnectedCallbacks.contains(onReconnected)) {
      _onReconnectedCallbacks.add(onReconnected);
    }

    // Guard against duplicate subscriptions
    if (_reconnectSubscription != null) return;

    _reconnectSubscription = device.connectionState.listen((state) async {
      // A DIRCON session deliberately leaves the Android BLE GATT connection
      // disconnected. Do not let that idle BLE state overwrite the active
      // network transport or start a competing reconnect loop.
      if (isDirConConnected) return;

      if (state == BluetoothConnectionState.connected) {
        _markTransportConnected(DeviceTransportKind.bluetooth, device);
        return;
      }

      if (state == BluetoothConnectionState.disconnected) {
        if (isUserDisconnect) {
          _markTransportDisconnected(explicit: true);
          return;
        }
        if (_initialConnectionInProgress) return;

        _markTransportReconnecting(DeviceTransportKind.bluetooth);

        // Reset connection-specific state so the next setupConnection
        // performs a full re-bootstrap (re-discover services, re-subscribe
        // to notifications, etc.).  Without this, stale references to the
        // old connection's characteristics remain and no data flows after
        // reconnection.
        _resetConnectionState();

        await reconnectAndSetup(device);
      }
    });
  }

  /// Connect using the IP advertised by SmartSpin2k whenever its DIRCON
  /// endpoint is reachable. BLE remains the transparent fallback.
  Future<void> connectPreferred(
    BluetoothDevice device, {
    bool waitForSetup = false,
  }) async {
    isUserDisconnect = false;
    _initialConnectionInProgress = true;
    try {
      final ipAddress = advertisedIpAddress;
      if (ipAddress != null && ipAddress.isNotEmpty) {
        _markTransportConnecting(DeviceTransportKind.dircon);
        try {
          await _connectDirCon(device, ipAddress, waitForSetup: waitForSetup);
          return;
        } catch (error) {
          print('[DIRCON] $ipAddress unavailable, falling back to BLE: $error');
          await _closeDirCon();
        }
      }

      _markTransportConnecting(DeviceTransportKind.bluetooth);
      final connected = await retryBleConnection(
        connect: device.connectAndUpdateStream,
        isConnected: () => device.isConnected,
        isCancelled: () => isUserDisconnect,
        onAttemptFailed: (attempt, error) {
          print('[BLE] Initial connection attempt $attempt/10 failed: $error');
        },
      );
      if (!connected) return;
      _markTransportConnected(DeviceTransportKind.bluetooth, device);
      if (waitForSetup) {
        await setupConnection(device);
      } else {
        _setupConnectionInBackground(device);
      }
    } catch (_) {
      // A failed bootstrap is not a dead link. Only report the transport down
      // when the physical session was never established; otherwise setup threw
      // over a live connection and nothing would ever re-mark it as connected.
      if (_transportStateController.value.phase !=
          DeviceTransportPhase.connected) {
        _markTransportDisconnected(explicit: false);
      }
      rethrow;
    } finally {
      _initialConnectionInProgress = false;
    }
  }

  Future<void> disconnectPreferred(BluetoothDevice device) async {
    isUserDisconnect = true;
    _markTransportDisconnected(explicit: true);
    if (_dirConClient != null) {
      await _closeDirCon();
      _resetConnectionState();
      return;
    }
    await device.disconnect();
  }

  Future<void> _connectDirCon(
    BluetoothDevice device,
    String ipAddress, {
    required bool waitForSetup,
  }) async {
    await _closeDirCon();
    final client = await DirConClient.connect(ipAddress);
    try {
      await client.initialize(serviceUuid: csUUID, characteristicUuid: ccUUID);
    } catch (_) {
      await client.close();
      rethrow;
    }

    _dirConClient = client;
    _dirConSetupComplete = false;
    configAppCompatibleFirmware = true;
    _ensureCachedMap();
    _markTransportConnected(DeviceTransportKind.dircon, device);
    _dirConNotificationSubscription = client
        .characteristicNotifications(ccUUID)
        .listen(_decodeCustomValue);
    try {
      await client.ensureCharacteristic(
        serviceUuid: ftmsServiceUUID,
        characteristicUuid: ftmsIndoorBikeDataUUID,
        enableNotifications: !isFtmsSubscriptionBlocked,
      );
      if (!isFtmsSubscriptionBlocked) {
        _dirConFtmsSubscription = client
            .characteristicNotifications(ftmsIndoorBikeDataUUID)
            .listen(_decodeIndoorBikeData);
        print('[DIRCON] Subscribed to FTMS Indoor Bike Data');
      }
    } catch (error) {
      // Configuration remains usable on firmware variants without FTMS.
      print('[DIRCON] FTMS subscription unavailable: $error');
    }
    _dirConDisconnectedSubscription = client.disconnected.listen((_) {
      _handleDirConDisconnect(device);
    });
    print('[DIRCON] Connected to $ipAddress:${DirConClient.port}');
    if (waitForSetup) {
      await setupConnection(device);
    } else {
      _setupConnectionInBackground(device);
    }
  }

  void _setupConnectionInBackground(BluetoothDevice device) {
    unawaited(
      setupConnection(device).catchError((Object error, StackTrace stackTrace) {
        print('[ConnectionSetup] Background setup failed: $error');
      }),
    );
  }

  Future<void> _handleDirConDisconnect(BluetoothDevice device) async {
    final disconnectedAddress = _dirConClient?.host;
    if (disconnectedAddress == null) return;
    _markTransportReconnecting(DeviceTransportKind.dircon);
    await _closeDirCon();
    _dirConSetupComplete = false;
    subscribed = false;
    charReceived.value = false;
    if (isUserDisconnect || _dirConReconnectInProgress) return;

    _dirConReconnectInProgress = true;
    try {
      print(
        '[DIRCON][FALLBACK] start reason=disconnect host=$disconnectedAddress',
      );
      await _connectBleAfterDirConLoss(device);
    } catch (error) {
      print('[DIRCON][FALLBACK] failed: $error');
    } finally {
      _dirConReconnectInProgress = false;
    }
  }

  Future<void> _connectBleAfterDirConLoss(BluetoothDevice device) async {
    _markTransportConnecting(DeviceTransportKind.bluetooth);
    final stopwatch = Stopwatch()..start();
    if (device.isConnected) {
      print('[DIRCON][FALLBACK] reusing connected BLE GATT session');
    } else {
      print('[DIRCON][FALLBACK] connecting BLE GATT session');
      await device.connectAndUpdateStream().timeout(
        const Duration(seconds: 10),
      );
    }
    _resetConnectionState();
    await setupConnection(
      device,
      markTransportConnected: false,
    ).timeout(const Duration(seconds: 10));
    if (ftmsControlPointCharacteristic == null || !device.isConnected) {
      throw StateError('BLE FTMS Control Point is not ready after DIRCON loss');
    }
    _markTransportConnected(DeviceTransportKind.bluetooth, device);
    print(
      '[DIRCON][FALLBACK] BLE ready epoch=${_transportStateController.value.epoch} '
      'duration=${stopwatch.elapsedMilliseconds}ms; redelivering target.',
    );
    await _runReconnectedCallbacks();
  }

  Future<void> _runReconnectedCallbacks() async {
    for (final callback in List<Future<void> Function()>.from(
      _onReconnectedCallbacks,
    )) {
      await callback();
    }
  }

  Future<void> _refreshAdvertisedEndpointForReconnect(
    BluetoothDevice device,
  ) async {
    final previousAddress = advertisedIpAddress;
    final session = _DirConRecoveryAdvertisementSession(device);
    try {
      await session.start(const Duration(seconds: 30));
      var advertisement = await session.waitForFirst(
        const Duration(seconds: 30),
      );

      // When WiFi was previously unavailable, DHCP may complete shortly after
      // the first post-boot advertisement. Keep observing briefly so a BLE
      // connection can be promoted to the newly available DIRCON endpoint.
      if (previousAddress == null && advertisement.ipAddress == null) {
        advertisement = await session.waitForUsableAddress(
          const Duration(seconds: 15),
        );
      }

      advertisedIpAddress = advertisement.ipAddress;
      if (advertisedIpAddress == null) {
        print('[AutoReconnect] Fresh advertisement has no usable WiFi IP.');
      } else if (advertisedIpAddress != previousAddress) {
        print(
          '[AutoReconnect] Advertised IP updated from '
          '${previousAddress ?? 'none'} to $advertisedIpAddress.',
        );
      } else {
        print(
          '[AutoReconnect] Fresh advertisement confirms IP '
          '$advertisedIpAddress.',
        );
      }
    } finally {
      await session.dispose();
    }
  }

  Future<void> _closeDirCon() async {
    final client = _dirConClient;
    _dirConClient = null;
    // Tearing down a live session is itself a transport transition. Callers
    // that already moved to connecting/reconnecting/disconnected are unaffected
    // by this guard, so no spurious disconnected phase is emitted mid-reconnect.
    if (client != null &&
        _transportStateController.value.transport ==
            DeviceTransportKind.dircon &&
        _transportStateController.value.phase ==
            DeviceTransportPhase.connected) {
      _markTransportDisconnected(explicit: isUserDisconnect);
    }
    _workoutControlLane.onAvailabilityChanged();
    await _dirConNotificationSubscription?.cancel();
    _dirConNotificationSubscription = null;
    await _dirConFtmsSubscription?.cancel();
    _dirConFtmsSubscription = null;
    await _dirConDisconnectedSubscription?.cancel();
    _dirConDisconnectedSubscription = null;
    if (client != null) await client.close();
  }

  // A DIRCON disconnect can land after dispose() has torn down the notifier,
  // so every transition is gated on the same disposal flag.
  void _markTransportConnecting(DeviceTransportKind transport) {
    if (_isDisposed) return;
    _transportStateController.markConnecting(transport);
  }

  void _markTransportReconnecting(DeviceTransportKind transport) {
    if (_isDisposed) return;
    _transportStateController.markReconnecting(transport);
  }

  void _markTransportConnected(
    DeviceTransportKind transport,
    BluetoothDevice device,
  ) {
    if (_isDisposed) return;
    final wasAlreadyConnected =
        _transportStateController.value.transport == transport &&
        _transportStateController.value.phase == DeviceTransportPhase.connected;
    _transportStateController.markConnected(transport);
    if (!wasAlreadyConnected) {
      _startFtmsPostConnectionBlock(device);
    }
  }

  void _startFtmsPostConnectionBlock(BluetoothDevice device) {
    _ftmsPostConnectionTimer?.cancel();
    if (!_ftmsPostConnectionBlockActive) {
      _ftmsPostConnectionBlockActive = true;
      unawaited(blockFtmsSubscription());
    }
    _ftmsPostConnectionTimer = Timer(const Duration(seconds: 10), () {
      _ftmsPostConnectionTimer = null;
      _ftmsPostConnectionBlockActive = false;
      unawaited(unblockFtmsSubscription(device));
    });
  }

  void _markTransportDisconnected({required bool explicit}) {
    if (_isDisposed) return;
    _transportStateController.markDisconnected(explicit: explicit);
  }

  void _handleTransportStateChanged() {
    connectionState = isTransportActive
        ? BluetoothConnectionState.connected
        : BluetoothConnectionState.disconnected;
    transportRevision.value++;
    _workoutControlLane.onAvailabilityChanged();
  }

  /// Reconnect and rebuild all connection-scoped BLE state so all recovery
  /// paths behave the same way after a reboot or dropped link.
  Future<bool> reconnectAndSetup(
    BluetoothDevice device, {
    int maxAttempts = 10,
    Duration retryDelay = const Duration(seconds: 1),
    Duration settleDelay = const Duration(milliseconds: 750),
    Future<void> Function()? onReconnected,
  }) async {
    if (isUserDisconnect) return false;

    if (_reconnecting) {
      _reconnectRequested = true;
      return await _reconnectCompleter?.future ?? device.isConnected;
    }

    _reconnecting = true;
    _markTransportReconnecting(_transportStateController.value.transport);
    _reconnectRequested = false;
    _reconnectCompleter = Completer<bool>();

    bool success = false;
    try {
      final keepWorkoutOnBle =
          _workoutControlActive &&
          _transportStateController.value.transport ==
              DeviceTransportKind.bluetooth;
      if (!keepWorkoutOnBle) {
        try {
          await _refreshAdvertisedEndpointForReconnect(device);
        } catch (error) {
          // Do not keep probing a cached network endpoint after a reboot when no
          // fresh advertisement could confirm it. BLE remains the safe fallback.
          advertisedIpAddress = null;
          print(
            '[AutoReconnect] Fresh advertisement unavailable; '
            'using BLE fallback: $error',
          );
        }
      } else {
        print(
          '[WorkoutTransport] keeping active workout on BLE; DIRCON promotion deferred.',
        );
      }

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        if (isUserDisconnect) break;

        _resetConnectionState();

        try {
          // Reconnection is transport-agnostic: a device that was previously
          // using BLE may have DIRCON available by the time it returns. Probe
          // the advertised endpoint before recreating a BLE GATT connection.
          final ipAddress = keepWorkoutOnBle ? null : advertisedIpAddress;
          if (ipAddress != null && ipAddress.isNotEmpty) {
            try {
              print(
                '[AutoReconnect] Attempt $attempt/$maxAttempts testing DIRCON...',
              );
              await _connectDirCon(device, ipAddress, waitForSetup: true);

              if (onReconnected != null) {
                await onReconnected();
              } else {
                for (final callback in List<Future<void> Function()>.from(
                  _onReconnectedCallbacks,
                )) {
                  await callback();
                }
              }

              success = true;
              print('[AutoReconnect] Reconnected via DIRCON successfully.');
              break;
            } catch (error) {
              print('[AutoReconnect] DIRCON unavailable: $error');
              await _closeDirCon();
            }
          }

          if (!device.isConnected) {
            print(
              '[AutoReconnect] Attempt $attempt/$maxAttempts connecting...',
            );
            await device.connectAndUpdateStream();
          }

          _markTransportConnected(DeviceTransportKind.bluetooth, device);

          await Future.delayed(settleDelay);

          if (!device.isConnected) {
            throw Exception(
              'Device disconnected during reconnect settle period.',
            );
          }

          // This attempt already reset all connection-scoped state. Join the
          // shared bootstrap instead of forcing a second service discovery.
          await setupConnection(device);

          if (!device.isConnected) {
            throw Exception('Device disconnected during setup.');
          }

          if (onReconnected != null) {
            await onReconnected();
          } else {
            for (final callback in List<Future<void> Function()>.from(
              _onReconnectedCallbacks,
            )) {
              await callback();
            }
          }

          success = true;
          print('[AutoReconnect] Reconnected successfully.');
          break;
        } catch (e) {
          print('[AutoReconnect] Reconnect attempt $attempt failed: $e');
          if (attempt < maxAttempts) {
            await Future.delayed(retryDelay);
          }
        }
      }
    } finally {
      _reconnecting = false;
      _reconnectCompleter?.complete(success);
      _reconnectCompleter = null;
    }

    if (!success && _reconnectRequested && !isUserDisconnect) {
      _reconnectRequested = false;
      return reconnectAndSetup(
        device,
        maxAttempts: maxAttempts,
        retryDelay: retryDelay,
        settleDelay: settleDelay,
        onReconnected: onReconnected,
      );
    }

    return success;
  }

  /// Reset BLE state that is tied to a specific connection so that the next
  /// [setupConnection] call performs a full re-bootstrap.
  void _resetConnectionState() {
    _setupCoordinator.invalidate();
    final pendingResponse = _pendingCustomResponse;
    if (pendingResponse != null && !pendingResponse.isCompleted) {
      // Release the serialized BLE queue immediately. The next operation will
      // observe the disconnected device instead of waiting for the timeout.
      pendingResponse.complete();
    }
    _pendingCustomResponse = null;
    _pendingCustomResponseReference = null;
    _customReadRequestCoalescer.clear();
    subscribed = false;
    charReceived.value = false;
    _myCharacteristic = null;
    indoorBikeCharacteristic = null;
    ftmsControlPointCharacteristic = null;
    machineStatusCharacteristic = null;
    services = [];
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _ftmsSubscription?.cancel();
    _ftmsSubscription = null;
    _machineStatusSubscription?.cancel();
    _machineStatusSubscription = null;
    _inUpdateLoop = false;
    _lastRequestStopwatch.reset();
    _cachedCharacteristicMap = null;
    lastFtmsUpdate = null;
    _ftmsRecoveryInProgress = false;
    _lastFtmsRecoveryAttempt = null;
    // The control point this target was delivered through is gone, so the
    // rebuilt session must receive it again even on an unchanged epoch.
    _workoutControlLane.invalidateDelivery();
  }

  /// Stop the auto-reconnect monitor.
  void stopConnectionMonitor({Future<void> Function()? onReconnected}) {
    if (onReconnected != null) {
      _onReconnectedCallbacks.remove(onReconnected);
    }

    if (_connectionMonitorUsers > 0) {
      _connectionMonitorUsers--;
    }

    if (_connectionMonitorUsers > 0) return;

    _reconnectSubscription?.cancel();
    _reconnectSubscription = null;
    _onReconnectedCallbacks.clear();
  }

  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<List<int>>? _ftmsSubscription;
  BluetoothService? _firmwareService;
  BluetoothCharacteristic? _firmwareDataCharacteristic;
  BluetoothCharacteristic? _firmwareControlCharacteristic;

  /// Creates the firmware writer supported by the active transport, or null
  /// when that transport only supports HTTP OTA. Screens should not inspect
  /// transport-specific characteristic state themselves.
  OtaPackage? createFirmwareOtaPackage() {
    final data = _firmwareDataCharacteristic;
    final control = _firmwareControlCharacteristic;
    if (_firmwareService == null || data == null || control == null)
      return null;
    return Esp32OtaPackage(data, control);
  }

  /// Runs a package created by [createFirmwareOtaPackage] without exposing the
  /// underlying BLE service or characteristics to UI code.
  Future<void> updateFirmwareWithPackage(
    OtaPackage package,
    BluetoothDevice device,
    int firmwareType, {
    required String binFilePath,
  }) async {
    final service = _firmwareService;
    final data = _firmwareDataCharacteristic;
    final control = _firmwareControlCharacteristic;
    if (service == null || data == null || control == null) {
      throw StateError(
        'The active transport does not provide a characteristic-based firmware update.',
      );
    }
    await package.updateFirmware(
      device,
      firmwareType,
      service,
      data,
      control,
      binFilePath: binFilePath,
    );
  }

  BluetoothCharacteristic? _myCharacteristic;
  BluetoothCharacteristic? ftmsControlPointCharacteristic;
  BluetoothCharacteristic? indoorBikeCharacteristic;
  BluetoothCharacteristic? machineStatusCharacteristic;
  StreamSubscription<List<int>>? _machineStatusSubscription;
  Completer<void>? _discoverServicesCompleter;
  final ConnectionSetupCoordinator _setupCoordinator =
      ConnectionSetupCoordinator();
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];
  FtmsData ftmsData = FtmsData();
  bool isSimulated = false; //Is this a demo device?
  bool isConnecting = false;
  bool isDisconnecting = false;
  bool configAppCompatibleFirmware = false;
  ValueNotifier<String> firmwareVersion = ValueNotifier("");

  // Create a broadcast stream controller for logs
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logStreamController.stream;

  // Raw FTMS Fitness Machine Status (0x2ADA) notifications. The SmartSpin2k
  // reports homing progress here, and unlike the log stream these cannot be
  // dropped by a full firmware log buffer.
  final StreamController<List<int>> _machineStatusController =
      StreamController<List<int>>.broadcast();
  Stream<List<int>> get machineStatusStream => _machineStatusController.stream;

  String simulatedTargetWatts = "";
  String simulatedFTMSmode = "";
  int FTMSmode = 0;
  bool simulateTargetWatts = false;
  double tableDivisor = 10.0; // Default divisor for power table data

  // Stream controller for characteristic changes
  final StreamController<CharacteristicChangeEvent>
  _characteristicChangeController =
      StreamController<CharacteristicChangeEvent>.broadcast();

  // Transport-neutral live bike data. Both BLE and DIRCON notifications are
  // decoded by _decodeIndoorBikeData, so screens should listen here instead of
  // depending on a transport-specific characteristic notification.
  final StreamController<FtmsData> _ftmsDataController =
      StreamController<FtmsData>.broadcast();

  /// Stream of characteristic changes
  Stream<CharacteristicChangeEvent> get characteristicChanges =>
      _characteristicChangeController.stream;

  Stream<FtmsData> get ftmsDataChanges => _ftmsDataController.stream;

  List<List<int?>> powerTableData = List.generate(
    10,
    (i) => List.generate(38, (j) => null),
  );
  bool isPowerTableTransferInProgress = false;

  var customCharacteristic = createCustomCharacteristicFramework();

  Map<int, Map>? _cachedCharacteristicMap;

  void _ensureCachedMap() {
    if (_cachedCharacteristicMap == null) {
      _cachedCharacteristicMap = {};
      for (var c in this.customCharacteristic) {
        try {
          _cachedCharacteristicMap![int.parse(c["reference"])] = c;
        } catch (e) {
          print("Error parsing characteristic reference: $e");
        }
      }
    }
  }

  /// Seeds this DeviceData as a simulated ("demo") device: marks it simulated,
  /// fills every custom characteristic with its default value, and reports a
  /// compatible firmware version. Used by both the main device screen and the
  /// onboarding wizard so the demo device behaves identically in either entry
  /// point. This is also the intended hook for a future demo data emitter.
  void setupDemoData() {
    isSimulated = true;
    for (final key in customCharacteristic) {
      key["value"] = key["defaultData"] ?? "Default Value";
    }
    charReceived.value = true;
    firmwareVersion.value = "24.1.3";
    configAppCompatibleFirmware = true;
  }

  /// @brief
  /// Returns the value of a custom characteristic by its vName.
  /// If the value is not found or is [noFirmSupport] and [returnNoFirmSupport] is false, returns "0".
  String getVnameValue(String vName, {bool returnNoFirmSupport = false}) {
    var characteristic = customCharacteristic.firstWhere(
      (c) => c["vName"] == vName,
      orElse: () => {"value": "0"},
    );
    var value = characteristic["value"].toString();
    if (!returnNoFirmSupport && value == noFirmSupport) {
      return "0";
    }
    return value;
  }

  String preferredDeviceName(String advertisedName) {
    final configuredName = getVnameValue(
      deviceNameVname,
      returnNoFirmSupport: true,
    ).trim();
    if (configuredName.isNotEmpty &&
        configuredName != '0' &&
        configuredName != 'null' &&
        configuredName != noFirmSupport) {
      return configuredName;
    }
    return advertisedName.trim();
  }

  Future<void> setupConnection(
    BluetoothDevice device, {
    bool forceRefresh = false,
    bool markTransportConnected = true,
  }) {
    if (isSimulated) return Future.value();

    if (isDirConConnected) {
      final setupInProgress = _setupCoordinator.inFlight;
      if (setupInProgress != null) return setupInProgress;
      if (_dirConSetupComplete && !forceRefresh) return Future.value();
      return _setupCoordinator.run((generation) async {
        if (!_setupCoordinator.isCurrent(generation) || !isDirConConnected) {
          return;
        }
        subscribed = true;
        charReceived.value = true;
        configAppCompatibleFirmware = true;
        // BLE initializes this lookup from decode(). DIRCON responses are
        // delivered directly, so initialize it before the first settings
        // request or every valid response will be ignored as an unknown
        // characteristic reference.
        _ensureCachedMap();
        _lastRequestStopwatch.reset();
        await requestSettings(device);
        if (_setupCoordinator.isCurrent(generation) && isDirConConnected) {
          _dirConSetupComplete = true;
          if (!_lastRequestStopwatch.isRunning) {
            _lastRequestStopwatch.start();
          }
        }
      });
    }

    if (!device.isConnected) return Future.value();
    if (markTransportConnected) {
      _markTransportConnected(DeviceTransportKind.bluetooth, device);
    }

    final setupInProgress = _setupCoordinator.inFlight;
    if (setupInProgress != null) return setupInProgress;

    final needsBootstrap =
        forceRefresh ||
        services.isEmpty ||
        _myCharacteristic == null ||
        indoorBikeCharacteristic == null ||
        ftmsControlPointCharacteristic == null ||
        !subscribed;
    if (!needsBootstrap) return Future.value();

    return _setupCoordinator.run(
      (generation) => _performConnectionSetup(
        device,
        generation: generation,
        forceRefresh: forceRefresh,
      ),
    );
  }

  Future<void> _performConnectionSetup(
    BluetoothDevice device, {
    required int generation,
    required bool forceRefresh,
  }) async {
    bool connectionIsCurrent() =>
        _setupCoordinator.isCurrent(generation) && device.isConnected;

    if (Platform.isAndroid && device.mtuNow <= 23) {
      _mtuRequestedForConnection = false;
    }

    if (forceRefresh) {
      subscribed = false;
      charReceived.value = false;
      _myCharacteristic = null;
      indoorBikeCharacteristic = null;
      ftmsControlPointCharacteristic = null;
      machineStatusCharacteristic = null;
      await _machineStatusSubscription?.cancel();
      _machineStatusSubscription = null;
      _workoutControlLane.invalidateDelivery();
    }

    await _discoverServices(device, forceRefresh: forceRefresh);
    if (!connectionIsCurrent()) return;
    if (services.length > 1) await _findChar();
    if (!connectionIsCurrent()) return;
    await updateCustomCharacter(device);
    if (!connectionIsCurrent()) return;
  }

  Future<BluetoothCharacteristic?> _getMyCharacteristic(
    BluetoothDevice device,
  ) async {
    if (this.isSimulated) return null;
    if (!device.isConnected) {
      charReceived.value = false;
      return null;
    }

    if (_myCharacteristic == null) {
      await _discoverServices(device);
      if (services.length > 1) {
        await _findChar();
      }
    }

    charReceived.value = _myCharacteristic != null;
    return _myCharacteristic;
  }

  Future _discoverServices(
    BluetoothDevice device, {
    bool forceRefresh = false,
  }) async {
    if (this.isSimulated) return;

    // If a discovery is already in flight, just await it and return.
    if (_discoverServicesCompleter != null) {
      print(
        '[discoverServices] Already in progress – waiting for existing call to finish.',
      );
      await _discoverServicesCompleter!.future;
      return;
    }

    if (!forceRefresh && services.isNotEmpty) return;

    _discoverServicesCompleter = Completer<void>();
    try {
      services = await device.discoverServices();
    } catch (e) {
      print(e);
    } finally {
      _discoverServicesCompleter!.complete();
      _discoverServicesCompleter = null;
    }
  }

  Future _findChar() async {
    if (this.isSimulated) return;
    try {
      // custom characteristic
      BluetoothService cs = services.first;
      for (BluetoothService s in services) {
        if (s.uuid == Guid(csUUID)) {
          cs = s;
          break;
        }
      }
      List<BluetoothCharacteristic> characteristics = cs.characteristics;
      for (BluetoothCharacteristic c in characteristics) {
        if (c.uuid == Guid(ccUUID)) {
          _myCharacteristic = c;
          if (!_myCharacteristic!.isNotifying) {
            await _queueBleOperation(
              () => _myCharacteristic!.setNotifyValue(true),
            );
          }
        }
      }

      // firmware
      configAppCompatibleFirmware = false;
      for (BluetoothService s in services) {
        if (s.uuid == Guid("4FAFC201-1FB5-459E-8FCC-C5C9C331914B")) {
          _firmwareService = s;
          configAppCompatibleFirmware = true;
          break;
        }
      }
      if (configAppCompatibleFirmware) {
        characteristics = _firmwareService!.characteristics;
        for (BluetoothCharacteristic c in characteristics) {
          print(c.uuid.toString());
          if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130005")) {
            _firmwareDataCharacteristic = c;
          }
          if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130003")) {
            _firmwareControlCharacteristic = c;
          }
        }
      }

      // ftms
      BluetoothService ftmsService = services.first;
      for (BluetoothService s in services) {
        if (s.uuid == Guid(ftmsServiceUUID)) {
          ftmsService = s;
          characteristics = ftmsService.characteristics;
          break;
        }
      }
      for (BluetoothCharacteristic c in characteristics) {
        if (c.uuid == Guid(ftmsIndoorBikeDataUUID)) {
          // Discovery only records the characteristic. Notification lifecycle
          // is owned exclusively by the FTMS block/subscription methods.
          indoorBikeCharacteristic = c;
        }
        if (c.uuid == Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID)) {
          ftmsControlPointCharacteristic = c;
        }
        if (c.uuid == Guid(FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID)) {
          machineStatusCharacteristic = c;
          await _machineStatusSubscription?.cancel();
          _machineStatusSubscription = c.onValueReceived.listen(
            _machineStatusController.add,
          );
          if (!c.isNotifying) {
            await _queueBleOperation(() => c.setNotifyValue(true));
            print("subscribed to FTMS machine status characteristic");
          }
        }
      }

      charReceived.value = _myCharacteristic != null;
      _workoutControlLane.onAvailabilityChanged();
    } catch (e) {
      charReceived.value = false;
      _workoutControlLane.onAvailabilityChanged();
    }
  }

  ///Data Helpers****************************************************************

  bool subscribed = false;
  bool _mtuRequestedForConnection = false;
  final _lastRequestStopwatch = Stopwatch();
  // only used as a flag to prevent multiple concurrent instances of updateCustomCharacter
  bool _inUpdateLoop = false;

  Future updateCustomCharacter(BluetoothDevice device) async {
    if (this.isSimulated) return;
    if (_inUpdateLoop) {
      return;
    }
    if (Platform.isAndroid) {
      if (!_mtuRequestedForConnection && device.mtuNow <= 23) {
        _mtuRequestedForConnection = true;
        try {
          await device.requestMtu(515);
        } catch (e) {
          _mtuRequestedForConnection = false;
        }
      }
    }
    _inUpdateLoop = true;
    try {
      if (!subscribed) {
        decode(device);
        await updateIndoorBikeData(device);
      }
      if (_myCharacteristic != null && !_myCharacteristic!.isNotifying) {
        await _queueBleOperation(() => _myCharacteristic!.setNotifyValue(true));
      }
      if (!_lastRequestStopwatch.isRunning) {
        await requestSettings(device);
        _lastRequestStopwatch.start();
      } else if (_lastRequestStopwatch.elapsed > Duration(seconds: 5)) {
        _lastRequestStopwatch.reset();
        await requestSettings(device);
      }
    } finally {
      _inUpdateLoop = false;
    }
  }

  Future<void> ensureCustomCharacteristicStream(BluetoothDevice device) async {
    if (this.isSimulated) return;
    if (isDirConConnected) {
      subscribed = true;
      charReceived.value = true;
      return;
    }
    if (!device.isConnected) return;

    if (_myCharacteristic == null) {
      await _discoverServices(device);
      if (services.length > 1) {
        await _findChar();
      }
    }

    final characteristic = _myCharacteristic;
    if (characteristic == null) return;

    if (!subscribed) {
      decode(device);
    }

    if (!characteristic.isNotifying) {
      await _queueBleOperation(() => characteristic.setNotifyValue(true));
    }
  }

  Future<void> updateIndoorBikeData(BluetoothDevice device) async {
    if (isFtmsSubscriptionBlocked) return;

    // The DIRCON session subscribes to FTMS during transport setup. Avoid
    // attempting BLE service discovery merely because a screen wants to make
    // sure the live stream is active.
    if (!isTransportActive || isDirConConnected) return;

    if (indoorBikeCharacteristic == null) {
      await _discoverServices(device);
      if (isFtmsSubscriptionBlocked) return;
      if (services.length > 1) {
        await _findChar();
      }
    }

    final ftmsCharacteristic = indoorBikeCharacteristic;
    if (ftmsCharacteristic == null) {
      print("no FTMS characteristic");
      return;
    }

    try {
      if (isFtmsSubscriptionBlocked) return;
      if (!ftmsCharacteristic.isNotifying) {
        await _queueBleOperation(() => ftmsCharacteristic.setNotifyValue(true));
      }
    } catch (e) {
      print("failed to enable FTMS notify: $e");
      return;
    }

    if (isFtmsSubscriptionBlocked) return;
    await _ftmsSubscription?.cancel();

    _ftmsSubscription = ftmsCharacteristic.onValueReceived.listen(
      _decodeIndoorBikeData,
      onError: (Object e) {
        print('Error in FTMS subscription: $e');
      },
    );
    device.cancelWhenDisconnected(_ftmsSubscription!);
  }

  Future<void> blockFtmsSubscription() async {
    _ftmsSubscriptionBlocks++;
    if (_ftmsSubscriptionBlocks > 1) return;

    final generation = ++_ftmsBlockGeneration;
    final subscription = _ftmsSubscription;
    final dirConSubscription = _dirConFtmsSubscription;
    _ftmsSubscription = null;
    _dirConFtmsSubscription = null;
    await subscription?.cancel();
    await dirConSubscription?.cancel();

    final characteristic = indoorBikeCharacteristic;
    if (generation == _ftmsBlockGeneration &&
        isFtmsSubscriptionBlocked &&
        characteristic != null &&
        characteristic.isNotifying) {
      await _queueBleOperation(() => characteristic.setNotifyValue(false));
    }
  }

  Future<void> unblockFtmsSubscription(BluetoothDevice device) async {
    if (_ftmsSubscriptionBlocks == 0) return;
    _ftmsSubscriptionBlocks--;
    if (_ftmsSubscriptionBlocks > 0) return;

    _ftmsBlockGeneration++;
    final dirConClient = _dirConClient;
    if (isDirConConnected && dirConClient != null) {
      await dirConClient.ensureCharacteristic(
        serviceUuid: ftmsServiceUUID,
        characteristicUuid: ftmsIndoorBikeDataUUID,
        enableNotifications: true,
      );
      if (isFtmsSubscriptionBlocked || _dirConClient != dirConClient) return;
      _dirConFtmsSubscription = dirConClient
          .characteristicNotifications(ftmsIndoorBikeDataUUID)
          .listen(_decodeIndoorBikeData);
      return;
    }
    await updateIndoorBikeData(device);
  }

  void _decodeIndoorBikeData(List<int> value) {
    try {
      lastFtmsUpdate = DateTime.now();
      if (value.length < 4) {
        return;
      }

      Uint8List data = Uint8List.fromList(value);
      ByteData byteData = ByteData.sublistView(data);

      int flags = byteData.getUint16(0, Endian.little);
      int index = 2;

      bool hasBytes(int requiredBytes) =>
          (index + requiredBytes) <= byteData.lengthInBytes;

      // Reset fields
      ftmsData.cadence = 0;
      ftmsData.watts = 0;
      ftmsData.heartRate = 0;
      ftmsData.speed = 0;

      if (!hasBytes(2)) {
        return;
      }
      ftmsData.speed =
          byteData.getUint16(index, Endian.little) ~/ 100; // resolution 0.01
      index += 2;

      if ((flags & (1 << 1)) != 0) {
        if (!hasBytes(2)) return;
        index += 2;
      }

      if ((flags & (1 << 2)) != 0) {
        if (!hasBytes(2)) return;
        ftmsData.cadence =
            byteData.getUint16(index, Endian.little) ~/ 2; // resolution 0.5
        index += 2;
      }

      if ((flags & (1 << 3)) != 0) {
        if (!hasBytes(2)) return;
        index += 2;
      }
      if ((flags & (1 << 4)) != 0) {
        if (!hasBytes(3)) return;
        index += 3;
      }

      if ((flags & (1 << 5)) != 0) {
        if (!hasBytes(2)) return;
        ftmsData.resistance = byteData.getInt16(index, Endian.little);
        index += 2;
      }

      if ((flags & (1 << 6)) != 0) {
        if (!hasBytes(2)) return;
        ftmsData.watts = byteData.getInt16(index, Endian.little);
        index += 2;
      }

      if ((flags & (1 << 7)) != 0) {
        if (!hasBytes(2)) return;
        index += 2;
      }
      if ((flags & (1 << 8)) != 0) {
        if (!hasBytes(1)) return;
        index += 1;
      }

      if ((flags & (1 << 9)) != 0) {
        if (!hasBytes(1)) return;
        ftmsData.heartRate = byteData.getUint8(index);
        index += 1;
      }

      if (DirConClient.diagnosticsEnabled && isDirConConnected) {
        print(
          '[DIRCON][FTMS] raw=${_diagnosticHex(value)} '
          'speed=${ftmsData.speed} cadence=${ftmsData.cadence} '
          'watts=${ftmsData.watts} resistance=${ftmsData.resistance} '
          'heartRate=${ftmsData.heartRate}',
        );
      }

      if (!_ftmsDataController.isClosed) {
        _ftmsDataController.add(
          FtmsData(
            cadence: ftmsData.cadence,
            watts: ftmsData.watts,
            targetERG: ftmsData.targetERG,
            mode: ftmsData.mode,
            resistance: ftmsData.resistance,
            heartRate: ftmsData.heartRate,
            speed: ftmsData.speed,
          ),
        );
      }

      // Emit a characteristic change event for FTMS data updates
      if (!_characteristicChangeController.isClosed) {
        _characteristicChangeController.add(
          CharacteristicChangeEvent(
            vName: "FTMS_DATA",
            reference: "FTMS",
            value: "updated",
            type: "ftms",
          ),
        );
      }
    } catch (e) {
      print('Error parsing FTMS packet: $e');
    }
  }

  bool _ftmsRecoveryInProgress = false;
  DateTime? _lastFtmsRecoveryAttempt;
  static const Duration _ftmsWatchdogTimeout = Duration(seconds: 15);
  static const Duration _ftmsRecoveryCooldown = Duration(seconds: 30);

  /// Checks the health of the FTMS data stream and attempts to recover if stalled.
  /// Skips if a recovery is already in progress.
  Future<void> checkFtmsHealth(BluetoothDevice device) async {
    // Screens and operations can intentionally pause FTMS notifications. A
    // CCCD toggle here would bypass that block and compete for the transport.
    if (isFtmsSubscriptionBlocked) return;
    if (isSimulated || !isTransportActive) return;
    // DIRCON socket loss has its own reconnect path. The notification toggle
    // below is specifically a BLE CCCD recovery operation.
    if (isDirConConnected) return;
    if (_ftmsRecoveryInProgress) return;

    final now = DateTime.now();
    final recentlyTriedRecovery =
        _lastFtmsRecoveryAttempt != null &&
        now.difference(_lastFtmsRecoveryAttempt!) < _ftmsRecoveryCooldown;

    // Before the first FTMS packet, subscribed may already be true because the
    // custom characteristic decode path is active. Keep retrying the FTMS notify
    // setup on the watchdog cooldown so a failed initial setNotifyValue(true)
    // does not leave the stream silent until reconnect.
    if (lastFtmsUpdate == null) {
      if (!recentlyTriedRecovery) {
        _ftmsRecoveryInProgress = true;
        _lastFtmsRecoveryAttempt = now;
        try {
          await updateIndoorBikeData(device);
        } catch (e) {
          print('Error retrying FTMS notify setup: $e');
          if (!device.isConnected) {
            _triggerReconnect(device);
          }
        } finally {
          _ftmsRecoveryInProgress = false;
        }
      }
      return;
    }

    // If we have received data before, and it's been more than the watchdog
    // timeout, try one recovery pass.  Do not toggle the CCCD every timer tick;
    // that adds extra BLE control traffic on the same Android radio Grupetto
    // uses for peripheral advertising/GATT serving.
    if (now.difference(lastFtmsUpdate!) > _ftmsWatchdogTimeout &&
        !recentlyTriedRecovery) {
      print(
        'FTMS connection appears stalled (last update: $lastFtmsUpdate). Attempting recovery...',
      );
      _ftmsRecoveryInProgress = true;
      _lastFtmsRecoveryAttempt = now;

      try {
        if (indoorBikeCharacteristic != null && device.isConnected) {
          // Toggle notifications to reset the stream
          await _queueBleOperation(
            () => indoorBikeCharacteristic!.setNotifyValue(false),
          );
          await Future.delayed(const Duration(milliseconds: 200));

          if (!device.isConnected) {
            print('[FTMS Recovery] Device disconnected during recovery.');
            _triggerReconnect(device);
            return;
          }

          await _queueBleOperation(
            () => indoorBikeCharacteristic!.setNotifyValue(true),
          );

          // Force internal tracking update
          lastFtmsUpdate = DateTime.now(); // Reset to avoid loop
        }
      } catch (e) {
        print('Error attempting FTMS recovery: $e');
        // If recovery failed because the device disconnected, trigger reconnect
        if (!device.isConnected) {
          _triggerReconnect(device);
        }
      } finally {
        _ftmsRecoveryInProgress = false;
      }
    }
  }

  /// Proactively trigger auto-reconnect when we detect disconnection through
  /// a failed BLE operation rather than through the connectionState stream.
  void _triggerReconnect(BluetoothDevice device) {
    if (isUserDisconnect) return;
    print(
      '[FTMS Recovery] Device appears disconnected. Triggering reconnect...',
    );

    () async {
      await reconnectAndSetup(device);
    }();
  }

  Future<void> writeCommand(BluetoothDevice device, String name) async {
    if (this.isSimulated) return;
    // Firmware that wasn't Compatible with the app would reboot whenever this command was read.
    if (!this.configAppCompatibleFirmware && name == saveVname) {
      return;
    }

    Map<String, dynamic>? command;
    for (final c in customCharacteristic) {
      if (c["vName"] == name) {
        command = c;
        break;
      }
    }
    if (command == null) return;

    try {
      await writeCustomCharacteristic(device, [
        0x02,
        int.parse(command["reference"]),
        0x01,
      ]);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  Future saveAllSettings(BluetoothDevice device) async {
    if (this.isSimulated) return;
    for (var c in this.customCharacteristic) {
      if (c["isSetting"] == true) await writeToSS2k(device, c);
    }
    await writeCommand(device, saveVname);
  }

  Future reboot(BluetoothDevice device) async {
    if (this.isSimulated) return;
    await writeCommand(device, rebootVname);
  }

  Future resetToDefaults(BluetoothDevice device) async {
    if (this.isSimulated) return;
    await writeCommand(device, resetVname);
  }

  Future resetPowerTable(BluetoothDevice device) async {
    if (this.isSimulated) return;
    await writeCommand(device, resetPowerTableVname);
  }

  //request all settings
  Future requestSettings(BluetoothDevice device) async {
    if (this.isSimulated) return;

    await blockFtmsSubscription();
    try {
      for (var c in this.customCharacteristic) {
        // Firmware that wasn't Compatible with the app would reboot whenever this command was read.
        if (!this.configAppCompatibleFirmware && c["vName"] == saveVname) {
          continue;
        }

        // Do not poll for BLE logging as it floods the connection. We rely on notifications for this.
        if (c["vName"] == BLE_logStreamVname) {
          continue;
        }

        try {
          await writeCustomCharacteristic(device, [
            0x01,
            int.parse(c["reference"]),
          ]);
        } catch (e) {
          Snackbar.show(
            ABC.c,
            "Failed to write to SmartSpin2k $e",
            success: false,
          );
        }
      }
    } finally {
      await unblockFtmsSubscription(device);
    }
  }

  /// Requests only editable settings belonging to [settingType]. Cached values
  /// remain available while the authoritative values arrive from the device.
  Future<void> requestSettingsForType(
    BluetoothDevice device,
    SettingType settingType,
  ) async {
    if (isSimulated) return;

    for (final c in customCharacteristic) {
      if (c["isSetting"] != true || c["settingType"] != settingType) {
        continue;
      }

      try {
        await writeCustomCharacteristic(device, [
          0x01,
          int.parse(c["reference"]),
        ]);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to request setting $e", success: false);
      }
    }
  }

  Future<void> requestAllEditableSettings(BluetoothDevice device) async {
    for (final settingType in SettingType.values) {
      await requestSettingsForType(device, settingType);
    }
  }

  //request single setting
  Future<void> requestSetting(
    BluetoothDevice device,
    String name, {
    int? extraByte,
  }) async {
    if (this.isSimulated) return;

    Map<String, dynamic>? setting;
    for (final c in customCharacteristic) {
      if (c["vName"] == name) {
        setting = c;
        break;
      }
    }
    if (setting == null) return;

    // Firmware that wasn't compatible with the app would reboot whenever this
    // command was read.
    if (!configAppCompatibleFirmware && setting["vName"] == saveVname) {
      return;
    }

    try {
      final value = <int>[0x01, int.parse(setting["reference"])];
      if (extraByte != null) {
        value.add(extraByte);
      }
      await writeCustomCharacteristic(device, value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to request setting $e", success: false);
    }
  }

  int getPrecision(Map c) {
    int precision = 0;
    switch (c["type"]) {
      case "string":
      case "int":
      case "long":
        precision = 0;
        break;
      default:
        precision = 2;
    }
    return precision;
  }

  Future<void> writeToSS2k(
    BluetoothDevice device,
    Map c, {
    String s = "",
  }) async {
    if (this.isSimulated) return;
    //If a specific value wasn't passed, use the previously saved value
    if (s == "") {
      s = c["value"];
    }
    //If the value wasn't read by the firmware, don't try to set it.
    if (s == noFirmSupport) {
      return;
    }

    List<int> value = [0x02, int.parse(c["reference"])];

    switch (c["type"]) {
      case "string":
        value = value + s.codeUnits;
      case "int":
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map(
          (b) => '0x${b.toRadixString(16).padLeft(2, '0')}',
        );
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1)),
        ];
        break;
      case "bool":
        (s == "false") ? s = "0" : s = "1";
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map(
          (b) => '0x${b.toRadixString(16).padLeft(2, '0')}',
        );
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1)),
        ];
        break;
      case "float":
        int t = (double.parse(s) * 10).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map(
          (b) => '0x${b.toRadixString(16).padLeft(2, '0')}',
        );
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1)),
        ];
        break;
      case "long":
        // Four little-endian bytes, which is what the firmware reassembles
        // from rxValue[2..5]. toSigned keeps an out-of-range value from
        // throwing here rather than being rejected by the device.
        int t = double.parse(s).round().toSigned(32);
        final bytes = Uint8List(4)
          ..buffer.asByteData().setInt32(0, t, Endian.little);
        print('bytes: ${bytes}');
        value = [0x02, int.parse(c["reference"]), ...bytes];
        break;
      case "powerTableData":
        // Define the INT_MIN value for uint16_t in little endian format
        const int intMinValue = -32768;

        // Loop through each row of the tableData
        for (
          int rowIndex = 0;
          rowIndex < this.powerTableData.length;
          rowIndex++
        ) {
          List<int?> row = this.powerTableData[rowIndex];
          List<int> rowValue = [];

          // Convert each entry in the row to its little-endian byte representation
          for (int? entry in row) {
            int valueToConvert = entry ?? intMinValue;
            final list = Uint16List.fromList([valueToConvert]);
            final bytes = Uint8List.view(list.buffer);
            final out = bytes.map(
              (b) => '0x${b.toRadixString(16).padLeft(2, '0')}',
            );
            print('bytes: ${out}');
            rowValue.add(bytes[0]); // Low byte
            rowValue.add(bytes[1]); // High byte
          }

          // Combine the request, reference, and row data
          List<int> rowToSend =
              [0x02, int.parse(c["reference"]), rowIndex] + rowValue;

          // Write the data to the device
          try {
            await writeCustomCharacteristic(device, rowToSend);
          } catch (e) {
            Snackbar.show(
              ABC.c,
              "Failed to write to SmartSpin2k $e",
              success: false,
            );
            return;
          }
        }
        break;

      default:
      //value = [0xff];
    }
    try {
      await writeCustomCharacteristic(device, value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  Future<void> _writeQueue = Future.value();
  DateTime? _lastBleWriteCompletedAt;
  Completer<void>? _pendingCustomResponse;
  int? _pendingCustomResponseReference;
  final CustomReadRequestCoalescer _customReadRequestCoalescer =
      CustomReadRequestCoalescer();
  static const Duration _customResponseTimeout = Duration(seconds: 2);
  final Object _bleOperationZoneKey = Object();
  final Set<Object> _activeBleOperationTokens = <Object>{};

  // Android does not expose an "is the BLE radio idle?" signal to app code.
  // Treat the completion of the previous GATT write as the best available
  // back-pressure signal, with a small guard interval on Android/Peloton so
  // SS2kConfigApp does not monopolize the shared BLE stack while Grupetto is
  // also advertising/serving as a peripheral.
  Duration get _bleWriteGuardInterval =>
      Platform.isAndroid ? const Duration(milliseconds: 35) : Duration.zero;

  Future<T> _queueBleOperation<T>(
    Future<T> Function() operation, {
    bool allowInline = true,
  }) {
    // Some queued operations perform discovery, and discovery may enable CCCD
    // notifications. Running nested queue work inline avoids self-deadlocking
    // while the outer queued operation is waiting for discovery to finish. The
    // zone token keeps that escape hatch scoped to the current queued operation
    // so unrelated BLE callbacks still serialize behind the queue.
    final currentToken = Zone.current[_bleOperationZoneKey];
    if (allowInline &&
        currentToken != null &&
        _activeBleOperationTokens.contains(currentToken)) {
      return operation();
    }

    final queued = _writeQueue.catchError((_) {}).then((_) async {
      final lastWrite = _lastBleWriteCompletedAt;
      final guard = _bleWriteGuardInterval;
      if (lastWrite != null && guard > Duration.zero) {
        final elapsed = DateTime.now().difference(lastWrite);
        if (elapsed < guard) {
          await Future.delayed(guard - elapsed);
        }
      }

      final token = Object();
      _activeBleOperationTokens.add(token);
      try {
        return await runZoned(
          operation,
          zoneValues: {_bleOperationZoneKey: token},
        );
      } finally {
        _activeBleOperationTokens.remove(token);
        _lastBleWriteCompletedAt = DateTime.now();
      }
    });

    _writeQueue = queued.then<void>((_) {}, onError: (_) {});
    return queued;
  }

  /// Writes to the SmartSpin2k custom characteristic and does not complete
  /// until the server returns the matching response (or the response times out).
  Future<void> writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> value,
  ) {
    if (isSimulated) return Future<void>.value();
    return _customReadRequestCoalescer.schedule(
      value,
      (packet) => _writeCustomCharacteristic(device, packet),
    );
  }

  Future<void> _writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> value,
  ) async {
    return _queueBleOperation(() async {
      final dirConClient = _dirConClient;
      if (dirConClient != null && dirConClient.isConnected) {
        try {
          final response = await dirConClient.writeCharacteristic(
            ccUUID,
            value,
          );
          if (response.isNotEmpty) _decodeCustomValue(response);
        } catch (error) {
          print('[DIRCON] Custom characteristic write failed: $error');
          rethrow;
        }
        return;
      }

      final characteristic = await _getMyCharacteristic(device);
      if (characteristic != null && characteristic.device.isConnected) {
        // Subscribe before writing so even a very fast server response cannot be
        // missed. Custom-characteristic writes are kept in the queue until the
        // response bearing the same characteristic reference arrives.
        if (!subscribed) {
          decode(device);
        }
        if (!characteristic.isNotifying) {
          await characteristic.setNotifyValue(true);
        }

        final response = Completer<void>();
        final expectedReference = value.length > 1 ? value[1] : null;
        if (expectedReference != null) {
          _pendingCustomResponse = response;
          _pendingCustomResponseReference = expectedReference;
        }

        try {
          await characteristic.write(value);
          if (expectedReference != null) {
            await response.future.timeout(_customResponseTimeout);
          }
        } catch (e) {
          Snackbar.show(
            ABC.c,
            "Failed to write to SmartSpin2k $e",
            success: false,
          );
        } finally {
          if (identical(_pendingCustomResponse, response)) {
            _pendingCustomResponse = null;
            _pendingCustomResponseReference = null;
          }
        }
      } else {
        Snackbar.show(
          ABC.c,
          "Failed to write to SmartSpin2k - Not Connected",
          success: false,
        );
      }
    });
  }

  void setWorkoutTargetPower(int watts, {bool force = false}) {
    _workoutControlActive = true;
    // Store what the lane actually sent, not the requested value: an imported
    // workout can ask for a target outside sint16 and the lane clamps it.
    ftmsData._targetERG = _workoutControlLane.setTargetPower(
      watts,
      force: force,
    );
  }

  void resetWorkoutSimulation() {
    _workoutControlActive = false;
    _workoutControlLane.resetSimulation();
    // Zero-grade simulation releases the ERG target, so the displayed target
    // must follow or it reports a hold the trainer is no longer applying.
    ftmsData._targetERG = 0;
  }

  bool _isWorkoutControlReady() {
    if (isSimulated) return false;
    final state = _transportStateController.value;
    if (state.phase != DeviceTransportPhase.connected) return false;
    return switch (state.transport) {
      DeviceTransportKind.dircon => _dirConClient?.isConnected ?? false,
      DeviceTransportKind.bluetooth => ftmsControlPointCharacteristic != null,
      DeviceTransportKind.none => false,
    };
  }

  Future<bool> _dispatchWorkoutControlBatch(
    WorkoutControlBatch batch,
    bool Function() isCurrent,
  ) {
    return _queueBleOperation(() async {
      for (final command in batch.commands) {
        if (!isCurrent()) return false;
        await _writeFtmsControlPointCommandNow(command);
      }
      return isCurrent();
    }, allowInline: false);
  }

  Future<void> _writeFtmsControlPointCommandNow(List<int> command) async {
    final dirConClient = _dirConClient;
    if (_transportStateController.value.transport ==
            DeviceTransportKind.dircon &&
        dirConClient != null &&
        dirConClient.isConnected) {
      await dirConClient.writeCharacteristic(ftmsControlPointUUID, command);
      return;
    }

    final characteristic = ftmsControlPointCharacteristic;
    if (_transportStateController.value.transport !=
            DeviceTransportKind.bluetooth ||
        characteristic == null ||
        !characteristic.device.isConnected) {
      throw StateError('FTMS Control Point is not ready');
    }
    await characteristic.write(command);
  }

  /// Writes an encoded FTMS Control Point command over the active transport.
  ///
  /// DIRCON sessions intentionally do not create FlutterBluePlus
  /// characteristics, so commands whose only input is a cached BLE
  /// characteristic can never reach the device while DIRCON is active.
  Future<void> writeFtmsControlPointCommand(List<int> command) async {
    if (isSimulated) return;
    return _queueBleOperation(() => _writeFtmsControlPointCommandNow(command));
  }

  void decode(BluetoothDevice device) {
    if (this.isSimulated) return;

    subscribed = true;
    _ensureCachedMap();

    if (isDirConConnected) {
      charReceived.value = true;
      return;
    }

    _notifySubscription?.cancel();
    final characteristic = _myCharacteristic;
    if (characteristic == null) {
      subscribed = false;
      charReceived.value = false;
      return;
    }

    _notifySubscription = characteristic.onValueReceived.listen(
      _decodeCustomValue,
    );
    device.cancelWhenDisconnected(_notifySubscription!);
  }

  void _decodeCustomValue(List<int> value) {
    try {
      if (value.isEmpty) return;

      // Both a normal response (0x80) and an unsupported-setting response
      // (0xff) finish the in-flight request. Complete this before decoding so
      // even a short or otherwise unsupported payload releases the next write.
      if (value.length > 1 && (value[0] == 0x80 || value[0] == 0xff)) {
        final pendingResponse = _pendingCustomResponse;
        if (pendingResponse != null &&
            !pendingResponse.isCompleted &&
            value[1] == _pendingCustomResponseReference) {
          pendingResponse.complete();
        }
      }

      if (value[0] == 0x80) {
        if (value.length < 2) return;

        // Use cached map for O(1) lookup
        var c = _cachedCharacteristicMap?[value[1]];

        if (c != null) {
          if (value.length == 2 && c["type"] != "string") {
            return;
          }

          var length = value.length;
          var t = new Uint8List(length);
          for (var i = 0; i < length; i++) {
            t[i] = value[i];
          }
          var data = t.buffer.asByteData();

          switch (c["type"]) {
            case "int":
              {
                if (data.lengthInBytes >= 4) {
                  c["value"] = data.getInt16(2, Endian.little).toString();
                } else if (data.lengthInBytes == 3) {
                  c["value"] = value[2].toString();
                } else {
                  c["value"] = noFirmSupport;
                }

                if (c["value"] != noFirmSupport) {
                  simulatedTargetWatts = (c["reference"] == "0x28")
                      ? c["value"]
                      : simulatedTargetWatts;
                  if (c["vName"] == FTMSModeVname) {
                    this.simulatedFTMSmode = c["value"];
                    FTMSmode = int.parse(this.simulatedFTMSmode);
                  }
                }
                // Emit characteristic change event
                _emitCharacteristicChange(c);
                break;
              }

            case "bool":
              {
                String b = (value[2] == 0) ? "false" : "true";
                c["value"] = b;
                if (c["vName"] == simulateTargetWattsVname) {
                  if (b == "true") {
                    this.simulateTargetWatts = true;
                    print('Simulate target watts = $simulateTargetWatts');
                  } else if (b == "false") {
                    this.simulateTargetWatts = false;
                    print('Simulate target watts = $simulateTargetWatts');
                  }
                }
                // Emit characteristic change event
                _emitCharacteristicChange(c);
                break;
              }
            case "float":
              {
                c["value"] = (data.getInt16(2, Endian.little) / 10).toString();
                // Emit characteristic change event
                _emitCharacteristicChange(c);
                break;
              }
            case "long":
              {
                // Two header bytes plus an int32. Firmware without support
                // for this characteristic answers with the header alone.
                if (data.lengthInBytes >= 6) {
                  c["value"] = data.getInt32(2, Endian.little).toString();
                } else {
                  c["value"] = noFirmSupport;
                }
                // Emit characteristic change event
                _emitCharacteristicChange(c);
                break;
              }
            case "string":
              {
                //remove the data bytes
                var subT = new Uint8List(length - 2);
                for (int i = 0; i < length - 2; i++) {
                  subT[i] = t[i + 2];
                }
                // Use allowMalformed to prevent crashes on split multibyte characters
                c["value"] = utf8.decode(subT, allowMalformed: true);

                // Push to log stream immediately after decoding
                if (c["vName"] == BLE_logStreamVname) {
                  _logStreamController.add(c["value"]);
                }

                // Format Found Devices into a JSON String
                if (c["vName"] == foundDevicesVname) {
                  String _pm = "";
                  String _hrm = "";
                  for (var i in this.customCharacteristic) {
                    if (i["vName"] == connectedHRMVname) {
                      _hrm = i["value"];
                    }
                    if (i["vName"] == connectedPWRVname) {
                      _pm = i["value"];
                    }
                  }
                  String t = c["value"];
                  String tList = "";
                  if (t == " " || t == "null") {
                    t = "";
                  } else {
                    t = t.substring(1, t.length - 1);
                    t += ",";
                  }
                  tList =
                      defaultDevices +
                      t +
                      '"device -5":{"name":"' +
                      _hrm +
                      '","UUID":"0x180d"},"device -6":{"name":"' +
                      _pm +
                      '","UUID":"0x1818"}}]';
                  c["value"] = tList;
                  print(c["value"]);
                }
                //Set the firmware version
                if (c["vName"] == fwVname) {
                  this.firmwareVersion.value = c["value"];
                  print(
                    "FW Version Was Updated!! ${c['value']} ${this.firmwareVersion.value}",
                  );
                }
                // Emit characteristic change event
                _emitCharacteristicChange(c);
                break;
              }
            case "powerTableData":
              int cadenceRow = value[2];
              if (cadenceRow >= 0 && cadenceRow < this.powerTableData.length) {
                List<int?> row = [];
                for (int i = 3; i < value.length; i += 2) {
                  if (data.getInt16(i, Endian.little) == -32768) {
                    row.add(null);
                  } else {
                    row.add(data.getInt16(i, Endian.little));
                  }
                }
                this.powerTableData[cadenceRow] = row;
              }
              // Emit characteristic change event
              _emitCharacteristicChange(c);
              break;
            default:
              {
                String type = c["type"];
                print("No decoder found for $type");
              }
          }
          if (DirConClient.diagnosticsEnabled && isDirConConnected) {
            final decodedValue = c["vName"] == passwordVname
                ? '<redacted>'
                : c["value"]?.toString();
            print(
              '[DIRCON][CUSTOM] ref=0x${value[1].toRadixString(16).padLeft(2, '0')} '
              'name=${c["vName"]} type=${c["type"]} value=$decodedValue '
              'raw=${c["vName"] == passwordVname ? '<redacted>' : _diagnosticHex(value)}',
            );
          }
        }
      } else if (value[0] == 0xff) {
        if (value.length > 1) {
          var c = _cachedCharacteristicMap?[value[1]];
          if (c != null) {
            c["value"] = noFirmSupport;
            // Emit characteristic change event
            _emitCharacteristicChange(c);
          }
        }
      }
    } catch (e) {
      print("Error decoding BLE data: $e");
    }
  }

  String _diagnosticHex(List<int> value) =>
      value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Helper method to emit characteristic change events
  void _emitCharacteristicChange(Map c) {
    if (!_characteristicChangeController.isClosed) {
      _characteristicChangeController.add(
        CharacteristicChangeEvent(
          vName: c["vName"] ?? "",
          reference: c["reference"] ?? "",
          value: c["value"]?.toString() ?? "",
          type: c["type"] ?? "",
        ),
      );
    }
  }

  /// Dispose of resources
  void dispose() {
    _isDisposed = true;
    _ftmsPostConnectionTimer?.cancel();
    _ftmsPostConnectionTimer = null;
    _transportStateController.removeListener(_handleTransportStateChanged);
    _workoutControlLane.dispose();
    _transportStateController.dispose();
    unawaited(_closeDirCon());
    _notifySubscription?.cancel();
    _ftmsSubscription?.cancel();
    _characteristicChangeController.close();
    _ftmsDataController.close();
    _machineStatusSubscription?.cancel();
    _machineStatusSubscription = null;
    _machineStatusController.close();
  }
}
