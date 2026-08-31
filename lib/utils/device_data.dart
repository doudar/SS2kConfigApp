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
import 'ble_scan_results_protocol.dart';
import 'bleOTA.dart';
import 'connection_setup_coordinator.dart';
import 'device_transport_state.dart';
import 'dircon_client.dart';
import 'settings_snapshot_protocol.dart';
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

/// Why a caller waiting on FTMS notifications stopped waiting.
///
/// Deliberately not a bool: a calibration run that starts without `0x2ADA` can
/// have got there four ways, and the Copy Log report is the only place anyone
/// ever finds out which. "Never became ready" and "the firmware has no Machine
/// Status characteristic" call for different replies from a maintainer.
enum FtmsNotificationsReadiness {
  /// The stream is live: the session is still valid, a listener is attached,
  /// and wire-level notifications were enabled successfully.
  ready,

  /// The block never drained within the caller's budget.
  timedOut,

  /// The block drained, but the characteristic could not be brought up —
  /// absent from this firmware, enablement failed, or the transport dropped.
  unavailable,

  /// The [DeviceData] was disposed while the caller was waiting.
  disposed,
}

enum _SettingsSnapshotSupport { unknown, supported, unsupported }

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

/// How urgent a transport operation is, relative to everything already queued.
///
/// The queue is shared by BLE *and* DIRCON work, and by traffic with wildly
/// different urgency: a calibration command the user is waiting on, and a
/// forty-entry settings sweep that can afford to wait. Ordering by arrival
/// alone is what let the sweep bury the command.
enum TransportOpPriority {
  /// Commands the device acts on and the user is waiting for: FTMS control
  /// point. Overtakes everything queued.
  control,

  /// User-initiated writes and workout target delivery.
  interactive,

  /// Settings sweeps and periodic polls. Nothing is waiting on these.
  background,
}

class _PendingTransportOp {
  _PendingTransportOp(this.priority, this.label, this.run);

  final TransportOpPriority priority;
  final String label;
  final Future<void> Function() run;
  final DateTime queuedAt = DateTime.now();
}

/// FTMS discovery results for one connection epoch. See
/// [DeviceData._ftmsCapabilitiesForEpoch] for why this is scoped per epoch.
class _FtmsCapabilities {
  _FtmsCapabilities(this.epoch);

  final int epoch;

  /// Whether an FTMS service with characteristics was found at all.
  bool discoveryRan = false;

  /// Whether 0x2ADA was among them.
  bool machineStatusPresent = false;

  /// Whether the one permitted re-probe has already been spent on this epoch.
  bool reprobed = false;
}

class DeviceData {
  DeviceData({DirConConnector? dirConConnector})
    : _dirConConnector = dirConConnector ?? _connectDirConClient {
    _workoutControlLane = WorkoutControlLane(
      transportState: () => _transportStateController.value,
      isReady: _isWorkoutControlReady,
      dispatch: _dispatchWorkoutControlBatch,
    );
    _transportStateController.addListener(_handleTransportStateChanged);
    // The saved-device pickers can be opened before either scan protocol has
    // produced a result. Seed their backing characteristic with valid choices
    // so those dialogs are never built from a null/empty JSON value.
    _applyStreamedFoundDevices(const <BleScanDevice>[]);
  }

  static Future<DirConSession> _connectDirConClient(String host) =>
      DirConClient.connect(host);

  final DirConConnector _dirConConnector;

  String? advertisedIpAddress;
  DirConSession? _dirConSession;
  StreamSubscription<List<int>>? _dirConNotificationSubscription;
  StreamSubscription<List<int>>? _dirConFtmsSubscription;
  StreamSubscription<List<int>>? _dirConMachineStatusSubscription;
  StreamSubscription<List<int>>? _dirConControlPointSubscription;
  StreamSubscription<void>? _dirConDisconnectedSubscription;
  bool _dirConSetupComplete = false;
  bool _dirConReconnectInProgress = false;

  /// The transport epoch the DIRCON->BLE fallback brought up, or null if this
  /// session never fell back. See [isDirConFallbackSilent].
  int? _dirConFallbackEpoch;
  bool _initialConnectionInProgress = false;
  bool _workoutControlActive = false;
  int _ftmsNotificationBlocks = 0;
  int _ftmsBlockGeneration = 0;
  Timer? _ftmsPostConnectionTimer;
  bool _ftmsPostConnectionBlockActive = false;

  /// True only while FTMS Machine Status is genuinely usable: a listener is
  /// published and its wire-level enable succeeded on the current transport.
  ///
  /// A drained block count proves none of that — the characteristic may be
  /// absent, the enable may have failed, the session may have died — so this is
  /// what [awaitFtmsNotificationsReady] answers from rather than the counter.
  bool _machineStatusNotificationsLive = false;
  bool _controlPointNotificationsLive = false;
  _FtmsCapabilities? _ftmsCapabilities;

  /// Waiters for the current block cycle. Created on the outermost 0 -> 1
  /// transition and completed by the final unblock; see
  /// [awaitFtmsNotificationsReady] for the full lifecycle.
  Completer<void>? _ftmsReadyCompleter;

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
  bool get isFtmsNotificationsBlocked => _ftmsNotificationBlocks > 0;

  /// Whether any interactive FTMS lease is held. See
  /// [beginInteractiveFtmsSession].
  bool get hasInteractiveFtmsSession => _interactiveFtmsSessions.isNotEmpty;
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

