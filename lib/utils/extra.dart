/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'utils.dart';

final Map<String, StreamControllerReemit<bool>> _connectingControllers = {};
final Map<String, StreamControllerReemit<bool>> _disconnectingControllers = {};

StreamControllerReemit<bool> _connectingControllerFor(String deviceId) {
  return _connectingControllers.putIfAbsent(
    deviceId,
    () => StreamControllerReemit(initialValue: false),
  );
}

StreamControllerReemit<bool> _disconnectingControllerFor(String deviceId) {
  return _disconnectingControllers.putIfAbsent(
    deviceId,
    () => StreamControllerReemit(initialValue: false),
  );
}

/// Convenience helpers for connect/disconnect state tracking.
extension Extra on BleDevice {
  Stream<bool> get isConnecting => _connectingControllerFor(deviceId).stream;

  Stream<bool> get isDisconnecting => _disconnectingControllerFor(deviceId).stream;

  Future<void> connectAndUpdateStream({Duration? timeout}) async {
    final controller = _connectingControllerFor(deviceId);
    controller.add(true);
    try {
      await UniversalBle.connect(deviceId, timeout: timeout);
    } finally {
      controller.add(false);
    }
  }

  Future<void> disconnectAndUpdateStream({Duration? timeout}) async {
    final controller = _disconnectingControllerFor(deviceId);
    controller.add(true);
    try {
      await UniversalBle.disconnect(deviceId, timeout: timeout);
    } finally {
      controller.add(false);
    }
  }
}

Stream<bool> connectingStreamFor(String deviceId) => _connectingControllerFor(deviceId).stream;

Stream<bool> disconnectingStreamFor(String deviceId) => _disconnectingControllerFor(deviceId).stream;

Future<void> connectDeviceId(String deviceId, {Duration? timeout}) async {
  final controller = _connectingControllerFor(deviceId);
  controller.add(true);
  try {
    await UniversalBle.connect(deviceId, timeout: timeout);
  } finally {
    controller.add(false);
  }
}

Future<void> disconnectDeviceId(String deviceId, {Duration? timeout}) async {
  final controller = _disconnectingControllerFor(deviceId);
  controller.add(true);
  try {
    await UniversalBle.disconnect(deviceId, timeout: timeout);
  } finally {
    controller.add(false);
  }
}
