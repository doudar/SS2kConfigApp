/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'utils.dart';
import 'connection_setup_coordinator.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Map<DeviceIdentifier, StreamControllerReemit<bool>> _cglobal = {};
final Map<DeviceIdentifier, StreamControllerReemit<bool>> _dglobal = {};
final Map<DeviceIdentifier, ConnectionSetupCoordinator> _connectCoordinators =
    {};

/// connect & disconnect + update stream
extension Extra on BluetoothDevice {
  // convenience
  StreamControllerReemit<bool> get _cstream {
    _cglobal[remoteId] ??= StreamControllerReemit(initialValue: false);
    return _cglobal[remoteId]!;
  }

  // convenience
  StreamControllerReemit<bool> get _dstream {
    _dglobal[remoteId] ??= StreamControllerReemit(initialValue: false);
    return _dglobal[remoteId]!;
  }

  // get stream
  Stream<bool> get isConnecting {
    return _cstream.stream;
  }

  // get stream
  Stream<bool> get isDisconnecting {
    return _dstream.stream;
  }

  // connect & update stream
  Future<void> connectAndUpdateStream() {
    final coordinator = _connectCoordinators[remoteId] ??=
        ConnectionSetupCoordinator();
    return coordinator.run((_) async {
      _cstream.add(true);
      try {
        if (!isConnected) {
          await connect(license: License.nonprofit);
        }
      } catch (_) {
        // Android can report that this app's GATT client is already attached
        // when another local app holds the same physical BLE link. Treat that
        // as success, but surface every genuine connection failure.
        if (!isConnected) rethrow;
      } finally {
        _cstream.add(false);
      }
    });
  }

  // disconnect & update stream
  Future<void> disconnectAndUpdateStream({bool queue = true}) async {
    _dstream.add(true);
    try {
      await disconnect(queue: queue);
    } finally {
      _dstream.add(false);
    }
  }
}
