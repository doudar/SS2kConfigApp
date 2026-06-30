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
import 'ftmsControlPoint.dart';
import 'bleConstants.dart';

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

class BLEDataManager {
  static final Map<String, BLEData> _dataMap = {};

  static BLEData forDevice(BluetoothDevice device) {
    if (!_dataMap.containsKey(device.remoteId.str)) {
      _dataMap[device.remoteId.str] = BLEData();
    }
    return _dataMap[device.remoteId.str]!;
  }

  static void updateDataForDevice(BluetoothDevice device, BLEData data) {
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

  // Add getter and setter for targetERG to monitor changes
  int get targetERG => _targetERG;
  set targetERG(int value) {
    if (value != _targetERG) {
      _targetERG = value;
      // Notify any listeners that target power has changed
      if (onTargetPowerChanged != null) {
        onTargetPowerChanged!(value);
      }
      // If target power is 0, switch to simulation mode with 0 incline
      if (value == 0 && onModeChanged != null) {
        onModeChanged!(true); // true indicates switch to simulation mode
      }
    }
  }

  // Callback for target power changes
  void Function(int)? onTargetPowerChanged;
  // Callback for mode changes (simulation vs target power)
  void Function(bool)? onModeChanged;

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

class BLEData {
  bool isUserDisconnect = false;
  ValueNotifier<int> rssi = ValueNotifier(0);
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
      connectionState = state;

      if (state == BluetoothConnectionState.disconnected) {
        // Reset connection-specific state so the next setupConnection
        // performs a full re-bootstrap (re-discover services, re-subscribe
        // to notifications, etc.).  Without this, stale references to the
        // old connection's characteristics remain and no data flows after
        // reconnection.
        _resetConnectionState();

        if (isUserDisconnect) return;

        await reconnectAndSetup(device);
      }
    });
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
    _reconnectRequested = false;
    _reconnectCompleter = Completer<bool>();

