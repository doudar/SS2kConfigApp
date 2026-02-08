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
import 'ftmsControlPoint.dart';
import 'bleConstants.dart';

import 'package:universal_ble/universal_ble.dart';
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

  static BLEData forDeviceId(String deviceId, {bool isSimulated = false}) {
    return _dataMap.putIfAbsent(
      deviceId,
      () => BLEData(deviceId: deviceId, isSimulated: isSimulated),
    );
  }

  static BLEData forBleDevice(BleDevice device, {bool isSimulated = false}) {
    return forDeviceId(device.deviceId, isSimulated: isSimulated);
  }

  static void updateDataForDevice(String deviceId, BLEData data) {
    _dataMap[deviceId] = data;
  }

  static void clearDataForDevice(String deviceId) {
    _dataMap.remove(deviceId);
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
  BLEData({required this.deviceId, this.isSimulated = false});

  final String deviceId;

  bool isUserDisconnect = false;
  ValueNotifier<int> rssi = ValueNotifier(0);
  ValueNotifier<bool> charReceived = ValueNotifier(false);
  DateTime? lastFtmsUpdate;
  StreamSubscription<bool>? _connectionStateSubscription;
  StreamSubscription<Uint8List>? _notifySubscription;
  StreamSubscription<Uint8List>? _ftmsSubscription;
  List<BleService> services = [];
  FtmsData ftmsData = FtmsData();
  bool isSimulated = false; //Is this a demo device?
  bool isConnecting = false;
  bool isDisconnecting = false;
  bool configAppCompatibleFirmware = false;
  bool isUpdatingFirmware = false;
  ValueNotifier<String> firmwareVersion = ValueNotifier("");
  final StreamController<String> _logStreamController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logStreamController.stream;

  String simulatedTargetWatts = "";
  String simulatedFTMSmode = "";
  int FTMSmode = 0;
  bool simulateTargetWatts = false;
  double tableDivisor = 10.0; // Default divisor for power table data

  final StreamController<CharacteristicChangeEvent> _characteristicChangeController =
      StreamController<CharacteristicChangeEvent>.broadcast();

  Stream<CharacteristicChangeEvent> get characteristicChanges => _characteristicChangeController.stream;

  List<List<int?>> powerTableData = List.generate(
    10,
    (i) => List.generate(38, (j) => null),
  );

  var customCharacteristic = customCharacteristicFramework;

  Map<int, Map>? _cachedCharacteristicMap;

  _CharacteristicHandle? _customCharacteristicHandle;
  _CharacteristicHandle? _firmwareDataHandle;
  _CharacteristicHandle? _firmwareControlHandle;
  _CharacteristicHandle? _ftmsControlPointHandle;
  _CharacteristicHandle? _indoorBikeHandle;

  String? get ftmsServiceUuid => _ftmsControlPointHandle?.serviceUuid;
  String? get ftmsCharacteristicUuid => _ftmsControlPointHandle?.characteristicUuid;
  String? get firmwareServiceUuid =>
      _firmwareDataHandle?.serviceUuid ?? _firmwareControlHandle?.serviceUuid;
  String? get firmwareDataCharacteristicUuid => _firmwareDataHandle?.characteristicUuid;
  String? get firmwareControlCharacteristicUuid => _firmwareControlHandle?.characteristicUuid;
  String? get indoorBikeServiceUuid => _indoorBikeHandle?.serviceUuid;
  String? get indoorBikeCharacteristicUuid => _indoorBikeHandle?.characteristicUuid;

  bool subscribed = false;
  final _lastRequestStopwatch = Stopwatch();
  bool _inUpdateLoop = false;

  bool _customNotificationsActive = false;
  bool _ftmsNotificationsActive = false;

  void _ensureCachedMap() {
    if (_cachedCharacteristicMap == null) {
      _cachedCharacteristicMap = {};
      for (var c in customCharacteristic) {
        try {
          _cachedCharacteristicMap![int.parse(c["reference"])] = c;
        } catch (e) {
          debugPrint("Error parsing characteristic reference: $e");
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

  Future<void> setupConnection({bool forceRediscover = false}) async {
    if (isSimulated) return;

    _listenToConnectionState();

    final state = await UniversalBle.getConnectionState(deviceId);
    if (state == BleConnectionState.disconnected) {
      charReceived.value = false;
      return;
    }

    await _discoverServices(force: forceRediscover);
    if (services.isEmpty) return;

    _cacheCharacteristicHandles();
    subscribed = false;

    if (_customCharacteristicHandle != null) {
      await updateCustomCharacter();
    }

    _configureFtmsCallbacks();
  }

  void _listenToConnectionState() {
    _connectionStateSubscription ??= UniversalBle.connectionStream(deviceId).listen((connected) {
      if (!connected) {
        _teardownStreams();
        charReceived.value = false;
      }
    });
  }

  void _teardownStreams() {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _ftmsSubscription?.cancel();
    _ftmsSubscription = null;
    if (_customNotificationsActive && _customCharacteristicHandle != null) {
      unawaited(UniversalBle.unsubscribe(
        deviceId,
        _customCharacteristicHandle!.serviceUuid,
        _customCharacteristicHandle!.characteristicUuid,
      ));
    }
    if (_ftmsNotificationsActive && _indoorBikeHandle != null) {
      unawaited(UniversalBle.unsubscribe(
        deviceId,
        _indoorBikeHandle!.serviceUuid,
        _indoorBikeHandle!.characteristicUuid,
      ));
    }
    _customNotificationsActive = false;
    _ftmsNotificationsActive = false;
    subscribed = false;
  }

  Future<void> _discoverServices({bool force = false}) async {
    if (isSimulated) return;
    if (services.isNotEmpty && !force) return;
    try {
      services = await UniversalBle.discoverServices(deviceId, withDescriptors: true);
    } catch (e) {
      debugPrint('discoverServices failed: $e');
      services = [];
    }
  }

  static final String _customServiceUuid = BleUuidParser.string(csUUID);
  static final String _customCharacteristicUuid = BleUuidParser.string(ccUUID);
  static final String _firmwareServiceUuid = BleUuidParser.string("4FAFC201-1FB5-459E-8FCC-C5C9C331914B");
  static final String _firmwareDataUuid = BleUuidParser.string("62ec0272-3ec5-11eb-b378-0242ac130005");
  static final String _firmwareControlUuid = BleUuidParser.string("62ec0272-3ec5-11eb-b378-0242ac130003");
  static final String _ftmsServiceUuid = BleUuidParser.string(ftmsServiceUUID);
  static final String _ftmsIndoorBikeUuid = BleUuidParser.string(ftmsIndoorBikeDataUUID);
  static final String _ftmsControlPointUuid = BleUuidParser.string(FTMS_CONTROL_POINT_CHARACTERISTIC_UUID);

  void _cacheCharacteristicHandles() {
    if (isSimulated) return;

    for (final service in services) {
      final serviceUuid = BleUuidParser.string(service.uuid);

      if (serviceUuid == _customServiceUuid) {
        for (final characteristic in service.characteristics) {
          final charUuid = BleUuidParser.string(characteristic.uuid);
          if (charUuid == _customCharacteristicUuid) {
            _customCharacteristicHandle = _CharacteristicHandle(serviceUuid, charUuid);
            charReceived.value = true;
          }
        }
      } else if (serviceUuid == _firmwareServiceUuid) {
        configAppCompatibleFirmware = true;
        for (final characteristic in service.characteristics) {
          final charUuid = BleUuidParser.string(characteristic.uuid);
          if (charUuid == _firmwareDataUuid) {
            _firmwareDataHandle = _CharacteristicHandle(serviceUuid, charUuid);
          } else if (charUuid == _firmwareControlUuid) {
            _firmwareControlHandle = _CharacteristicHandle(serviceUuid, charUuid);
          }
        }
      } else if (serviceUuid == _ftmsServiceUuid) {
        for (final characteristic in service.characteristics) {
          final charUuid = BleUuidParser.string(characteristic.uuid);
          if (charUuid == _ftmsIndoorBikeUuid) {
            _indoorBikeHandle = _CharacteristicHandle(serviceUuid, charUuid);
          } else if (charUuid == _ftmsControlPointUuid) {
            _ftmsControlPointHandle = _CharacteristicHandle(serviceUuid, charUuid);
          }
        }
      }
    }
  }

  void _configureFtmsCallbacks() {
    ftmsData.onTargetPowerChanged = (int newPower) async {
      final handle = _ftmsControlPointHandle;
      if (handle == null) return;
      try {
        await FTMSControlPoint.writeTargetPower(
          deviceId: deviceId,
          serviceUuid: handle.serviceUuid,
          characteristicUuid: handle.characteristicUuid,
          targetPower: newPower,
        );
      } catch (e) {
        debugPrint('Error writing target power to FTMS: $e');
      }
    };

    ftmsData.onModeChanged = (bool toSimulation) async {
      final handle = _ftmsControlPointHandle;
      if (!toSimulation || handle == null) return;
      try {
        await FTMSControlPoint.writeIndoorBikeSimulation(
          deviceId: deviceId,
          serviceUuid: handle.serviceUuid,
          characteristicUuid: handle.characteristicUuid,
          windSpeed: 0,
          grade: 0,
          crr: 0,
          cw: 0,
        );
      } catch (e) {
        debugPrint('Error switching FTMS mode: $e');
      }
    };
  }

  ///Data Helpers****************************************************************

  Future<void> updateCustomCharacter() async {
    if (isSimulated || _customCharacteristicHandle == null) return;
    if (_inUpdateLoop) return;

    _inUpdateLoop = true;
    try {
      if (Platform.isAndroid) {
        try {
          await UniversalBle.requestMtu(deviceId, 515);
        } catch (_) {}
      }

      if (!subscribed || !_customNotificationsActive) {
        await decode();
        await updateIndoorBikeData();
        subscribed = true;
      }

      if (!_lastRequestStopwatch.isRunning) {
        await requestSettings();
        _lastRequestStopwatch.start();
      } else if (_lastRequestStopwatch.elapsed > const Duration(seconds: 5)) {
        _lastRequestStopwatch
          ..reset();
        await requestSettings();
      }
    } finally {
      _inUpdateLoop = false;
    }
  }

  Future<void> _ensureCustomNotifications() async {
    if (_customNotificationsActive) return;
    final handle = _customCharacteristicHandle;
    if (handle == null) return;
    await UniversalBle.subscribeNotifications(deviceId, handle.serviceUuid, handle.characteristicUuid);
    _customNotificationsActive = true;
  }

  Future<void> updateIndoorBikeData() async {
    if (isSimulated || _indoorBikeHandle == null) return;

    final handle = _indoorBikeHandle!;
    await UniversalBle.subscribeNotifications(deviceId, handle.serviceUuid, handle.characteristicUuid);

    _ftmsSubscription?.cancel();
    _ftmsSubscription = UniversalBle.characteristicValueStream(deviceId, handle.characteristicUuid).listen(
      _handleFtmsValue,
      onError: (Object e) => debugPrint('Error in FTMS subscription: $e'),
    );
    _ftmsNotificationsActive = true;
  }

  Future<void> pauseFtmsNotifications() async {
    if (_indoorBikeHandle == null || !_ftmsNotificationsActive) {
      return;
    }
    try {
      await UniversalBle.unsubscribe(
        deviceId,
        _indoorBikeHandle!.serviceUuid,
        _indoorBikeHandle!.characteristicUuid,
      );
    } catch (e) {
      debugPrint('Error pausing FTMS notifications: $e');
    } finally {
      _ftmsSubscription?.cancel();
      _ftmsSubscription = null;
      _ftmsNotificationsActive = false;
    }
  }

  Future<void> resumeFtmsNotifications() async {
    await updateIndoorBikeData();
  }

  void _handleFtmsValue(Uint8List value) {
    lastFtmsUpdate = DateTime.now();
    if (value.length < 2) {
      throw ArgumentError('FTMS Characteristic data list is too short');
    }
    ByteData byteData = ByteData.sublistView(value);

    int flags = byteData.getUint16(0, Endian.little);
    int index = 2;

    String binaryFlags = flags.toRadixString(2).padLeft(16, '0');
    debugPrint('FTMS flags: $binaryFlags');

    ftmsData.cadence = 0;
    ftmsData.watts = 0;
    ftmsData.heartRate = 0;
    ftmsData.speed = 0;

    ftmsData.speed = byteData.getUint16(index, Endian.little) ~/ 100;
    index += 2;

    if ((flags & (1 << 1)) != 0) {
      index += 2;
    }

    if ((flags & (1 << 2)) != 0) {
      ftmsData.cadence = byteData.getUint16(index, Endian.little) ~/ 2;
      index += 2;
    }

    if ((flags & (1 << 3)) != 0) {
      index += 2;
    }
    if ((flags & (1 << 4)) != 0) {
      index += 3;
    }

    if ((flags & (1 << 5)) != 0) {
      ftmsData.resistance = byteData.getInt16(index, Endian.little);
      index += 2;
    }

    if ((flags & (1 << 6)) != 0) {
      ftmsData.watts = byteData.getInt16(index, Endian.little);
      index += 2;
    }

    if ((flags & (1 << 7)) != 0) {
      index += 2;
    }
    if ((flags & (1 << 8)) != 0) {
      index += 1;
    }

    if ((flags & (1 << 9)) != 0) {
      ftmsData.heartRate = byteData.getUint8(index);
    }

    if (!_characteristicChangeController.isClosed) {
      _characteristicChangeController.add(CharacteristicChangeEvent(
        vName: "FTMS_DATA",
        reference: "FTMS",
        value: "updated",
        type: "ftms",
      ));
    }
  }

  Future<void> checkFtmsHealth() async {
    if (isSimulated || _indoorBikeHandle == null) return;

    final now = DateTime.now();
    const watchdogTimeout = Duration(seconds: 3);

    if (lastFtmsUpdate != null && now.difference(lastFtmsUpdate!) > watchdogTimeout) {
      debugPrint('FTMS connection appears stalled (last update: $lastFtmsUpdate). Attempting recovery...');
      try {
        final handle = _indoorBikeHandle!;
        await UniversalBle.unsubscribe(deviceId, handle.serviceUuid, handle.characteristicUuid);
        await Future.delayed(const Duration(milliseconds: 200));
        _ftmsNotificationsActive = false;
        await updateIndoorBikeData();
        lastFtmsUpdate = DateTime.now();
      } catch (e) {
        debugPrint('Error attempting FTMS recovery: $e');
      }
    } else if (lastFtmsUpdate == null && !_ftmsNotificationsActive) {
      await updateIndoorBikeData();
    }
  }

  Future<void> findNSave(Map c, String find) async {
    if (isSimulated) return;
    if (!configAppCompatibleFirmware && c["vName"] == saveVname) {
      return;
    }
    if (c["vName"] == find) {
      await write([0x02, int.parse(c["reference"]), 0x01]);
    }
  }

  Future<void> saveAllSettings() async {
    if (isSimulated) return;
    for (var c in customCharacteristic) {
      if (c["isSetting"] == true) {
        await writeToSS2k(c);
      }
    }
    for (var c in customCharacteristic) {
      await findNSave(c, saveVname);
    }
  }

  Future<void> reboot() async {
    if (isSimulated) return;
    for (var c in customCharacteristic) {
      await findNSave(c, rebootVname);
    }
  }

  Future<void> resetToDefaults() async {
    if (isSimulated) return;
    for (var c in customCharacteristic) {
      await findNSave(c, resetVname);
    }
  }

  Future<void> resetPowerTable() async {
    if (isSimulated) return;
    for (var c in customCharacteristic) {
      await findNSave(c, resetPowerTableVname);
    }
  }

  Future<void> requestSettings() async {
    if (isSimulated) return;

    for (var c in customCharacteristic) {
      if (!configAppCompatibleFirmware && c["vName"] == saveVname) {
        continue;
      }

      if (c["vName"] == BLE_logStreamVname) {
        continue;
      }

      try {
        await Future.delayed(const Duration(milliseconds: 50));
        await write([0x01, int.parse(c["reference"])], withResponse: true);
      } catch (e) {
        Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
      }
    }
  }

  Future<void> requestSetting(String name, {int? extraByte}) async {
    if (isSimulated) return;

    for (var c in customCharacteristic) {
      if (!configAppCompatibleFirmware && c["vName"] == saveVname) {
        continue;
      }
      if (c["vName"] == name) {
        try {
          List<int> value = [0x01, int.parse(c["reference"])];
          if (extraByte != null) {
            value.add(extraByte);
          }
          await write(value, withResponse: true);
        } catch (e) {
          Snackbar.show(ABC.c, "Failed to request setting $e", success: false);
        }
      }
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

  Future<void> writeToSS2k(Map c, {String s = ""}) async {
    if (isSimulated) return;
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
        final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
        break;
      case "bool":
        (s == "false") ? s = "0" : s = "1";
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
        break;
      case "float":
        int t = (double.parse(s) * 10).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
        print('bytes: ${out}');
        value = [0x02, int.parse(c["reference"]), int.parse(out.elementAt(0)), int.parse(out.elementAt(1))];
        break;
      case "long":
        int t = double.parse(s).round();
        final list = new Uint64List.fromList([t]);
        final bytes = new Uint8List.view(list.buffer);
        final out = bytes.map((b) => '0x${b.toRadixString(32).padLeft(2, '0')}');
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
        for (int rowIndex = 0; rowIndex < this.powerTableData.length; rowIndex++) {
          List<int?> row = this.powerTableData[rowIndex];
          List<int> rowValue = [];

          // Convert each entry in the row to its little-endian byte representation
          for (int? entry in row) {
            int valueToConvert = entry ?? intMinValue;
            final list = Uint16List.fromList([valueToConvert]);
            final bytes = Uint8List.view(list.buffer);
            final out = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}');
            print('bytes: ${out}');
            rowValue.add(bytes[0]); // Low byte
            rowValue.add(bytes[1]); // High byte
          }

          // Combine the request, reference, and row data
          List<int> rowToSend = [0x02, int.parse(c["reference"]), rowIndex + 1] + rowValue;

          try {
            await write(rowToSend);
          } catch (e) {
            Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
            return;
          }
        }
        break;

      default:
      //value = [0xff];
    }
    try {
      await write(value);
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  Future<void> write(List<int> value, {bool withResponse = true}) async {
    if (isSimulated) return;
    final handle = _customCharacteristicHandle;
    if (handle == null) {
      Snackbar.show(ABC.c, "No SmartSpin2K characteristic", success: false);
      return;
    }
    try {
      await UniversalBle.write(
        deviceId,
        handle.serviceUuid,
        handle.characteristicUuid,
        Uint8List.fromList(value),
        withoutResponse: !withResponse,
      );
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to write to SmartSpin2k $e", success: false);
    }
  }

  Future<void> decode() async {
    if (isSimulated || _customCharacteristicHandle == null) return;

    subscribed = true;
    _ensureCachedMap();
    await _ensureCustomNotifications();

    _notifySubscription?.cancel();
    _notifySubscription = UniversalBle.characteristicValueStream(deviceId, _customCharacteristicHandle!.characteristicUuid).listen((value) {
      try {
        if (value.isEmpty) return;

        if (value[0] == 0x80) {
          if (value.length < 2) return;
          
          // Use cached map for O(1) lookup
          var c = _cachedCharacteristicMap?[value[1]];
          
          if (c != null) {
            var length = value.length;
            var t = new Uint8List(length);
            for (var i = 0; i < length; i++) {
              t[i] = value[i];
            }
            var data = t.buffer.asByteData();

            switch (c["type"]) {
              case "int":
                {
                  if (data.lengthInBytes < 4) {
                    c["value"] = noFirmSupport;
                  } else {
                    c["value"] = data.getInt16(2, Endian.little).toString();

                    simulatedTargetWatts = (c["reference"] == "0x28") ? c["value"] : simulatedTargetWatts;
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
                    print("FW Version Was Updated!! ${c['value']} ${this.firmwareVersion.value}");
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
    });
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

class _CharacteristicHandle {
  _CharacteristicHandle(this.serviceUuid, this.characteristicUuid);

  final String serviceUuid;
  final String characteristicUuid;
}