    // `Stream.listen` discards the future an async callback returns, so an
    // uncaught throw in here is an unhandled async error with no owner: silent
    // in release, an isolate pause in debug. This one drives reconnection, so
    // it is also the callback least able to afford dying quietly.
    _reconnectSubscription = device.connectionState.listen(
      (state) async {
        try {
          // A DIRCON session deliberately leaves the Android BLE GATT
          // connection disconnected. Do not let that idle BLE state overwrite
          // the active network transport or start a competing reconnect loop.
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
        } catch (error) {
          print('[AutoReconnect] connection state handler failed: $error');
        }
      },
      onError: (Object error) =>
          print('[AutoReconnect] connectionState stream error: $error'),
    );
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
    final notifySubscription = _notifySubscription;
    final ftmsSubscription = _ftmsSubscription;
    final machineStatusSubscription = _machineStatusSubscription;
    final controlPointSubscription = _controlPointSubscription;
    await _closeDirCon();
    _resetConnectionState(cancelBleSubscriptions: false);
    await _safeCancel(notifySubscription, 'custom characteristic');
    await _safeCancel(ftmsSubscription, 'FTMS Indoor Bike Data');
    await _safeCancel(machineStatusSubscription, 'FTMS Machine Status');
    await _safeCancel(controlPointSubscription, 'FTMS Control Point');
    // A promoted BLE session can coexist with a DIRCON socket. Explicit
    // disconnect means both transports, not merely whichever one was active.
    if (device.isConnected) {
      await device.disconnectAndUpdateStream();
    }
  }

  Future<void> _connectDirCon(
    BluetoothDevice device,
    String ipAddress, {
    required bool waitForSetup,
  }) async {
    await _closeDirCon();
    final session = await _dirConConnector(ipAddress);
    try {
      await session.initialize(serviceUuid: csUUID, characteristicUuid: ccUUID);
    } catch (_) {
      await session.close();
      rethrow;
    }

    _dirConSession = session;
    _dirConSetupComplete = false;
    configAppCompatibleFirmware = true;
    _ensureCachedMap();
    // Registered before any optional discovery below. `disconnected` is a
    // broadcast stream with no replay: a transport failure raised while FTMS
    // discovery is in flight fires into it immediately, and if nothing is
    // listening yet that event is dropped and the session is closed before the
    // listener ever attaches.
    _dirConDisconnectedSubscription = session.disconnected.listen((_) {
      _handleDirConDisconnect(device);
    });
    _markTransportConnected(DeviceTransportKind.dircon, device);
    _dirConNotificationSubscription = session
        .characteristicNotifications(ccUUID)
        .listen(_decodeCustomValue);

    // Indoor Bike Data and Machine Status are set up independently: firmware
    // that exposes one but not the other must still deliver the one it has, and
    // neither gates configuration, which is already live above.
    final blocked = isFtmsNotificationsBlocked;
    final ftmsSubscription = await _subscribeDirConNotifications(
      session,
      ftmsIndoorBikeDataUUID,
      _decodeIndoorBikeData,
      label: 'FTMS Indoor Bike Data',
      enable: !blocked,
    );
    // Gated by the same block, for the same reason. An earlier revision exempted
    // Machine Status so calibration could never be blinded; review reversed that,
    // because a second stream outside the block is a second thing that can be
    // live while the transport is meant to be quiet. Calibration instead waits
    // for readiness — see [awaitFtmsNotificationsReady].
    final machineStatusSubscription = await _subscribeDirConNotifications(
      session,
      FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID,
      _forwardMachineStatus,
      label: 'FTMS Machine Status',
      enable: !blocked,
    );
    // The control point's own responses. Failures here are swallowed rather
    // than rethrown: this is an evidence channel, not a transport requirement,
    // and the two subscriptions above have already established that the session
    // is usable. A transport that dies at this exact moment is the disconnect
    // listener's problem.
    StreamSubscription<List<int>>? controlPointSubscription;
    try {
      controlPointSubscription = await _subscribeDirConNotifications(
        session,
        FTMS_CONTROL_POINT_CHARACTERISTIC_UUID,
        _forwardControlPointResponse,
        label: 'FTMS Control Point',
        enable: !blocked,
      );
    } catch (error) {
      print('[DIRCON] FTMS Control Point subscribe failed: $error');
    }

    // The disconnect handler above may have torn this session down while
    // discovery was in flight, which nulls the subscription fields. Assigning
    // them now would leak live subscriptions onto a dead session and bootstrap
    // over it, so unwind and let the caller fall back instead.
    if (_dirConSession != session) {
      await ftmsSubscription?.cancel();
      await machineStatusSubscription?.cancel();
      await controlPointSubscription?.cancel();
      throw StateError('DIRCON session was lost during FTMS setup');
    }
    _dirConFtmsSubscription = ftmsSubscription;
    _dirConMachineStatusSubscription = machineStatusSubscription;
    _dirConControlPointSubscription = controlPointSubscription;
    _machineStatusNotificationsLive = machineStatusSubscription != null;
    _controlPointNotificationsLive = controlPointSubscription != null;

    print('[DIRCON] Connected to $ipAddress');
    if (waitForSetup) {
      await setupConnection(device);
    } else {
      _setupConnectionInBackground(device);
    }
  }

  /// Subscribes to a DIRCON characteristic's notifications, returning null when
  /// the firmware does not expose it and rethrowing when the transport itself
  /// failed.
  ///
  /// Listens *before* enabling notifications: [DirConSession.characteristicNotifications]
  /// filters a broadcast stream with no replay, so a frame the device emits
  /// while the enable request is still in flight would otherwise be dropped.
  ///
  /// With [enable] false the characteristic is still discovered but no
  /// notifications are turned on and nothing is subscribed, which is how a
  /// blocked stream is left for [unblockFtmsNotifications] to pick up later.
  ///
  /// A returned subscription means the stream is genuinely live: enablement
  /// succeeded and the block generation captured on entry is still current. If
  /// a block was taken while enablement was in flight the enable is *undone*
  /// rather than merely abandoned — leaving the device notifying into a socket
  /// nobody reads is the exact state the block exists to prevent.
  Future<StreamSubscription<List<int>>?> _subscribeDirConNotifications(
    DirConSession session,
    String characteristicUuid,
    void Function(List<int>) onData, {
    required String label,
    bool enable = true,
  }) async {
    final generation = _ftmsBlockGeneration;
    final subscription = enable
        ? session.characteristicNotifications(characteristicUuid).listen(onData)
        : null;
    try {
      await session.ensureCharacteristic(
        serviceUuid: ftmsServiceUUID,
        characteristicUuid: characteristicUuid,
        enableNotifications: enable,
      );
      if (!enable) return null;

      if (generation != _ftmsBlockGeneration || isFtmsNotificationsBlocked) {
        await _safeCancel(subscription, label);
        await _disableDirConNotifications(session, characteristicUuid, label);
        return null;
      }

      print('[DIRCON] Subscribed to $label');
      return subscription;
    } catch (error) {
      await _safeCancel(subscription, label);
      // Absent characteristic or dead transport? Liveness is the reliable
      // discriminator, not the exception type: DirConClient raises a bare
      // StateError both for a characteristic the firmware genuinely lacks and
      // for protocol-level request failures, while every transport-fatal path
      // (response timeout, socket error, remote close) invalidates the session
      // first. Downgrading a dead transport to "unavailable" would leave
      // DeviceData reporting DIRCON/connected over a closed socket, which also
      // suppresses the BLE reconnect path in startConnectionMonitor.
      if (!session.isConnected) rethrow;
      print('[DIRCON] $label unavailable: $error');
      return null;
    }
  }

  /// Turns a DIRCON characteristic's notifications off, swallowing failures.
  ///
  /// Every caller is either tearing down or undoing, and both run from paths
  /// that must not throw — a `unawaited` block, or the error handler of an
  /// enable that already failed. A dead session is the disconnect listener's
  /// problem, not this method's.
  Future<void> _disableDirConNotifications(
    DirConSession session,
    String characteristicUuid,
    String label,
  ) async {
    try {
      await session.setNotifications(characteristicUuid, false);
      print('[DIRCON] Disabled $label notifications');
    } catch (error) {
      print('[DIRCON] Could not disable $label notifications: $error');
    }
  }

  /// Publishes a raw FTMS Machine Status frame from either transport.
  ///
  /// Guarded because `dispose()` closes the controller synchronously while the
  /// DIRCON teardown it started is still unwinding, so a late frame can arrive
  /// after the controller is gone.
  void _forwardMachineStatus(List<int> value) {
    if (_isDisposed || _machineStatusController.isClosed) return;
    _machineStatusController.add(value);
  }

  /// Publishes a raw FTMS Control Point response frame from either transport.
  ///
  /// `0x2AD9` is `WRITE | NOTIFY` on this firmware and the response is sent
  /// **unconditionally** — `BLE_Fitness_Machine_Service.cpp:353-354` notifies
  /// without checking for a subscriber, on the reasoning that a write request
  /// is what triggered it. That makes this the most reliable acknowledgement
  /// channel the protocol offers, and strictly more reliable than `0x2ADA`,
  /// which the same handler only re-notifies when the status value actually
  /// *changed* (`:361`) — so a repeated spin-down request produces no Machine
  /// Status frame at all.
  void _forwardControlPointResponse(List<int> value) {
    if (_isDisposed || _controlPointController.isClosed) return;
    _controlPointController.add(value);
  }

  void _setupConnectionInBackground(BluetoothDevice device) {
    unawaited(
      setupConnection(device).catchError((Object error, StackTrace stackTrace) {
        print('[ConnectionSetup] Background setup failed: $error');
      }),
    );
  }

  Future<void> _handleDirConDisconnect(BluetoothDevice device) async {
    final disconnectedAddress = _dirConSession?.host;
    if (disconnectedAddress == null) return;
    _markTransportReconnecting(DeviceTransportKind.dircon);
    await _closeDirCon();
    _dirConSetupComplete = false;
    subscribed = false;
    charReceived.value = false;
    // During the initial connect, connectPreferred owns the fallback: it
    // catches the DIRCON failure and runs the retrying BLE path itself. Racing
    // a second BLE connect from here would duplicate it, exactly as the
    // _initialConnectionInProgress guard in startConnectionMonitor prevents.
    if (isUserDisconnect ||
        _dirConReconnectInProgress ||
        _initialConnectionInProgress) {
      return;
    }

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
    final reusedSession = device.isConnected;
    if (reusedSession) {
      print('[DIRCON][FALLBACK] reusing connected BLE GATT session');
    } else {
      print('[DIRCON][FALLBACK] connecting BLE GATT session');
      await device.connectAndUpdateStream().timeout(
        const Duration(seconds: 10),
      );
    }
    _resetConnectionState();
    // `sweepSettings: false` is what makes this timeout satisfiable. The sweep
    // polls every custom characteristic one round-trip at a time — ~80 s on a
    // fresh session — so a 10 s bound around it could never be met: it fired on
    // every DIRCON->BLE transition, skipping `_markTransportConnected`, the
    // settle decision and `_runReconnectedCallbacks()` below, while the
    // abandoned continuation carried on holding the FTMS notification block.
    // The timeout freed the caller, not the work. Bound only what the fallback
    // actually needs — discovery and the FTMS characteristics — and sweep
    // settings at the end, off this budget.
    //
    // TODO(dircon-calibration-parity): `Future.timeout` does not cancel. A
    // continuation that completes after this 10 s bound keeps mutating shared
    // BLE state (characteristics, subscriptions, the FTMS block) while the
    // fallback bookkeeping below is skipped. Needs generation/epoch gating on
    // every post-await publication. See
    // docs/fallback_setup_cancellation_todo.md.
    await setupConnection(
      device,
      markTransportConnected: false,
      sweepSettings: false,
    ).timeout(const Duration(seconds: 10));
    if (ftmsControlPointCharacteristic == null || !device.isConnected) {
      throw StateError('BLE FTMS Control Point is not ready after DIRCON loss');
    }
    // The FTMS setup inside `setupConnection` above ran while this transport was
    // still `connecting`, so it bailed on `!isTransportActive`. Nothing else
    // will drive it now that the settle block is skipped, so drive it here.
    _markTransportConnected(
      DeviceTransportKind.bluetooth,
      device,
      settle: !reusedSession,
    );
    _dirConFallbackEpoch = _transportStateController.value.epoch;
    print(
      '[DIRCON][FALLBACK] BLE ready epoch=${_transportStateController.value.epoch} '
      'duration=${stopwatch.elapsedMilliseconds}ms '
      'settle=${!reusedSession}; redelivering target.',
    );
    if (reusedSession) {
      await ensureFtmsNotifications(device);
    }
    await _runReconnectedCallbacks();
    // Last, and unawaited: the sweep holds the FTMS notification block for its
    // whole duration, so every stream above has to be live before it starts.
    _sweepSettingsInBackground(device);
  }

  /// Runs the full settings sweep without blocking the caller.
  ///
  /// The sweep is cosmetic to the transport — it repopulates the settings UI —
  /// but it is the slowest thing `setupConnection` does and it holds the FTMS
  /// notification block throughout. A recovery path that needs a live FTMS
  /// stream runs it through here, after the stream is up, rather than inside
  /// its own timeout budget.
  ///
  /// The stopwatch is started before the sweep launches, not after it lands, so
  /// a concurrent [updateCustomCharacter] sees a sweep already in flight
  /// instead of starting a second one against the same characteristics.
  void _sweepSettingsInBackground(BluetoothDevice device) {
    if (isSimulated) return;
    // An interactive FTMS session (a calibration run) holds its own lease on
    // the FTMS notification block. The sweep would take a *second* refcount and
    // keep Machine Status and Control Point responses suspended for its whole
    // ~80 s duration — blinding the run. Coalesce to one pending sweep and run
    // it when the last lease is released; do not drop it, or settings stay
    // stale after every fallback.
    if (_interactiveFtmsSessions.isNotEmpty) {
      _pendingSweepDevice = device;
      print(
        '[transport] settings sweep deferred: interactive FTMS session held',
      );
      return;
    }
    if (_lastRequestStopwatch.isRunning) {
      _lastRequestStopwatch.reset();
    } else {
      _lastRequestStopwatch.start();
    }
    unawaited(
      requestSettings(device).catchError((Object error) {
        print('[transport] background settings sweep failed: $error');
      }),
    );
  }

  /// Live interactive FTMS leases. A `Set` rather than a counter: release is
  /// then naturally idempotent and a double-release is a no-op, which matters
  /// because [CalibrationMonitor] releases from several paths that can overlap
  /// (`_finishRun`, the `start()` failure path, `stopWatching`, `dispose`).
  final Set<Object> _interactiveFtmsSessions = <Object>{};

  /// A settings sweep that [_sweepSettingsInBackground] or an in-flight
  /// [requestSettings] deferred while a lease was held. Coalesced, not queued —
  /// the sweep is idempotent, so one run after the last release is enough.
  BluetoothDevice? _pendingSweepDevice;

  /// Claims a lease on the FTMS notification block for an interactive run.
  ///
  /// While any lease is held the background settings sweep is deferred rather
  /// than run, so it cannot take a second refcount and suspend the FTMS streams
  /// the run is listening on. Also ends the post-connection settle block early
  /// so a fresh-GATT fallback's 10 s window does not stack on top.
  ///
  /// The returned token is the only handle to this lease; pass it to
  /// [endInteractiveFtmsSession]. Holding more than one token per caller is a
  /// bug, but the `Set` makes it survivable.
  Object beginInteractiveFtmsSession(BluetoothDevice device) {
    final token = Object();
    _interactiveFtmsSessions.add(token);
    _endFtmsPostConnectionBlock(device);
    return token;
  }

  /// Releases a lease claimed by [beginInteractiveFtmsSession]. Idempotent: a
  /// token already released, or never issued, is ignored. When the last lease
  /// is released, any sweep deferred while leases were held runs now, against
  /// the device that deferred it.
  void endInteractiveFtmsSession(Object token) {
    if (!_interactiveFtmsSessions.remove(token)) return;
    if (_interactiveFtmsSessions.isNotEmpty) return;
    final pending = _pendingSweepDevice;
    _pendingSweepDevice = null;
    if (pending != null) {
      print('[transport] running deferred settings sweep: last lease released');
      _sweepSettingsInBackground(pending);
    }
  }

  /// Reconnect callbacks are advisory: they refresh UI, re-read RSSI, redeliver
  /// a workout target. Restoring the transport is the transaction; none of this
  /// is part of it. A failing callback must not skip its siblings, and must not
  /// turn a successfully restored link into a failed reconnect attempt — which
  /// is what an unisolated throw here used to do at the `[AutoReconnect]` catch.
  Future<void> _runReconnectedCallbacks([Future<void> Function()? only]) async {
    final callbacks = only != null
        ? <Future<void> Function()>[only]
        : List<Future<void> Function()>.from(_onReconnectedCallbacks);
    for (final callback in callbacks) {
      try {
        await callback();
      } catch (error) {
        print('[Reconnect] callback failed (ignored): $error');
      }
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
    final session = _dirConSession;
    _dirConSession = null;
    // Tearing down a live session is itself a transport transition. Callers
    // that already moved to connecting/reconnecting/disconnected are unaffected
    // by this guard, so no spurious disconnected phase is emitted mid-reconnect.
    if (session != null &&
        _transportStateController.value.transport ==
            DeviceTransportKind.dircon &&
        _transportStateController.value.phase ==
            DeviceTransportPhase.connected) {
      _markTransportDisconnected(explicit: isUserDisconnect);
    }
    _workoutControlLane.onAvailabilityChanged();
    _machineStatusNotificationsLive = false;
    _controlPointNotificationsLive = false;
    await _dirConNotificationSubscription?.cancel();
    _dirConNotificationSubscription = null;
    await _dirConFtmsSubscription?.cancel();
    _dirConFtmsSubscription = null;
    await _dirConMachineStatusSubscription?.cancel();
    _dirConMachineStatusSubscription = null;
    await _dirConControlPointSubscription?.cancel();
    _dirConControlPointSubscription = null;
    await _dirConDisconnectedSubscription?.cancel();
    _dirConDisconnectedSubscription = null;
    if (session != null) await session.close();
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

  /// [settle] false skips the post-connection quiet window. It exists to let a
  /// *newly established* GATT link settle before notifications are enabled; a
  /// session that has been up for minutes and is merely being promoted to the
  /// active transport has nothing to settle, and the block would only leave the
  /// FTMS streams down for another ten seconds.
  void _markTransportConnected(
    DeviceTransportKind transport,
    BluetoothDevice device, {
    bool settle = true,
  }) {
    if (_isDisposed) return;
    final wasAlreadyConnected =
        _transportStateController.value.transport == transport &&
        _transportStateController.value.phase == DeviceTransportPhase.connected;
    _transportStateController.markConnected(transport);
    if (!wasAlreadyConnected && settle) {
      _startFtmsPostConnectionBlock(device);
    } else if (!settle) {
      // A settle block outstanding from the *previous* transport blocks this
      // one's setup until its original deadline expires. Same reasoning as
      // skipping the window: the link has been up, there is nothing to settle,
      // and leaving the block in place is what keeps the FTMS streams down.
      _endFtmsPostConnectionBlock(device);
    }
  }

  void _startFtmsPostConnectionBlock(BluetoothDevice device) {
    _ftmsPostConnectionTimer?.cancel();
    if (!_ftmsPostConnectionBlockActive) {
      _ftmsPostConnectionBlockActive = true;
      unawaited(blockFtmsNotifications());
    }
    _ftmsPostConnectionTimer = Timer(const Duration(seconds: 10), () {
      _ftmsPostConnectionTimer = null;
      _ftmsPostConnectionBlockActive = false;
      unawaited(unblockFtmsNotifications(device));
    });
  }

  /// Releases the settle block now instead of at its deadline. The refcount is
  /// decremented synchronously, so a caller may drive setup immediately after.
  void _endFtmsPostConnectionBlock(BluetoothDevice device) {
    _ftmsPostConnectionTimer?.cancel();
    _ftmsPostConnectionTimer = null;
    if (!_ftmsPostConnectionBlockActive) return;
    _ftmsPostConnectionBlockActive = false;
    print('[FTMS] settle block ended early: transport promoted');
    unawaited(unblockFtmsNotifications(device));
  }

  void _markTransportDisconnected({required bool explicit}) {
    if (_isDisposed) return;
    _transportStateController.markDisconnected(explicit: explicit);
    // A user disconnect ends the wait: nothing is coming back on its own. A
    // *reconnecting* phase deliberately does not, so a waiter whose timeout
    // outlives the reconnect can still be satisfied by the new session.
    if (explicit) _releaseFtmsReadyWaiters();
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

              await _runReconnectedCallbacks(onReconnected);

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

          await _runReconnectedCallbacks(onReconnected);

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
  void _resetConnectionState({bool cancelBleSubscriptions = true}) {
    _setupCoordinator.invalidate();
    final pendingResponse = _pendingCustomResponse;
    if (pendingResponse != null && !pendingResponse.isCompleted) {
      // Release the serialized BLE queue immediately. The next operation will
      // observe the disconnected device instead of waiting for the timeout.
      pendingResponse.complete();
    }
    _pendingCustomResponse = null;
    _pendingCustomResponseReference = null;
    final settingsSnapshotCompleter = _settingsSnapshotCompleter;
    if (settingsSnapshotCompleter != null &&
        !settingsSnapshotCompleter.isCompleted) {
      settingsSnapshotCompleter.completeError(
        StateError('Connection closed during settings snapshot.'),
      );
    }
    _settingsSnapshotCompleter = null;
    _settingsSnapshotDecoder.reset();
    _settingsSnapshotSupport = _SettingsSnapshotSupport.unknown;
    _scanResultDecoder.reset();
    _scanResultStreamSupported = false;
    _customReadRequestCoalescer.clear();
    // The breaker describes a link that no longer exists; the next one starts
    // with a clean record.
    _consecutiveCustomResponseTimeouts = 0;
    customResponsesDegraded.value = false;
    subscribed = false;
    charReceived.value = false;
    _myCharacteristic = null;
    indoorBikeCharacteristic = null;
    ftmsControlPointCharacteristic = null;
    machineStatusCharacteristic = null;
    services = [];
    final notifySubscription = _notifySubscription;
    final ftmsSubscription = _ftmsSubscription;
    final machineStatusSubscription = _machineStatusSubscription;
    final controlPointSubscription = _controlPointSubscription;
    _notifySubscription = null;
    _ftmsSubscription = null;
    _machineStatusSubscription = null;
    _machineStatusNotificationsLive = false;
    _controlPointSubscription = null;
    _controlPointNotificationsLive = false;
    if (cancelBleSubscriptions) {
      unawaited(_safeCancel(notifySubscription, 'custom characteristic'));
      unawaited(_safeCancel(ftmsSubscription, 'FTMS Indoor Bike Data'));
      unawaited(_safeCancel(machineStatusSubscription, 'FTMS Machine Status'));
      unawaited(_safeCancel(controlPointSubscription, 'FTMS Control Point'));
    }
    _inUpdateLoop = false;
    _lastRequestStopwatch.reset();
    _cachedCharacteristicMap = null;
    _applyStreamedFoundDevices(const <BleScanDevice>[]);
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
  StreamSubscription<List<int>>? _controlPointSubscription;
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

  // Raw FTMS Control Point (0x2AD9) response frames. See
  // [_forwardControlPointResponse] for why this channel is more dependable than
  // 0x2ADA for "the device processed my command".
  final StreamController<List<int>> _controlPointController =
      StreamController<List<int>>.broadcast();
  Stream<List<int>> get controlPointResponseStream =>
      _controlPointController.stream;

  /// Whether an FTMS Control Point response listener is published and its
  /// wire-level enable succeeded on the current session.
  bool get controlPointNotificationsLive => _controlPointNotificationsLive;

  /// True when this session fell back from DIRCON to BLE and the BLE transport
  /// it brought up has never delivered a single FTMS frame.
  ///
  /// This is an *observation*, not a diagnosis. No FTMS Indoor Bike Data or
  /// Machine Status has arrived since the fallback, even though the synchronous
  /// custom-characteristic path (settings, shifting, the log stream) is working.
  /// The most common cause is a SmartSpin2k wedged on a half-open DirCon socket:
  /// pulling Wi-Fi sends no FIN, so the device still believes its TCP client is
  /// there and blocks its main loop writing to it. But the same signature is
  /// also produced by failed CCCD setup, a missing Indoor Bike Data
  /// characteristic, or an abandoned setup continuation — the app cannot tell
  /// them apart from the outside.
  ///
  /// For the half-open-socket case, restarting the SmartSpin2k or restoring
  /// Wi-Fi is what clears it. A flow that would otherwise offer a bare retry
  /// should surface the observation and recommend the restart as the first
  /// recovery step.
  ///
  /// Scoped to the fallback's own epoch. A later reconnect publishes a new
  /// epoch, and this stops claiming anything about it.
  ///
  bool get isDirConFallbackSilent =>
      _dirConFallbackEpoch != null &&
      _dirConFallbackEpoch == _transportStateController.value.epoch &&
      isTransportActive &&
      !isDirConConnected &&
      lastFtmsUpdate == null;

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
  final BleScanResultStreamDecoder _scanResultDecoder =
      BleScanResultStreamDecoder();
  bool _scanResultStreamSupported = false;
  final SettingsSnapshotDecoder _settingsSnapshotDecoder =
      SettingsSnapshotDecoder();
  _SettingsSnapshotSupport _settingsSnapshotSupport =
      _SettingsSnapshotSupport.unknown;
  Completer<SettingsSnapshotRequestResult>? _settingsSnapshotCompleter;
  Future<void>? _settingsRequestInFlight;

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

  /// [sweepSettings] false brings the transport up — discovery, characteristics,
  /// notification subscriptions — and leaves the settings poll to the caller.
  /// The sweep is the one unbounded step in here (one round-trip per custom
  /// characteristic, ~80 s cold) and it holds the FTMS notification block for
  /// its whole duration, so a caller under a timeout, or one that needs live
  /// FTMS data first, runs it itself via [_sweepSettingsInBackground].
  Future<void> setupConnection(
    BluetoothDevice device, {
    bool forceRefresh = false,
    bool markTransportConnected = true,
    bool sweepSettings = true,
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
        if (sweepSettings) await requestSettings(device);
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
        sweepSettings: sweepSettings,
      ),
    );
  }

  Future<void> _performConnectionSetup(
    BluetoothDevice device, {
    required int generation,
    required bool forceRefresh,
    bool sweepSettings = true,
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
      // Published state is discarded first and synchronously, before the first
      // await: a setup pass already waiting on setNotifyValue must not be able
      // to publish onto the characteristics this reset just dropped. Bumping
      // the generation is what makes that pass fail its own staleness check
      // rather than reattaching. Matches _resetConnectionState, which clears
      // both subscriptions and the readiness flag together.
      final stale = <StreamSubscription<List<int>>?>[
        _ftmsSubscription,
        _machineStatusSubscription,
        _controlPointSubscription,
      ];
      _ftmsSubscription = null;
      _machineStatusSubscription = null;
      _controlPointSubscription = null;
      _machineStatusNotificationsLive = false;
      _controlPointNotificationsLive = false;
      _ftmsBlockGeneration++;
      for (final subscription in stale) {
        await _safeCancel(subscription, 'FTMS');
      }
      _workoutControlLane.invalidateDelivery();
    }

    await _discoverServices(device, forceRefresh: forceRefresh);
    if (!connectionIsCurrent()) return;
    if (services.length > 1) await _findChar();
    if (!connectionIsCurrent()) return;
    await updateCustomCharacter(device, sweepSettings: sweepSettings);
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
      //
      // Scoped to its own list rather than reusing `characteristics`: that
      // local still holds the firmware service's characteristics, so a device
      // with no FTMS service used to scan *those* — matching nothing, but
      // leaving no way to tell "FTMS absent" from "FTMS scanned and empty".
      List<BluetoothCharacteristic> ftmsCharacteristics =
          const <BluetoothCharacteristic>[];
      for (BluetoothService s in services) {
        if (s.uuid == Guid(ftmsServiceUUID)) {
          ftmsCharacteristics = s.characteristics;
          break;
        }
      }
      for (BluetoothCharacteristic c in ftmsCharacteristics) {
        if (c.uuid == Guid(ftmsIndoorBikeDataUUID)) {
          // Discovery only records the characteristic. Notification lifecycle
          // is owned exclusively by the FTMS block/subscription methods.
          indoorBikeCharacteristic = c;
        }
        if (c.uuid == Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID)) {
          ftmsControlPointCharacteristic = c;
        }
        if (c.uuid == Guid(FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID)) {
          // As above: discovery only records the characteristic. Subscribing
          // here would put Machine Status outside the FTMS notification block,
          // which is exactly what this branch used to do.
          machineStatusCharacteristic = c;
        }
      }

      final capabilities = _ftmsCapabilitiesForEpoch();
      capabilities.discoveryRan = ftmsCharacteristics.isNotEmpty;
      capabilities.machineStatusPresent = machineStatusCharacteristic != null;
      print(
        '[FTMS] discovery epoch=${capabilities.epoch} '
        'ftmsService=${capabilities.discoveryRan} '
        'indoorBike=${indoorBikeCharacteristic != null} '
        'controlPoint=${ftmsControlPointCharacteristic != null} '
        'machineStatus=${capabilities.machineStatusPresent}',
      );

      charReceived.value = _myCharacteristic != null;
      _workoutControlLane.onAvailabilityChanged();
    } catch (e) {
      print('[BLE] characteristic discovery failed: $e');
      charReceived.value = false;
      _workoutControlLane.onAvailabilityChanged();
    }
  }

  /// What FTMS discovery found on one connection epoch.
  ///
  /// A missed 0x2ADA has to be re-probed exactly once per connection. Never
  /// re-probing makes the miss permanent for the life of the link — which is the
  /// A6 failure mode, since neither `needsBootstrap` nor
  /// [_ensureFtmsNotifications] keys rediscovery off Machine Status. Re-probing
  /// unconditionally would re-run service discovery forever on firmware that
  /// legitimately has no Machine Status characteristic.
  _FtmsCapabilities _ftmsCapabilitiesForEpoch() {
    final epoch = _transportStateController.value.epoch;
    final existing = _ftmsCapabilities;
    if (existing != null && existing.epoch == epoch) return existing;
    return _ftmsCapabilities = _FtmsCapabilities(epoch);
  }

  ///Data Helpers****************************************************************

  bool subscribed = false;
  bool _mtuRequestedForConnection = false;
  final _lastRequestStopwatch = Stopwatch();
  // only used as a flag to prevent multiple concurrent instances of updateCustomCharacter
  bool _inUpdateLoop = false;

  /// [sweepSettings] false skips the settings poll only; the subscriptions and
  /// the MTU bump above it still happen. See [setupConnection].
  Future updateCustomCharacter(
    BluetoothDevice device, {
    bool sweepSettings = true,
  }) async {
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
        await ensureFtmsNotifications(device);
      }
      if (_myCharacteristic != null && !_myCharacteristic!.isNotifying) {
        await _queueBleOperation(() => _myCharacteristic!.setNotifyValue(true));
      }
      // Skipping deliberately leaves the stopwatch alone: the caller owns the
      // sweep now, and starting it here would pretend one just ran and suppress
      // the next due one.
      if (sweepSettings) {
        if (!_lastRequestStopwatch.isRunning) {
          await requestSettings(device);
          _lastRequestStopwatch.start();
        } else if (_lastRequestStopwatch.elapsed > Duration(seconds: 5)) {
          _lastRequestStopwatch.reset();
          await requestSettings(device);
        }
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

  /// Serializes FTMS notification setup.
  ///
  /// Four screens call [ensureFtmsNotifications] unawaited from `initState`,
  /// and the health watchdog, the readiness wait and the unblock path all drive
  /// it too, so two passes can genuinely overlap. Each pass cancels the
  /// subscription it was *handed* and then publishes its own, so an overlap
  /// ends with both listeners created and only the last published — the other
  /// keeps decoding Indoor Bike Data and forwarding Machine Status with nothing
  /// able to cancel it.
  ///
  /// Queued rather than coalesced: a caller arriving mid-pass still needs a
  /// pass of its own, because the block generation may have moved since the
  /// in-flight one captured it.
  Future<void> _ftmsSetupQueue = Future<void>.value();

  /// Brings both FTMS notification streams up over BLE: Indoor Bike Data and
  /// Machine Status `0x2ADA`.
  ///
  /// The two are attempted independently — firmware that exposes one but not
  /// the other must still deliver the one it has, and a failure on either must
  /// not decide anything about the other.
  Future<void> ensureFtmsNotifications(BluetoothDevice device) {
    final pass = _ftmsSetupQueue.then((_) => _ensureFtmsNotifications(device));
    // The queue must outlive a failing pass, or one error wedges every later
    // caller. The error still reaches whoever awaited this call.
    _ftmsSetupQueue = pass.catchError((Object _) {});
    return pass;
  }

  Future<void> _ensureFtmsNotifications(BluetoothDevice device) async {
    // A queued pass can start well after it was requested.
    if (_isDisposed) {
      print('[FTMS] setup skipped: disposed');
      return;
    }
    if (isFtmsNotificationsBlocked) {
      print('[FTMS] setup skipped: blocked($_ftmsNotificationBlocks)');
      return;
    }

    // The DIRCON session subscribes to FTMS during transport setup. Avoid
    // attempting BLE service discovery merely because a screen wants to make
    // sure the live stream is active.
    if (!isTransportActive || isDirConConnected) {
      final state = _transportStateController.value;
      print(
        '[FTMS] setup skipped: '
        '${isDirConConnected ? 'dircon owns FTMS' : 'transport inactive'} '
        '(${state.transport.name}/${state.phase.name})',
      );
      return;
    }

    // Both characteristics come out of the same `_findChar` pass, so Indoor
    // Bike Data being present is proof discovery has run. Keying off a null
    // Machine Status instead would re-discover on every call for firmware that
    // simply does not have it.
    bool discoveredThisPass = false;
    if (indoorBikeCharacteristic == null) {
      await _discoverServices(device);
      if (isFtmsNotificationsBlocked) return;
      if (services.length > 1) {
        await _findChar();
        discoveredThisPass = true;
      }
    }

    // ...which leaves the case discovery cannot distinguish on its own: Indoor
    // Bike Data present, Machine Status absent. That is either firmware without
    // 0x2ADA or a discovery pass that missed it, and the difference decides
    // whether calibration has an evidence channel. Spend exactly one forced
    // re-probe per connection epoch settling it; after that the answer is
    // recorded and believed.
    final capabilities = _ftmsCapabilitiesForEpoch();
    if (machineStatusCharacteristic == null &&
        !capabilities.reprobed &&
        !discoveredThisPass) {
      capabilities.reprobed = true;
      print(
        '[FTMS] Machine Status absent on epoch ${capabilities.epoch}; '
        're-probing services once',
      );
      await _discoverServices(device, forceRefresh: true);
      if (_isDisposed || isFtmsNotificationsBlocked || !isTransportActive) {
        return;
      }
      if (services.length > 1) {
        await _findChar();
      }
      print(
        '[FTMS] re-probe result: machineStatus='
        '${machineStatusCharacteristic != null}',
      );
    }

    var stale = await _subscribeFtmsCharacteristics(device);

    // The other way discovery goes wrong, and the one Run D exposed: the
    // characteristic object is *not* null, so the branch above never fires, but
    // the platform's own service cache no longer contains 0x1826 and the enable
    // comes back `primary service not found '1826'`. Cached characteristics
    // outlive the services they were found in across a reconnect, so the only
    // repair is to discover again and re-subscribe against the fresh objects.
    //
    // Deliberately drawing on the same one-per-epoch budget: both branches are
    // asking the same question of the same connection, and a device that keeps
    // failing the enable must not be able to drive service discovery in a loop.
    if (stale && !capabilities.reprobed) {
      capabilities.reprobed = true;
      print(
        '[FTMS] enable failed against a stale service cache on epoch '
        '${capabilities.epoch}; re-probing services once',
      );
      await _discoverServices(device, forceRefresh: true);
      if (_isDisposed || isFtmsNotificationsBlocked || !isTransportActive) {
        return;
      }
      if (services.length > 1) {
        await _findChar();
      }
      stale = await _subscribeFtmsCharacteristics(device);
      print(
        '[FTMS] stale-cache re-probe result: '
        '${stale ? 'enable still failing' : 'recovered'}',
      );
    }
  }

  /// Subscribes the three FTMS notification characteristics, returning whether
  /// any enable failed in a way that points at stale platform discovery.
  ///
  /// All three are attempted regardless of what the others do — firmware that
  /// exposes one but not another must still deliver what it has.
  Future<bool> _subscribeFtmsCharacteristics(BluetoothDevice device) async {
    var stale = false;

    stale |= await _subscribeBleNotifications(
      device,
      indoorBikeCharacteristic,
      _decodeIndoorBikeData,
      label: 'FTMS Indoor Bike Data',
      publish: (subscription) => _ftmsSubscription = subscription,
      previous: _ftmsSubscription,
    );

    stale |= await _subscribeBleNotifications(
      device,
      machineStatusCharacteristic,
      _forwardMachineStatus,
      label: 'FTMS Machine Status',
      publish: (subscription) {
        _machineStatusSubscription = subscription;
        _machineStatusNotificationsLive = subscription != null;
      },
      previous: _machineStatusSubscription,
    );

    // The control point's responses. Not part of the readiness verdict — that
    // question is specifically about 0x2ADA — but the channel calibration's
    // acknowledgement stage trusts most. See [_forwardControlPointResponse].
    stale |= await _subscribeBleNotifications(
      device,
      ftmsControlPointCharacteristic,
      _forwardControlPointResponse,
      label: 'FTMS Control Point',
      publish: (subscription) {
        _controlPointSubscription = subscription;
        _controlPointNotificationsLive = subscription != null;
      },
      previous: _controlPointSubscription,
    );

    return stale;
  }

  /// Whether a failed CCCD write says the platform's service cache is stale
  /// rather than that the device refused.
  ///
  /// Both the Darwin and Android plugins phrase this identically —
  /// `primary service not found '<uuid>'`, `secondary service not found`,
  /// `characteristic not found in service` — raised when their own
  /// `locateCharacteristic` walks a cached service list that no longer holds
  /// the service. Matching on message text is unlovely, but the plugins give a
  /// bare `PlatformException`/`FlutterBluePlusException` with no code that
  /// separates this from a device-side refusal.
  static bool _looksLikeStaleDiscovery(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('service not found') ||
        text.contains('characteristic not found in service');
  }

  /// Upper bound on a single CCCD write. Without it one wedged enable holds the
  /// shared transport queue for as long as the platform takes to give up, which
  /// is what turns a stalled device into a stalled app.
  static const Duration _notifyEnableTimeout = Duration(seconds: 5);

  /// Subscribes one BLE FTMS characteristic, listening *before* enabling.
  ///
  /// The mirror image of [_subscribeDirConNotifications], and for the same
  /// reason: the device can emit a frame the moment the CCCD is written, and
  /// `onValueReceived` is a broadcast stream with no replay, so a listener
  /// attached afterwards silently loses it.
  ///
  /// If the block generation moves while enablement is in flight, the enable is
  /// *undone* rather than merely abandoned. Returning early would leave the
  /// characteristic notifying with nothing listening — a block that had seen
  /// `isNotifying == false` would have scheduled no disable for it.
  ///
  /// Returns true when the enable failed in a way that points at a stale
  /// platform service cache, which the caller can repair. Every other outcome —
  /// success, an absent characteristic, a held block, a device-side refusal —
  /// returns false, because none of them is fixed by discovering again.
  Future<bool> _subscribeBleNotifications(
    BluetoothDevice device,
    BluetoothCharacteristic? characteristic,
    void Function(List<int>) onData, {
    required String label,
    required void Function(StreamSubscription<List<int>>?) publish,
    StreamSubscription<List<int>>? previous,
  }) async {
    if (characteristic == null) {
      print('[BLE] $label unavailable: characteristic not discovered');
      // Not merely "nothing to do": a previous connection's subscription may
      // still be published against a characteristic this pass no longer has,
      // and for Machine Status `publish` is what maintains
      // _machineStatusNotificationsLive — the one field
      // awaitFtmsNotificationsReady answers from. Returning early here is how
      // calibration gets told the stream is ready with no listener behind it.
      await _safeCancel(previous, label);
      publish(null);
      return false;
    }
    if (isFtmsNotificationsBlocked) {
      print(
        '[BLE] $label subscribe skipped: blocked($_ftmsNotificationBlocks)',
      );
      return false;
    }

    final generation = _ftmsBlockGeneration;
    await _safeCancel(previous, label);
    publish(null);

    final subscription = characteristic.onValueReceived.listen(
      onData,
      onError: (Object e) => print('[BLE] Error in $label subscription: $e'),
    );

    bool enabled = false;
    // Already-notifying is the invisible case: no CCCD write reaches the wire,
    // so a serial capture shows nothing at all for this characteristic even
    // though the subscription is healthy.
    final needsWire = !characteristic.isNotifying;
    try {
      if (needsWire) {
        // The timeout goes *inside* the queued operation, not around the queue
        // future: bounding the wait alone would free this caller while the slot
        // stayed occupied by the wedged write.
        await _queueBleOperation(
          () =>
              characteristic.setNotifyValue(true).timeout(_notifyEnableTimeout),
        );
      }
      enabled = true;
    } catch (e) {
      await _safeCancel(subscription, label);
      final stale = _looksLikeStaleDiscovery(e);
      print(
        '[BLE] failed to enable $label notify'
        '${stale ? ' (stale service cache)' : ''}: $e',
      );
      return stale;
    }

    if (_isDisposed ||
        generation != _ftmsBlockGeneration ||
        isFtmsNotificationsBlocked) {
      print(
        '[BLE] $label subscribe discarded: '
        '${_isDisposed
            ? 'disposed'
            : generation != _ftmsBlockGeneration
            ? 'generation $generation != $_ftmsBlockGeneration'
            : 'blocked($_ftmsNotificationBlocks)'}',
      );
      await _safeCancel(subscription, label);
      if (enabled) await _disableBleNotifications(characteristic, label);
      return false;
    }

    device.cancelWhenDisconnected(subscription);
    publish(subscription);
    print(
      '[BLE] $label subscribed '
      '(${needsWire ? 'CCCD write issued' : 'already notifying, no CCCD write'})',
    );
    return false;
  }

  /// Cancels a notification subscription without letting a failing cancel cost
  /// the rest of a teardown.
  ///
  /// The block and unblock paths run `unawaited` from the post-connection
  /// timer, and both walk several subscriptions in sequence. One erroring
  /// `cancel()` must not skip the subscriptions and wire disables behind it.
  Future<void> _safeCancel(
    StreamSubscription<List<int>>? subscription,
    String label,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } catch (error) {
      print('[FTMS] Cancelling $label notifications failed: $error');
    }
  }

  /// Turns a BLE characteristic's notifications off, swallowing failures for
  /// the same reason [_disableDirConNotifications] does.
  ///
  /// Deliberately not gated on `isNotifying`, which reads a cached CCCD
  /// descriptor value rather than asking the device. A block that skipped a
  /// disable because the cache said "already quiet" is exactly the failure this
  /// is meant to rule out, and a redundant CCCD write on two characteristics is
  /// a cheap price for the guarantee. The DIRCON side has never had such a
  /// guard, so this also puts the two transports on the same footing.
  Future<void> _disableBleNotifications(
    BluetoothCharacteristic characteristic,
    String label,
  ) async {
    try {
      await _queueBleOperation(() => characteristic.setNotifyValue(false));
    } catch (e) {
      print('[BLE] Could not disable $label notifications: $e');
    }
  }

  /// Suspends both FTMS notification streams on whichever transport is live.
  ///
  /// Refcounted: OTA, the settings bootstrap, and the post-connection window
  /// each hold one, and only the outermost release brings the streams back.
  ///
  /// Every cancellation and every wire operation is guarded individually. This
  /// runs `unawaited` from [_startFtmsPostConnectionBlock], so it must not
  /// complete with an error on any path — and one failing `cancel()` must not
  /// cost the remaining teardown.
  Future<void> blockFtmsNotifications() async {
    _ftmsNotificationBlocks++;
    if (_ftmsNotificationBlocks > 1) return;

    _ftmsReadyCompleter ??= Completer<void>();
    final generation = ++_ftmsBlockGeneration;
    _machineStatusNotificationsLive = false;

    _controlPointNotificationsLive = false;

    final subscriptions = <StreamSubscription<List<int>>?>[
      _ftmsSubscription,
      _machineStatusSubscription,
      _controlPointSubscription,
      _dirConFtmsSubscription,
      _dirConMachineStatusSubscription,
      _dirConControlPointSubscription,
    ];
    _ftmsSubscription = null;
    _machineStatusSubscription = null;
    _controlPointSubscription = null;
    _dirConFtmsSubscription = null;
    _dirConMachineStatusSubscription = null;
    _dirConControlPointSubscription = null;
    for (final subscription in subscriptions) {
      await _safeCancel(subscription, 'FTMS');
    }

    bool stillBlocking() =>
        generation == _ftmsBlockGeneration && isFtmsNotificationsBlocked;

    final session = _dirConSession;
    if (isDirConConnected && session != null) {
      for (final (uuid, label) in _ftmsNotificationCharacteristics) {
        if (!stillBlocking()) return;
        await _disableDirConNotifications(session, uuid, label);
      }
      return;
    }

    for (final (characteristic, label) in _bleFtmsNotificationCharacteristics) {
      if (!stillBlocking()) return;
      if (characteristic == null) continue;
      await _disableBleNotifications(characteristic, label);
    }
  }

  /// The BLE characteristics the FTMS notification block owns, in setup order.
  /// A getter rather than a field: these are re-assigned by every `_findChar`.
  List<(BluetoothCharacteristic?, String)>
  get _bleFtmsNotificationCharacteristics => [
    (indoorBikeCharacteristic, 'FTMS Indoor Bike Data'),
    (machineStatusCharacteristic, 'FTMS Machine Status'),
    (ftmsControlPointCharacteristic, 'FTMS Control Point'),
  ];

  /// Releases one block. The outermost release brings both streams back.
  Future<void> unblockFtmsNotifications(BluetoothDevice device) async {
    if (_ftmsNotificationBlocks == 0) return;
    _ftmsNotificationBlocks--;
    if (_ftmsNotificationBlocks > 0) return;

    _ftmsBlockGeneration++;
    // Whether a setup pass actually ran on a live transport. A DIRCON pass that
    // runs and fails still counts: `unavailable` is then the truth. Only a pass
    // that never happened at all must stay silent.
    bool setupAttempted = true;
    final dirConSession = _dirConSession;
    if (isDirConConnected && dirConSession != null) {
      // Same helper the initial setup uses, so the resubscribe also listens
      // before enabling and a firmware variant without a characteristic reports
      // rather than throwing out of the post-connection timer that calls this.
      for (final (uuid, label) in _ftmsNotificationCharacteristics) {
        StreamSubscription<List<int>>? subscription;
        try {
          subscription = await _subscribeDirConNotifications(
            dirConSession,
            uuid,
            _dirConFtmsHandlerFor(uuid),
            label: label,
          );
        } catch (error) {
          // A dead transport, not an absent characteristic — the helper only
          // rethrows once the session is invalid. Abandon the whole pass:
          // subscribing the other characteristic to a closed session achieves
          // nothing. This method runs unawaited from the post-connection timer
          // and must not raise into it.
          print('[DIRCON] FTMS resubscribe abandoned: $error');
          // The disconnect listener normally owns the failover, but it cannot
          // be relied on here: `DirConClient.close()` invalidates the session
          // without publishing on `disconnected`, and `_closeWithError` is
          // one-shot via `_disconnectEmitted`. On those paths `isConnected` is
          // the only evidence, and leaving it unread would strand DeviceData
          // reporting DIRCON/connected over a dead socket — which also wedges
          // BLE recovery, since startConnectionMonitor short-circuits on
          // isDirConConnected.
          if (_dirConSession == dirConSession && !dirConSession.isConnected) {
            // Unawaited because requestSettings awaits this method during the
            // settings bootstrap and OTA; a BLE reconnect must not block it.
            // The guards in _handleDirConDisconnect make a second, concurrent
            // invocation from the real listener harmless.
            unawaited(
              _handleDirConDisconnect(device).catchError(
                (Object e) =>
                    print('[DIRCON] post-resubscribe teardown failed: $e'),
              ),
            );
          }
          break;
        }
        // The session may have been replaced while enablement was in flight;
        // the block-generation race is handled inside the helper.
        if (_dirConSession != dirConSession) {
          await _safeCancel(subscription, label);
          break;
        }
        _publishDirConFtmsSubscription(uuid, subscription);
      }
    } else if (isTransportActive) {
      await ensureFtmsNotifications(device);
    } else {
      // The DIRCON->BLE fallback releases the settings-bootstrap block while
      // the transport is still `connecting`, so this is a real state, not a
      // defensive branch. `ensureFtmsNotifications` would bail on
      // `!isTransportActive` and the release below would then hand every waiter
      // an `unavailable` for a setup pass that never ran.
      setupAttempted = false;
      print(
        '[FTMS] unblock: no setup attempted, transport inactive '
        '(${_transportStateController.value.transport.name}/'
        '${_transportStateController.value.phase.name}); '
        'leaving readiness waiters pending',
      );
    }

    // A block taken while the resubscribe was in flight invalidates this
    // attempt: leave the waiters pending for that cycle's own release rather
    // than reporting a readiness the block just revoked. Likewise, a pass that
    // never ran must not be reported as a readiness verdict — the waiter's own
    // deadline bounds the wait, and _markTransportDisconnected(explicit: true)
    // releases it if the transport is never coming back.
    if (_ftmsNotificationBlocks == 0 && setupAttempted) {
      _releaseFtmsReadyWaiters();
    }
  }

  /// The characteristics the FTMS notification block owns, in setup order.
  static final List<(String, String)> _ftmsNotificationCharacteristics = [
    (ftmsIndoorBikeDataUUID, 'FTMS Indoor Bike Data'),
    (FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID, 'FTMS Machine Status'),
    (FTMS_CONTROL_POINT_CHARACTERISTIC_UUID, 'FTMS Control Point'),
  ];

  /// Not a `switch`: the UUID constants are `final`, not `const`, so they
  /// cannot be pattern-matched.
  void Function(List<int>) _dirConFtmsHandlerFor(String uuid) {
    if (uuid == ftmsIndoorBikeDataUUID) return _decodeIndoorBikeData;
    if (uuid == FTMS_CONTROL_POINT_CHARACTERISTIC_UUID) {
      return _forwardControlPointResponse;
    }
    return _forwardMachineStatus;
  }

  void _publishDirConFtmsSubscription(
    String uuid,
    StreamSubscription<List<int>>? subscription,
  ) {
    if (uuid == ftmsIndoorBikeDataUUID) {
      _dirConFtmsSubscription = subscription;
    } else if (uuid == FTMS_CONTROL_POINT_CHARACTERISTIC_UUID) {
      _dirConControlPointSubscription = subscription;
      _controlPointNotificationsLive = subscription != null;
    } else {
      _dirConMachineStatusSubscription = subscription;
      _machineStatusNotificationsLive = subscription != null;
    }
  }

  void _releaseFtmsReadyWaiters() {
    final completer = _ftmsReadyCompleter;
    _ftmsReadyCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Waits until FTMS Machine Status is genuinely usable, and reports why if it
  /// is not.
  ///
  /// "Ready" is not "the block count reached zero": the characteristic may be
  /// absent from this firmware, its enable may have failed, or the transport
  /// may have dropped. It means a listener is published and its wire-level
  /// enable succeeded on the current session.
  ///
  /// Never touches the refcount. A caller waiting on this must not be able to
  /// revoke a block that OTA or the settings bootstrap is holding.
  /// One deadline is spent across both concerns — waiting out a held block and
  /// driving setup — so the caller's budget bounds the whole call. The previous
  /// `if blocked / else if not-live` shape could return `unavailable` having
  /// never attempted setup at all: a block that drained while the transport was
  /// still `connecting` released the waiter, and the fall-through then reported
  /// on a pass that never ran.
  ///
  /// Note what the deadline does and does not buy. Timing out
  /// [ensureFtmsNotifications] frees *this* caller; it does not cancel the pass,
  /// which stays on `_ftmsSetupQueue` and may still hold a transport-queue slot.
  /// A UI timeout cannot repair a poisoned shared queue — the bounded
  /// `setNotifyValue` in [_subscribeBleNotifications] and the
  /// `_ftmsBlockGeneration` staleness check are what keep a wedged pass from
  /// holding the queue forever or publishing onto a superseded connection.
  Future<FtmsNotificationsReadiness> awaitFtmsNotificationsReady(
    BluetoothDevice device, {
    required Duration timeout,
  }) async {
    if (_isDisposed) return FtmsNotificationsReadiness.disposed;

    final deadline = DateTime.now().add(timeout);
    Duration remaining() => deadline.difference(DateTime.now());

    // A block retaken while setup was in flight sends us round again. Capped so
    // a pathological block/unblock cycle cannot spin here; the deadline is the
    // real bound.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (isFtmsNotificationsBlocked) {
        final budget = remaining();
        if (budget <= Duration.zero) return FtmsNotificationsReadiness.timedOut;
        final completer = (_ftmsReadyCompleter ??= Completer<void>());
        try {
          await completer.future.timeout(budget);
        } on TimeoutException {
          return FtmsNotificationsReadiness.timedOut;
        }
        if (_isDisposed) return FtmsNotificationsReadiness.disposed;
      }

      if (_machineStatusNotificationsLive) break;

      // Unblocked but not yet subscribed is a real state: screens kick setup off
      // unawaited, so this can be the exact moment a caller asks. Drive it
      // rather than reporting a readiness that only happens to be pending.
      if (!isFtmsNotificationsBlocked) {
        final budget = remaining();
        if (budget <= Duration.zero) return FtmsNotificationsReadiness.timedOut;
        try {
          await ensureFtmsNotifications(device).timeout(budget);
        } on TimeoutException {
          return FtmsNotificationsReadiness.timedOut;
        }
        if (_isDisposed) return FtmsNotificationsReadiness.disposed;
      }

      // Setup ran to completion and nothing retook a block: this verdict is
      // final, whatever it is.
      if (!isFtmsNotificationsBlocked) break;
    }

    return _machineStatusNotificationsLive && isTransportActive
        ? FtmsNotificationsReadiness.ready
        : FtmsNotificationsReadiness.unavailable;
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
    if (isFtmsNotificationsBlocked) return;
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
    //
    // This branch has to recycle, not merely ensure. `ensureFtmsNotifications`
    // is a no-op once `isNotifying` is true, and a connection that has never
    // delivered a frame is very often exactly that: subscribed on both ends,
    // silent anyway. In Run C it ran four times and logged
    // `subscribed (already notifying, no CCCD write)` each time, repairing
    // nothing — the same "repairs the wire and nothing else" trap
    // [_recycleFtmsNotifications] was written to close for the stalled branch,
    // just on the other side of the null check. Note the stalled branch below
    // cannot cover for it: `lastFtmsUpdate` stays null forever on a connection
    // that never delivered, so it is never reached.
    if (lastFtmsUpdate == null) {
      if (!recentlyTriedRecovery) {
        _ftmsRecoveryInProgress = true;
        _lastFtmsRecoveryAttempt = now;
        try {
          // Nothing to cycle before discovery has produced the characteristics;
          // an ensure pass is what runs discovery in the first place.
          if (indoorBikeCharacteristic != null && device.isConnected) {
            // The stalled branch below announces itself; this one used to be
            // silent, which made a watchdog that ran and repaired nothing
            // indistinguishable in the log from one that never ran.
            print(
              'FTMS has delivered nothing since this connection came up. '
              'Recycling notifications...',
            );
            await _recycleFtmsNotifications(device);
          } else {
            await ensureFtmsNotifications(device);
          }
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
          await _recycleFtmsNotifications(device);
          // Deliberately *not* resetting lastFtmsUpdate here. Recovery
          // returning is not evidence that data is flowing —
          // ensureFtmsNotifications returns normally after an individual enable
          // failure — and a reset would report a recovery that did not happen
          // and push the next attempt out by a full watchdog period.
          // _lastFtmsRecoveryAttempt already supplies the cooldown that stops
          // this becoming a tight loop; the timestamp stays stale until real
          // Indoor Bike Data arrives and _decodeIndoorBikeData moves it.
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

  /// Cycles both FTMS notification streams off and back on.
  ///
  /// The old recovery wrote the CCCD on `indoorBikeCharacteristic` directly.
  /// That repaired the *wire* and nothing else: it never republished
  /// `_ftmsSubscription`, so a stream whose Dart listener had been cancelled
  /// came back enabled with nobody reading it — a permanent stall/recover loop —
  /// and it never touched Machine Status at all, leaving calibration's only
  /// evidence channel down.
  ///
  /// Going through [ensureFtmsNotifications] keeps the wire-level kick and adds
  /// the listener republish, symmetrically for both characteristics.
  Future<void> _recycleFtmsNotifications(BluetoothDevice device) async {
    for (final (characteristic, label) in _bleFtmsNotificationCharacteristics) {
      if (characteristic == null) continue;
      await _disableBleNotifications(characteristic, label);
    }

    await Future.delayed(const Duration(milliseconds: 200));

    if (!device.isConnected) {
      print('[FTMS Recovery] Device disconnected during recovery.');
      _triggerReconnect(device);
      return;
    }

    await ensureFtmsNotifications(device);
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

  // Request all settings. Current firmware returns one chunked 0x31 snapshot;
  // only firmware that explicitly rejects 0x31 uses the legacy per-reference
  // sweep below.
  Future<void> requestSettings(BluetoothDevice device) {
    if (isSimulated) return Future<void>.value();

    // Calibration owns the interactive FTMS channels while its lease is held.
    // Defer even the shorter snapshot transfer so background bootstrap traffic
    // cannot contend with the run.
    if (_interactiveFtmsSessions.isNotEmpty) {
      print(
        '[transport] settings sweep deferred: interactive FTMS session held',
      );
      _pendingSweepDevice = device;
      return Future<void>.value();
    }

    final existing = _settingsRequestInFlight;
    if (existing != null) return existing;

    final request = _requestSettings(device);
    _settingsRequestInFlight = request;
    void clearRequest() {
      if (identical(_settingsRequestInFlight, request)) {
        _settingsRequestInFlight = null;
      }
    }

    request.then<void>((_) => clearRequest(), onError: (_) => clearRequest());
    return request;
  }

  Future<void> _requestSettings(BluetoothDevice device) async {
    await blockFtmsNotifications();
    try {
      if (customResponsesDegraded.value) {
        print('[transport] settings sweep abandoned: link degraded');
        return;
      }

      if (_settingsSnapshotSupport != _SettingsSnapshotSupport.unsupported) {
        try {
          final result = await requestSettingsWithSnapshotFallback(
            requestSnapshot: () => _requestSettingsSnapshot(device),
            requestIndividually: () async {
              _settingsSnapshotSupport = _SettingsSnapshotSupport.unsupported;
              await _requestSettingsIndividually(device);
            },
          );
          if (result == SettingsSnapshotRequestResult.supported) {
            _settingsSnapshotSupport = _SettingsSnapshotSupport.supported;
          }
          return;
        } catch (error) {
          // A timeout, malformed chunk, or transport failure does not prove the
          // command is unsupported. Retry 0x31 on the next settings refresh.
          print('[transport] settings snapshot failed: $error');
          if (_interactiveFtmsSessions.isNotEmpty) {
            _pendingSweepDevice = device;
            print(
              '[transport] settings sweep yielded: interactive FTMS session started',
            );
          }
          return;
        }
      }

      await _requestSettingsIndividually(device);
    } finally {
      await unblockFtmsNotifications(device);
    }
  }

  Future<SettingsSnapshotRequestResult> _requestSettingsSnapshot(
    BluetoothDevice device,
  ) async {
    _settingsSnapshotDecoder.reset();
    final completer = Completer<SettingsSnapshotRequestResult>();
    _settingsSnapshotCompleter = completer;
    try {
      await writeCustomCharacteristic(device, const [
        0x01,
        settingsSnapshotReference,
      ]);
      return await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      if (identical(_settingsSnapshotCompleter, completer)) {
        _settingsSnapshotCompleter = null;
      }
    }
  }

  Future<void> _requestSettingsIndividually(BluetoothDevice device) async {
    if (_interactiveFtmsSessions.isNotEmpty) {
      print(
        '[transport] settings sweep yielded: interactive FTMS session started',
      );
      _pendingSweepDevice = device;
      return;
    }

    var unconfirmed = 0;
    for (final c in customCharacteristic) {
      if (!configAppCompatibleFirmware && c["vName"] == saveVname) continue;
      if (c["vName"] == BLE_logStreamVname) continue;

      if (customResponsesDegraded.value) {
        print('[transport] settings sweep abandoned: link degraded');
        break;
      }
      if (_interactiveFtmsSessions.isNotEmpty) {
        print(
          '[transport] settings sweep yielded: interactive FTMS session started',
        );
        _pendingSweepDevice = device;
        break;
      }

      try {
        await writeCustomCharacteristic(device, [
          0x01,
          int.parse(c["reference"]),
        ]);
      } on TransportResponseUnconfirmed {
        unconfirmed++;
      } catch (error) {
        print('[transport] settings sweep stopped: $error');
        break;
      }
    }
    if (unconfirmed > 0) {
      print('[transport] settings sweep: $unconfirmed reads unconfirmed');
    }
  }

  /// Requests only editable settings belonging to [settingType]. Cached values
  /// remain available while the authoritative values arrive from the device.
  Future<void> requestSettingsForType(
    BluetoothDevice device,
    SettingType settingType,
  ) async {
    if (isSimulated) return;

    var unconfirmed = 0;
    for (final c in customCharacteristic) {
      if (c["isSetting"] != true || c["settingType"] != settingType) {
        continue;
      }
      if (customResponsesDegraded.value) {
        print('[transport] settings request abandoned: link degraded');
        break;
      }

      try {
        await writeCustomCharacteristic(device, [
          0x01,
          int.parse(c["reference"]),
        ]);
      } on TransportResponseUnconfirmed {
        unconfirmed++;
      } catch (e) {
        print('[transport] settings request stopped: $e');
        break;
      }
    }
    if (unconfirmed > 0) {
      print('[transport] settings request: $unconfirmed reads unconfirmed');
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

  /// A legacy UI-feedback wrapper retained for compatibility: it forwards to
  /// [writeToSS2kStrict] and turns any transport fault into a snackbar. Not a
  /// principled presentation boundary — a caller that needs to know whether the
  /// write landed must call [writeToSS2kStrict] and handle
  /// [TransportNotConnected] / [TransportResponseUnconfirmed] itself.
  Future<void> writeToSS2k(
    BluetoothDevice device,
    Map c, {
    String s = "",
  }) async {
    try {
      await writeToSS2kStrict(device, c, s: s);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  /// Serialises [c] and writes it to the custom characteristic, propagating
  /// every transport fault. No UI. See [writeToSS2k] for the tolerant wrapper.
  Future<void> writeToSS2kStrict(
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

          // Write the data to the device. A failed row propagates: a
          // half-written power table was never a good outcome.
          await writeCustomCharacteristic(device, rowToSend);
        }
        // Every row has been sent. Returning here — rather than breaking — skips
        // the trailing generic write below, which would otherwise put an extra
        // header-only [0x02, reference] packet on the wire; an unconfirmed
        // response to that packet can now make a completed upload report
        // failure.
        return;

      default:
      //value = [0xff];
    }
    // A setting the user just changed, or a run enabling its log stream.
    // Something is waiting on it, unlike the background settings sweep.
    await writeCustomCharacteristic(
      device,
      value,
      priority: TransportOpPriority.interactive,
    );
  }

  final List<_PendingTransportOp> _pendingTransportOps = [];
  bool _transportPumpRunning = false;
  DateTime? _lastBleWriteCompletedAt;
  Completer<void>? _pendingCustomResponse;
  int? _pendingCustomResponseReference;
  final CustomReadRequestCoalescer _customReadRequestCoalescer =
      CustomReadRequestCoalescer();
  static const Duration _customResponseTimeout = Duration(seconds: 2);

  /// How many consecutive unanswered requests it takes to call the link
  /// degraded. Two is within normal jitter; three in a row is a pattern.
  static const int _customResponseFailureThreshold = 3;
  int _consecutiveCustomResponseTimeouts = 0;

  /// True while the device has stopped answering custom-characteristic
  /// requests.
  ///
  /// A `ValueNotifier` because [DeviceData] is a plain class, not a
  /// `ChangeNotifier` — the same idiom as `transportRevision` and
  /// `charReceived`.
  ///
  /// Scope is deliberately narrow: only BLE response timeouts trip it. DIRCON
  /// is request/response with its own timeout and no pending-response completer,
  /// so it never contributes.
  final ValueNotifier<bool> customResponsesDegraded = ValueNotifier<bool>(
    false,
  );

  void _recordCustomResponseTimeout() {
    _consecutiveCustomResponseTimeouts++;
    if (_consecutiveCustomResponseTimeouts < _customResponseFailureThreshold ||
        customResponsesDegraded.value) {
      return;
    }
    customResponsesDegraded.value = true;
    print(
      '[transport] link degraded: $_consecutiveCustomResponseTimeouts '
      'consecutive unanswered requests; suspending background polling',
    );
    // One message on the edge, not one per request — a full sweep would
    // otherwise stack forty identical snackbars.
    Snackbar.show(
      ABC.c,
      'SmartSpin2k has stopped responding. Background updates paused.',
      success: false,
    );
  }

  /// A request that was positively answered clears the breaker. Called from
  /// [_decodeCustomValue] only when an incoming frame's reference matches the
  /// in-flight request — never for unsolicited notifications on the same
  /// characteristic.
  void _recordCustomResponseSuccess() {
    _consecutiveCustomResponseTimeouts = 0;
    if (customResponsesDegraded.value) {
      customResponsesDegraded.value = false;
      print('[transport] link recovered: background polling resumed');
    }
  }

  final Object _bleOperationZoneKey = Object();
  final Set<Object> _activeBleOperationTokens = <Object>{};

  // Android does not expose an "is the BLE radio idle?" signal to app code.
  // Treat the completion of the previous GATT write as the best available
  // back-pressure signal, with a small guard interval on Android/Peloton so
  // SS2kConfigApp does not monopolize the shared BLE stack while Grupetto is
  // also advertising/serving as a peripheral.
  Duration get _bleWriteGuardInterval =>
      Platform.isAndroid ? const Duration(milliseconds: 35) : Duration.zero;

  /// Serializes one transport operation, ahead of lower-priority queued work.
  ///
  /// What this does and does not guarantee. A [TransportOpPriority.control]
  /// operation overtakes every *queued* background operation — which is the
  /// case that mattered: a calibration spin-down used to queue behind a
  /// forty-entry settings sweep, each entry costing up to
  /// [_customResponseTimeout] against a device that had stopped answering, for
  /// well over a minute of delay. It cannot preempt the operation already
  /// running. An in-flight service discovery, CCCD write or DIRCON round trip
  /// can exceed two seconds and some have no explicit bound, so the honest
  /// worst case is one in-flight operation, not a fixed number of seconds.
  Future<T> _queueBleOperation<T>(
    Future<T> Function() operation, {
    bool allowInline = true,
    TransportOpPriority priority = TransportOpPriority.background,
    String label = 'transport op',
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

    final completer = Completer<T>();
    _pendingTransportOps.add(
      _PendingTransportOp(priority, label, () async {
        try {
          completer.complete(await _runTransportOperation(operation));
        } catch (error, stackTrace) {
          // Captured rather than thrown: the pump must outlive a failing
          // operation, and the error still reaches whoever awaited this call.
          completer.completeError(error, stackTrace);
        }
      }),
    );
    unawaited(_pumpTransportQueue());
    return completer.future;
  }

  /// Runs one operation with the Android spacing guard and the reentrancy token.
  Future<T> _runTransportOperation<T>(Future<T> Function() operation) async {
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
  }

  Future<void> _pumpTransportQueue() async {
    if (_transportPumpRunning) return;
    _transportPumpRunning = true;
    try {
      while (_pendingTransportOps.isNotEmpty) {
        final next = _takeNextTransportOp();
        final waited = DateTime.now().difference(next.queuedAt);
        // Queue wait is the difference between "the device is slow" and "the
        // app never sent it", which is precisely what the 2026-08-25 capture
        // could not distinguish.
        if (next.priority == TransportOpPriority.control ||
            waited > const Duration(seconds: 1)) {
          print(
            '[transport] ${next.label} (${next.priority.name}) ran after '
            '${waited.inMilliseconds}ms, ${_pendingTransportOps.length} still queued',
          );
        }
        await next.run();
      }
    } finally {
      // Synchronous with the loop's exit check, so an operation enqueued from
      // another microtask either sees the pump running or starts a new one.
      _transportPumpRunning = false;
    }
  }

  /// Highest priority first, FIFO within a priority.
  _PendingTransportOp _takeNextTransportOp() {
    var index = 0;
    for (var i = 1; i < _pendingTransportOps.length; i++) {
      if (_pendingTransportOps[i].priority.index <
          _pendingTransportOps[index].priority.index) {
        index = i;
      }
    }
    return _pendingTransportOps.removeAt(index);
  }

  /// Writes to the SmartSpin2k custom characteristic and does not complete
  /// until the server returns the matching response (or the response times out).
  Future<void> writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> value, {
    TransportOpPriority priority = TransportOpPriority.background,
  }) {
    if (isSimulated) return Future<void>.value();
    return _customReadRequestCoalescer.schedule(
      value,
      (packet) => _writeCustomCharacteristic(device, packet, priority),
    );
  }

  Future<void> _writeCustomCharacteristic(
    BluetoothDevice device,
    List<int> value,
    TransportOpPriority priority,
  ) async {
    return _queueBleOperation(priority: priority, label: 'custom char', () async {
      final dirConSession = _dirConSession;
      if (dirConSession != null && dirConSession.isConnected) {
        try {
          final response = await dirConSession.writeCharacteristic(
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
      if (characteristic == null || !characteristic.device.isConnected) {
        // The write never left the app. A different fact from an unconfirmed
        // write, and callers act on the difference — see the sweep in
        // [requestSettings].
        throw const TransportNotConnected();
      }

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
      } on TimeoutException {
        // The write went out; no matching response arrived in time. Record the
        // strike for the three-strike breaker, then surface it — swallowing it
        // here is what let an unconfirmed calibration write read as success and
        // a stalled sweep grind through forty full timeouts silently.
        _recordCustomResponseTimeout();
        throw const TransportResponseUnconfirmed();
      } finally {
        if (identical(_pendingCustomResponse, response)) {
          _pendingCustomResponse = null;
          _pendingCustomResponseReference = null;
        }
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
      DeviceTransportKind.dircon => _dirConSession?.isConnected ?? false,
      DeviceTransportKind.bluetooth => ftmsControlPointCharacteristic != null,
      DeviceTransportKind.none => false,
    };
  }

  Future<bool> _dispatchWorkoutControlBatch(
    WorkoutControlBatch batch,
    bool Function() isCurrent,
  ) {
    return _queueBleOperation(
      () async {
        for (final command in batch.commands) {
          if (!isCurrent()) return false;
          await _writeFtmsControlPointCommandNow(command);
        }
        return isCurrent();
      },
      // Not `control`: a workout redelivering its target must not be able to
      // starve a calibration command the user is waiting on. It still outranks
      // the settings sweep.
      allowInline: false,
      priority: TransportOpPriority.interactive,
      label: 'workout control batch',
    );
  }

  /// [onDispatch] fires once, *after* transport validation and immediately
  /// before the command reaches the wire — never on a path that then throws
  /// `'FTMS Control Point is not ready'`. It is the point a caller may treat
  /// the command as sent; anything keyed off "sent" before this could be
  /// acknowledged by a stale frame from a previous run.
  Future<void> _writeFtmsControlPointCommandNow(
    List<int> command, [
    void Function()? onDispatch,
  ]) async {
    final dirConSession = _dirConSession;
    if (_transportStateController.value.transport ==
            DeviceTransportKind.dircon &&
        dirConSession != null &&
        dirConSession.isConnected) {
      onDispatch?.call();
      await dirConSession.writeCharacteristic(ftmsControlPointUUID, command);
      return;
    }

    final characteristic = ftmsControlPointCharacteristic;
    if (_transportStateController.value.transport !=
            DeviceTransportKind.bluetooth ||
        characteristic == null ||
        !characteristic.device.isConnected) {
      throw StateError('FTMS Control Point is not ready');
    }
    onDispatch?.call();
    await characteristic.write(command);
  }

  /// Writes an encoded FTMS Control Point command over the active transport.
  ///
  /// DIRCON sessions intentionally do not create FlutterBluePlus
  /// characteristics, so commands whose only input is a cached BLE
  /// characteristic can never reach the device while DIRCON is active.
  Future<void> writeFtmsControlPointCommand(
    List<int> command, {
    void Function()? onDispatch,
  }) async {
    if (isSimulated) return;
    final stopwatch = Stopwatch()..start();
    try {
      await _queueBleOperation(
        () => _writeFtmsControlPointCommandNow(command, onDispatch),
        priority: TransportOpPriority.control,
        label: 'FTMS control point',
      );
      print(
        '[transport] FTMS control point delivered in '
        '${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (error) {
      print(
        '[transport] FTMS control point failed after '
        '${stopwatch.elapsedMilliseconds}ms: $error',
      );
      rethrow;
    }
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
          // Reference matching is the strongest correlation this protocol
          // offers, so only a matched response clears the breaker. An
          // unsolicited notification — log-stream frames arrive as 0x80 on this
          // same characteristic — proves the link carries traffic but not that
          // a *request* was answered. Clearing on those let the calibration log
          // flood keep _consecutiveCustomResponseTimeouts permanently reset, so
          // customResponsesDegraded never tripped and the post-fallback sweep
          // never abandoned early.
          _recordCustomResponseSuccess();
        }
      }

      if (value.length > 1 &&
          value[0] == 0x80 &&
          value[1] == bleScanResultsReference) {
        final update = _scanResultDecoder.add(value);
        if (update != null) {
          _scanResultStreamSupported = true;
          if (update.event == BleScanResultEvent.end &&
              update.isComplete == false) {
            print(
              'Scan-result stream ended with missing packets; displaying '
              '${update.devices.length} complete records.',
            );
          }
          if (update.changed) {
            _applyStreamedFoundDevices(update.devices);
          }
        }
        return;
      }

      if (value.length > 1 && value[1] == settingsSnapshotReference) {
        if (isUnsupportedSettingsSnapshotPacket(value)) {
          _settingsSnapshotDecoder.reset();
          _settingsSnapshotSupport = _SettingsSnapshotSupport.unsupported;
          final completer = _settingsSnapshotCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete(SettingsSnapshotRequestResult.unsupported);
          }
          return;
        }

        if (value[0] == 0x80) {
          try {
            final snapshot = _settingsSnapshotDecoder.add(value);
            if (snapshot != null) {
              _applySettingsSnapshot(snapshot);
              _settingsSnapshotSupport = _SettingsSnapshotSupport.supported;
              final completer = _settingsSnapshotCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.complete(SettingsSnapshotRequestResult.supported);
              }
            }
          } catch (error, stackTrace) {
            _settingsSnapshotDecoder.reset();
            final completer = _settingsSnapshotCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        }
        return;
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
                  if (_scanResultStreamSupported) return;
                  _formatFoundDevices(c, c["value"]);
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

  void _applySettingsSnapshot(Map<String, dynamic> snapshot) {
    _ensureCachedMap();
    final values = settingsSnapshotValuesByReference(
      snapshot,
      customCharacteristic,
    );
    final rawFoundDevices = values.remove(0x14);

    for (final entry in values.entries) {
      final characteristic = _cachedCharacteristicMap?[entry.key];
      if (characteristic == null) continue;

      characteristic['value'] = entry.value.toString();
      if (characteristic['vName'] == fwVname) {
        firmwareVersion.value = characteristic['value'];
      }
      _emitCharacteristicChange(characteristic);
    }

    // Format this last so the saved HRM and power-meter values from the same
    // snapshot are available when the synthetic picker entries are appended.
    if (rawFoundDevices != null) {
      final characteristic = _cachedCharacteristicMap?[0x14];
      if (characteristic != null && !_scanResultStreamSupported) {
        _formatFoundDevices(characteristic, rawFoundDevices.toString());
        _emitCharacteristicChange(characteristic);
      }
    }
  }

  void _applyStreamedFoundDevices(List<BleScanDevice> devices) {
    _ensureCachedMap();
    final foundDevices = _cachedCharacteristicMap?[0x14];
    if (foundDevices == null) return;

    final raw = <String, dynamic>{};
    for (var i = 0; i < devices.length; i++) {
      raw['device $i'] = {'name': devices[i].name, 'UUID': devices[i].uuid};
    }
    _formatFoundDevices(foundDevices, jsonEncode(raw));
    _emitCharacteristicChange(foundDevices);
  }

  void _formatFoundDevices(Map characteristic, String rawJson) {
    final combined = <String, dynamic>{
      'device -4': {'name': 'any', 'UUID': '0x180d'},
      'device -3': {'name': 'none', 'UUID': '0x180d'},
      'device -2': {'name': 'any', 'UUID': '0x1818'},
      'device -1': {'name': 'none', 'UUID': '0x1818'},
    };

    if (rawJson.trim().isNotEmpty &&
        rawJson.trim() != 'null' &&
        rawJson.trim() != ' ') {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          combined[entry.key.toString()] = entry.value;
        }
      }
    }

    combined['device -5'] = {
      'name': getVnameValue(connectedHRMVname, returnNoFirmSupport: true),
      'UUID': '0x180d',
    };
    combined['device -6'] = {
      'name': getVnameValue(connectedPWRVname, returnNoFirmSupport: true),
      'UUID': '0x1818',
    };
    characteristic['value'] = jsonEncode([combined]);
  }

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
    // Anything waiting on readiness is woken here rather than left to time out
    // against an object that will never answer. The disposal flag turns that
    // into `disposed` rather than a spurious `ready`.
    _machineStatusNotificationsLive = false;
    _controlPointNotificationsLive = false;
    _releaseFtmsReadyWaiters();
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
    _controlPointSubscription?.cancel();
    _controlPointSubscription = null;
    _controlPointController.close();
  }
}