    bool success = false;
    try {
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        if (isUserDisconnect) break;

        _resetConnectionState();

        try {
          if (!device.isConnected) {
            print(
                '[AutoReconnect] Attempt $attempt/$maxAttempts connecting...');
            await device.connectAndUpdateStream();
          }

          await Future.delayed(settleDelay);

          if (!device.isConnected) {
            throw Exception(
                'Device disconnected during reconnect settle period.');
          }

          await setupConnection(device, forceRefresh: true);

          if (!device.isConnected) {
            throw Exception('Device disconnected during setup.');
          }

          if (onReconnected != null) {
            await onReconnected();
          } else {
            for (final callback in List<Future<void> Function()>.from(
                _onReconnectedCallbacks)) {
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
    subscribed = false;
    charReceived.value = false;
    _myCharacteristic = null;
    indoorBikeCharacteristic = null;
    ftmsControlPointCharacteristic = null;
    services = [];
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _ftmsSubscription?.cancel();
    _ftmsSubscription = null;
    _inUpdateLoop = false;
    _lastRequestStopwatch.reset();
    _cachedCharacteristicMap = null;
    lastFtmsUpdate = null;
    _ftmsRecoveryInProgress = false;
    _lastFtmsRecoveryAttempt = null;
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
  late BluetoothService firmwareService;
  late BluetoothCharacteristic firmwareDataCharacteristic;
  late BluetoothCharacteristic firmwareControlCharacteristic;
  BluetoothCharacteristic? _myCharacteristic;
  BluetoothCharacteristic? ftmsControlPointCharacteristic;
  BluetoothCharacteristic? indoorBikeCharacteristic;
  Completer<void>? _discoverServicesCompleter;
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

  String simulatedTargetWatts = "";
  String simulatedFTMSmode = "";
  int FTMSmode = 0;
  bool simulateTargetWatts = false;
  double tableDivisor = 10.0; // Default divisor for power table data

  // Stream controller for characteristic changes
  final StreamController<CharacteristicChangeEvent>
      _characteristicChangeController =
      StreamController<CharacteristicChangeEvent>.broadcast();

  /// Stream of characteristic changes
  Stream<CharacteristicChangeEvent> get characteristicChanges =>
      _characteristicChangeController.stream;

  List<List<int?>> powerTableData = List.generate(
    10,
    (i) => List.generate(38, (j) => null),
  );

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

  setupConnection(BluetoothDevice device, {bool forceRefresh = false}) async {
    if (!device.isConnected) {
      return;
    }

    if (Platform.isAndroid && device.mtuNow <= 23) {
      _mtuRequestedForConnection = false;
    }

    final needsBootstrap = forceRefresh ||
        services.isEmpty ||
        _myCharacteristic == null ||
        indoorBikeCharacteristic == null ||
        ftmsControlPointCharacteristic == null ||
        !subscribed;

    if (needsBootstrap) {
      if (forceRefresh) {
        this.subscribed = false;
        charReceived.value = false;
        _myCharacteristic = null;
        indoorBikeCharacteristic = null;
        ftmsControlPointCharacteristic = null;
      }

      await _discoverServices(device, forceRefresh: forceRefresh);
      if (services.length > 1) {
        await _findChar();
      }
    }

    await updateCustomCharacter(device);

    // Set up target power change listener
    ftmsData.onTargetPowerChanged = (int newPower) async {
      if (ftmsControlPointCharacteristic != null) {
        try {
          await writeFtmsControlPoint(
            (characteristic) => FTMSControlPoint.writeTargetPower(
              characteristic,
              newPower,
            ),
          );
        } catch (e) {
          print('Error writing target power to FTMS: $e');
        }
      }
    };

    // Set up mode change listener
    ftmsData.onModeChanged = (bool toSimulation) async {
      if (ftmsControlPointCharacteristic != null) {
        try {
          if (toSimulation) {
            // Switch to simulation mode with 0 incline
            await writeFtmsControlPoint(
              (characteristic) => FTMSControlPoint.writeIndoorBikeSimulation(
                characteristic,
                windSpeed: 0,
                grade: 0,
                crr: 0,
                cw: 0,
              ),
            );
          }
        } catch (e) {
          print('Error switching FTMS mode: $e');
        }
      }
    };
  }

  Future<BluetoothCharacteristic?> getMyCharacteristic(
      BluetoothDevice device) async {
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

  Future _discoverServices(BluetoothDevice device,
      {bool forceRefresh = false}) async {
    if (this.isSimulated) return;

    // If a discovery is already in flight, just await it and return.
    if (_discoverServicesCompleter != null) {
      print(
          '[discoverServices] Already in progress – waiting for existing call to finish.');
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
          firmwareService = s;
          configAppCompatibleFirmware = true;
          break;
        }
      }
      if (configAppCompatibleFirmware) {
        characteristics = firmwareService.characteristics;
        for (BluetoothCharacteristic c in characteristics) {
          print(c.uuid.toString());
          if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130005")) {
            firmwareDataCharacteristic = c;
          }
          if (c.uuid == Guid("62ec0272-3ec5-11eb-b378-0242ac130003")) {
            firmwareControlCharacteristic = c;
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
          indoorBikeCharacteristic = c;
          if (!indoorBikeCharacteristic!.isNotifying) {
            await _queueBleOperation(
              () => indoorBikeCharacteristic!.setNotifyValue(true),
            );
            print("subscribed to indoor bike characteristic");
          }
        }
        if (c.uuid == Guid(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID)) {
          ftmsControlPointCharacteristic = c;
        }
      }

      charReceived.value = _myCharacteristic != null;
    } catch (e) {
      charReceived.value = false;
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
    if (this.isSimulated || !device.isConnected) return;

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
    if (indoorBikeCharacteristic == null) {
      await _discoverServices(device);
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
      if (!ftmsCharacteristic.isNotifying) {
        await _queueBleOperation(() => ftmsCharacteristic.setNotifyValue(true));
      }
    } catch (e) {
      print("failed to enable FTMS notify: $e");
      return;
    }

    // TODO handle cancelling subscription
    _ftmsSubscription?.cancel();

    _ftmsSubscription = ftmsCharacteristic.onValueReceived.listen((value) {
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

        // Emit a characteristic change event for FTMS data updates
        if (!_characteristicChangeController.isClosed) {
          _characteristicChangeController.add(CharacteristicChangeEvent(
            vName: "FTMS_DATA",
            reference: "FTMS",
            value: "updated",
            type: "ftms",
          ));
        }
      } catch (e) {
        print('Error parsing FTMS packet: $e');
      }
    }, onError: (Object e) {
      print('Error in FTMS subscription: $e');
    });
    device.cancelWhenDisconnected(_ftmsSubscription!);
  }

  bool _ftmsRecoveryInProgress = false;
  DateTime? _lastFtmsRecoveryAttempt;
  static const Duration _ftmsWatchdogTimeout = Duration(seconds: 15);
  static const Duration _ftmsRecoveryCooldown = Duration(seconds: 30);

  /// Checks the health of the FTMS data stream and attempts to recover if stalled.
  /// Skips if a recovery is already in progress.
  Future<void> checkFtmsHealth(BluetoothDevice device) async {
    if (isSimulated || !device.isConnected) return;
    if (_ftmsRecoveryInProgress) return;

    final now = DateTime.now();
    final recentlyTriedRecovery = _lastFtmsRecoveryAttempt != null &&
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
          'FTMS connection appears stalled (last update: $lastFtmsUpdate). Attempting recovery...');
      _ftmsRecoveryInProgress = true;
      _lastFtmsRecoveryAttempt = now;

      try {
        if (indoorBikeCharacteristic != null && device.isConnected) {
          // Toggle notifications to reset the stream
          await _queueBleOperation(
              () => indoorBikeCharacteristic!.setNotifyValue(false));
          await Future.delayed(const Duration(milliseconds: 200));

          if (!device.isConnected) {
            print('[FTMS Recovery] Device disconnected during recovery.');
            _triggerReconnect(device);
            return;
          }

          await _queueBleOperation(
              () => indoorBikeCharacteristic!.setNotifyValue(true));

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
        '[FTMS Recovery] Device appears disconnected. Triggering reconnect...');

    () async {
      await reconnectAndSetup(device);
    }();
  }

  Future<void> findNSave(BluetoothDevice device, Map c, String find) async {
    if (this.isSimulated) return;
    // Firmware that wasn't Compatible with the app would reboot whenever this command was read.
    if (!this.configAppCompatibleFirmware && c["vName"] == saveVname) {
      return;
    }
    if (c["vName"] == find) {
      try {
        await write(device, [0x02, int.parse(c["reference"]), 0x01]);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e",
            success: false);
      }
    }
  }

  Future saveAllSettings(BluetoothDevice device) async {
    if (this.isSimulated) return;
    for (var c in this.customCharacteristic) {
      if (c["isSetting"] == true) await writeToSS2k(device, c);
    }
    for (var c in this.customCharacteristic) {
      await findNSave(device, c, saveVname);
    }
  }

  Future reboot(BluetoothDevice device) async {
    if (this.isSimulated) return;
    for (var c in this.customCharacteristic) {
      await findNSave(device, c, rebootVname);
    }
  }

  Future resetToDefaults(BluetoothDevice device) async {
    if (this.isSimulated) return;
    for (var c in this.customCharacteristic) {
      await findNSave(device, c, resetVname);
    }
  }

  Future resetPowerTable(BluetoothDevice device) async {
    if (this.isSimulated) return;
    for (var c in this.customCharacteristic) {
      await findNSave(device, c, resetPowerTableVname);
    }
  }

//request all settings
  Future requestSettings(BluetoothDevice device) async {
    if (this.isSimulated) return;

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
        await write(device, [0x01, int.parse(c["reference"])]);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e",
            success: false);
      }
    }
  }

//request single setting
  Future requestSetting(BluetoothDevice device, String name,
      {int? extraByte}) async {
    if (this.isSimulated) return;
    Future<void> _request(Map c) async {
      // Firmware that wasn't Compatible with the app would reboot whenever this command was read.
      if (!this.configAppCompatibleFirmware && c["vName"] == saveVname) {
        return;
      }
      if (c["vName"] == name) {
        try {
          List<int> value = [0x01, int.parse(c["reference"])];
          if (extraByte != null) {
            value.add(extraByte);
          }
          return write(device, value);
        } catch (e) {
          Snackbar.show(ABC.c, "Failed to request setting $e", success: false);
        }
      } else {
        // skipped
      }
    }

    for (var c in this.customCharacteristic) {
      await _request(c);
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

  Future<void> writeToSS2k(BluetoothDevice device, Map c,
      {String s = ""}) async {
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
        final out =
            bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1))
        ];
        break;
      case "bool":
        (s == "false") ? s = "0" : s = "1";
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out =
            bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1))
        ];
        break;
      case "float":
        int t = (double.parse(s) * 10).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out =
            bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1))
        ];
        break;
      case "long":
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out =
            bytes.map((b) => '0x${b.toRadixString(32).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [
          0x02,
          int.parse(c["reference"]),
          int.parse(out.elementAt(0)),
          int.parse(out.elementAt(1)),
          int.parse(out.elementAt(2)),
          int.parse(out.elementAt(3))
        ];
        break;
      case "powerTableData":
        // Define the INT_MIN value for uint16_t in little endian format
        const int intMinValue = -32768;

        // Loop through each row of the tableData
        for (int rowIndex = 0;
            rowIndex < this.powerTableData.length;
            rowIndex++) {
          List<int?> row = this.powerTableData[rowIndex];
          List<int> rowValue = [];

          // Convert each entry in the row to its little-endian byte representation
          for (int? entry in row) {
            int valueToConvert = entry ?? intMinValue;
            final list = Uint16List.fromList([valueToConvert]);
            final bytes = Uint8List.view(list.buffer);
            final out =
                bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
            print('bytes: ${out}');
            rowValue.add(bytes[0]); // Low byte
            rowValue.add(bytes[1]); // High byte
          }

          // Combine the request, reference, and row data
          List<int> rowToSend =
              [0x02, int.parse(c["reference"]), rowIndex + 1] + rowValue;

          // Write the data to the device
          try {
            await write(device, rowToSend);
          } catch (e) {
            Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e",
                success: false);
            return;
          }
        }
        break;

      default:
      //value = [0xff];
    }
    try {
      await write(device, value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  Future<void> _writeQueue = Future.value();
  DateTime? _lastBleWriteCompletedAt;
  final Object _bleOperationZoneKey = Object();
  final Set<Object> _activeBleOperationTokens = <Object>{};

  // Android does not expose an "is the BLE radio idle?" signal to app code.
  // Treat the completion of the previous GATT write as the best available
  // back-pressure signal, with a small guard interval on Android/Peloton so
  // SS2kConfigApp does not monopolize the shared BLE stack while Grupetto is
  // also advertising/serving as a peripheral.
  Duration get _bleWriteGuardInterval =>
      Platform.isAndroid ? const Duration(milliseconds: 35) : Duration.zero;

  Future<T> _queueBleOperation<T>(Future<T> Function() operation) {
    // Some queued operations perform discovery, and discovery may enable CCCD
    // notifications. Running nested queue work inline avoids self-deadlocking
    // while the outer queued operation is waiting for discovery to finish. The
    // zone token keeps that escape hatch scoped to the current queued operation
    // so unrelated BLE callbacks still serialize behind the queue.
    final currentToken = Zone.current[_bleOperationZoneKey];
    if (currentToken != null &&
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

  Future<void> write(BluetoothDevice device, List<int> value) async {
    if (this.isSimulated) return;

    return _queueBleOperation(() async {
      final characteristic = await getMyCharacteristic(device);
      if (characteristic != null && characteristic.device.isConnected) {
        try {
          await characteristic.write(value);
        } catch (e) {
          Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e",
              success: false);
        }
      } else {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k - Not Connected",
            success: false);
      }
    });
  }

  Future<void> writeFtmsControlPoint(
    Future<void> Function(BluetoothCharacteristic characteristic) operation,
  ) async {
    if (this.isSimulated) return;
    final characteristic = ftmsControlPointCharacteristic;
    if (characteristic == null) {
      print('FTMS Control Point characteristic not found');
      return;
    }

    return _queueBleOperation(() => operation(characteristic));
  }

  void decode(BluetoothDevice device) {
    if (this.isSimulated) return;

    subscribed = true;
    _ensureCachedMap();

    _notifySubscription?.cancel();
    final characteristic = _myCharacteristic;
    if (characteristic == null) {
      subscribed = false;
      charReceived.value = false;
      return;
    }

    _notifySubscription =
        characteristic.onValueReceived.listen((value) {
      try {
        if (value.isEmpty) return;

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
                  c["value"] =
                      (data.getInt16(2, Endian.little) / 10).toString();
                  // Emit characteristic change event
                  _emitCharacteristicChange(c);
                  break;
                }
              case "long":
                {
                  c["value"] = data.getInt32(2, Endian.little).toString();
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
                    tList = defaultDevices +
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
                        "FW Version Was Updated!! ${c['value']} ${this.firmwareVersion.value}");
                  }
                  // Emit characteristic change event
                  _emitCharacteristicChange(c);
                  break;
                }
              case "powerTableData":
                int cadenceRow = value[2];
                if (cadenceRow >= 0 &&
                    cadenceRow < this.powerTableData.length) {
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
    }); //VV This is handled by the subscription flag.
    device.cancelWhenDisconnected(_notifySubscription!);
  }

  /// Helper method to emit characteristic change events
  void _emitCharacteristicChange(Map c) {
    if (!_characteristicChangeController.isClosed) {
      _characteristicChangeController.add(CharacteristicChangeEvent(
        vName: c["vName"] ?? "",
        reference: c["reference"] ?? "",
        value: c["value"]?.toString() ?? "",
        type: c["type"] ?? "",
      ));
    }
  }

  /// Dispose of resources
  void dispose() {
    _characteristicChangeController.close();
  }
}
