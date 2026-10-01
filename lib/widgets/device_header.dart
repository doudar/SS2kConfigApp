/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/snackbar.dart';
import '../utils/device_data.dart';
import '../utils/device_transport_state.dart';
import '../utils/constants.dart';

class DeviceHeader extends StatefulWidget {
  final BluetoothDevice device;
  final bool connectOnly;
  final bool firmwareOnlyRefresh;
  final bool customRefreshEnabled;
  const DeviceHeader({
    Key? key,
    required this.device,
    this.connectOnly = false,
    this.firmwareOnlyRefresh = false,
    this.customRefreshEnabled = true,
  }) : super(key: key);

  @override
  State<DeviceHeader> createState() => _DeviceHeaderState();
}

class _DeviceHeaderState extends State<DeviceHeader> {
  late final ConnectedEpochWatcher _watcher;
  Timer rssiTimer = Timer(Duration(seconds: 0), () {});
  Timer setupTimer = Timer(Duration(seconds: 0), () {});
  late DeviceData deviceData;
  bool _isRefreshing = false;
  bool _retryRefreshAfterInProgress = false;
  bool _connectionActionInProgress = false;
  late final Listenable _statusChanges;
  StreamSubscription<CharacteristicChangeEvent>? _deviceNameSubscription;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);

    _statusChanges = Listenable.merge([
      deviceData.transportState,
      deviceData.firmwareVersion,
      deviceData.customResponseReceived,
      deviceData.customResponsesDegraded,
    ]);
    _deviceNameSubscription = deviceData.characteristicChanges
        .where((event) => event.vName == deviceNameVname)
        .listen((_) {
          if (mounted) setState(() {});
        });

    // Start the centralized auto-reconnect monitor. It owns BLE-specific
    // recovery only — the connected-epoch watcher below is this widget's sole
    // session signal, so no `onReconnected` callback is registered. Wiring both
    // ran the setup work twice per reconnect: the watcher fires when the
    // transport reports connected, `onReconnected` fires again after
    // `setupConnection` returns.
    deviceData.startConnectionMonitor(this.widget.device);

    // Re-initialize once per connected session on either transport.
    // `BluetoothDevice.connectionState`, which this replaces, never fires over
    // DIRCON, so the old listener had to bail out on that transport entirely.
    _watcher = ConnectedEpochWatcher(
      transportState: deviceData.transportState,
      onNewConnectedEpoch: (state) =>
          unawaited(_initializeConnectedSession(state)),
      onLeftConnected: (_) {
        deviceData.rssi.value = 0;
        if (mounted) setState(() {});
      },
    )..attach();
    // The watcher deliberately does not replay on attach, unlike the fbp
    // stream it replaces. Without this the header would lose its setup pass on
    // every screen entry made while already connected.
    if (_watcher.isConnected) {
      unawaited(_initializeConnectedSession(deviceData.transportState.value));
    }
    startTimer();
  }

  /// Brings the header's view of the device up to date for one connected
  /// session.
  ///
  /// The whole body is guarded. This runs as a fire-and-forget callback, so
  /// anything that throws becomes an unhandled async error — silent in release,
  /// an isolate pause in debug. `readRssi` is the one that actually bit: a
  /// disconnect racing this call throws, and there is nothing above to catch
  /// it.
  ///
  /// Each await is followed by an epoch re-check so that work started in one
  /// session cannot publish its result into the next.
  Future<void> _initializeConnectedSession(DeviceTransportState state) async {
    final generation = _watcher.generation;
    bool stale() => !mounted || !_watcher.isCurrentGeneration(generation);
    try {
      // DIRCON is a network transport and has no BLE RSSI to read.
      if (state.transport == DeviceTransportKind.bluetooth) {
        await _readRssiInto();
      }
      if (stale()) return;
      if (widget.customRefreshEnabled) {
        if (widget.firmwareOnlyRefresh) {
          await deviceData.ensureCustomCharacteristicStream(widget.device);
        } else {
          await deviceData.setupConnection(widget.device);
        }
        if (stale()) return;
        // _refreshDeviceInfo queues its own retry if another session's pass
        // is still running, so this session's refresh is never dropped.
        await _refreshDeviceInfo();
      }
    } catch (e) {
      print('[DeviceHeader] connected-session init failed: $e');
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshDeviceInfo({bool forceRefresh = false}) async {
    if (_isRefreshing) {
      // A previous session's pass (or a manual "discover services") is still
      // running. _isRefreshing is not scoped per session, so without this the
      // losing caller's refresh would be silently dropped instead of retried
      // once the in-flight pass finishes.
      _retryRefreshAfterInProgress = true;
      return;
    }

    try {
      _isRefreshing = true;

      // Wait a bit for the device to stabilize after connection
      final generation = _watcher.generation;
      await Future.delayed(Duration(seconds: 1));
      if (!mounted || !_watcher.isCurrentGeneration(generation)) return;

      if (widget.firmwareOnlyRefresh) {
        await deviceData.ensureCustomCharacteristicStream(widget.device);
      } else {
        await deviceData.setupConnection(
          widget.device,
          forceRefresh: forceRefresh,
        );
      }
      await deviceData.requestSetting(this.widget.device, fwVname);
    } catch (e) {
      print('Error refreshing device info: $e');
    } finally {
      _isRefreshing = false;
      final retry = _retryRefreshAfterInProgress;
      _retryRefreshAfterInProgress = false;
      if (retry && mounted) {
        unawaited(_refreshDeviceInfo());
      }
    }
  }

  @override
  void dispose() {
    _watcher.dispose();
    _deviceNameSubscription?.cancel();
    _deviceNameSubscription = null;
    deviceData.stopConnectionMonitor();
    rssiTimer.cancel();
    setupTimer.cancel();
    super.dispose();
  }

  /// Reads RSSI without letting a disconnect race become a thrown error.
  ///
  /// The read is inherently racy: the device can go away between the
  /// `isConnected` check and the reply. Every caller here treats a failed read
  /// as "no signal", never as a reason to abandon what it was doing.
  Future<void> _readRssiInto() async {
    final device = deviceData.resolveTransportDevice(widget.device);
    if (!device.isConnected) {
      this.deviceData.rssi.value = 0;
      return;
    }
    try {
      this.deviceData.rssi.value = await device.readRssi();
    } catch (e) {
      this.deviceData.rssi.value = 0;
    }
  }

  // Both bodies are guarded for the same reason as the connection-state
  // listener: a timer callback's future is discarded, so a throw here is an
  // unhandled async error with no owner.
  startTimer() async {
    rssiTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      try {
        await _updateRssi();
      } catch (e) {
        print('[DeviceHeader] RSSI poll failed: $e');
      }
    });
    // Keep monitoring FTMS health without repeatedly restarting GATT setup.
    setupTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (!mounted || !deviceData.isTransportActive) return;
      try {
        await deviceData.checkFtmsHealth(this.widget.device);
      } catch (e) {
        print('[DeviceHeader] FTMS health check failed: $e');
      }
    });
  }

  Future<void> _updateRssi() async {
    await _readRssiInto();
    if (widget.customRefreshEnabled && deviceData.isTransportActive) {
      await deviceData.requestSetting(this.widget.device, fwVname);
    }
    // No need for manual setState here anymore - the listener handles
    // firmware version updates on either transport.
  }

  bool get isConnected {
    return this.deviceData.isTransportActive;
  }

  Future onConnectPressed() async {
    if (_connectionActionInProgress) return;
    setState(() => _connectionActionInProgress = true);
    // Reset user disconnect flag when connecting
    this.deviceData.isUserDisconnect = false;

    try {
      await this.deviceData.connectPreferred(this.widget.device);
    } catch (e) {
      if (e is FlutterBluePlusException &&
          e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(
          ABC.c,
          prettyException("Connect Error:", e),
          success: false,
        );
      }
    } finally {
      if (mounted) setState(() => _connectionActionInProgress = false);
    }
  }

  Future<void> onReconnectPressed() async {
    if (_connectionActionInProgress) return;
    setState(() => _connectionActionInProgress = true);
    try {
      // Connecting an already-connected GATT client is a no-op. Explicitly
      // close it and reset subscriptions before asking for a new session.
      await deviceData.disconnectPreferred(widget.device);
      if (!mounted) return;
      await deviceData.connectPreferred(widget.device);
    } catch (e) {
      Snackbar.show(
        ABC.c,
        prettyException('Reconnect Error: ', e),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _connectionActionInProgress = false);
    }
  }

  Future onDisconnectPressed() async {
    try {
      await this.deviceData.disconnectPreferred(this.widget.device);
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(
        ABC.c,
        prettyException("Disconnect Error:", e),
        success: false,
      );
    }
  }

  Future onDiscoverServicesPressed() async {
    try {
      await _refreshDeviceInfo(forceRefresh: true);
      Snackbar.show(ABC.c, "Settings refresh requested", success: true);
    } catch (e) {
      Snackbar.show(
        ABC.c,
        prettyException("Discover Services Error:", e),
        success: false,
      );
    }
  }

  Future onRebootPressed() async {
    try {
      await this.deviceData.reboot(this.widget.device);
      Snackbar.show(ABC.a, "SmartSpin2k is rebooting", success: true);
      // Do not treat a reboot as a user-requested disconnect. In particular,
      // closing a DIRCON socket here sets [isUserDisconnect], then reconnects
      // while the device is still booting. That bypasses DIRCON recovery and
      // causes connectPreferred to fall back to BLE. Let the transport-loss
      // monitor reconnect after the device's DIRCON endpoint is ready again.
    } catch (e) {
      Snackbar.show(
        ABC.c,
        prettyException("Reboot Failed ", e),
        success: false,
      );
    }
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: CircularProgressIndicator(),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${this.widget.device.remoteId}'),
    );
  }

  /// Branches on [DeviceTransportState] rather than on `isDirConConnected` and
  /// `device.isConnected`. Those two can disagree with the transport state
  /// after a failover — a live BLE session left over from a DIRCON drop kept
  /// painting the router icon — and only the transport state is authoritative.
  Widget _buildSignalStrengthIcon(DeviceTransportState state, int rssi) {
    IconData iconData;
    Color iconColor;

    final connected = state.phase == DeviceTransportPhase.connected;

    if (connected && state.transport == DeviceTransportKind.dircon) {
      // DIRCON is a network transport and has no meaningful BLE RSSI. Use a
      // clearly different connected-cable symbol instead of implying that the
      // network session has no signal.
      iconData = Icons.router;
      iconColor = Colors.lightBlueAccent;
    } else if (connected && state.transport == DeviceTransportKind.bluetooth) {
      if (rssi >= -60) {
        iconData = Icons.signal_cellular_4_bar_sharp;
        iconColor = Colors.green;
      } else if (rssi >= -70) {
        iconData = Icons.signal_cellular_alt_sharp;
        iconColor = Colors.lightGreenAccent;
      } else if (rssi >= -80) {
        iconData = Icons.signal_cellular_alt_2_bar_sharp;
        iconColor = Colors.yellow;
      } else if (rssi >= -90) {
        iconData = Icons.signal_cellular_alt_1_bar_sharp;
        iconColor = Colors.orange;
      } else {
        iconData = Icons.signal_cellular_0_bar_sharp;
        iconColor = Colors.red;
      }
    } else {
      iconData = Icons.signal_cellular_off_sharp;
      iconColor = Colors.red;
    }

    return Icon(iconData, color: iconColor);
  }

  String get _connectionStatus {
    if (_connectionActionInProgress) return 'Connecting…';
    if (deviceData.isSimulated) return deviceData.firmwareVersion.value;
    final state = deviceData.transportState.value;
    switch (state.phase) {
      case DeviceTransportPhase.disconnected:
        return 'Disconnected';
      case DeviceTransportPhase.connecting:
        return 'Connecting…';
      case DeviceTransportPhase.reconnecting:
        return 'Reconnecting…';
      case DeviceTransportPhase.connected:
        final transport = state.transport == DeviceTransportKind.dircon
            ? 'Network'
            : 'Bluetooth';
        if (deviceData.customResponsesDegraded.value) {
          return '$transport Connected, no data received';
        }
        if (state.transport == DeviceTransportKind.bluetooth &&
            !deviceData.customResponseReceived.value) {
          return '$transport connected · waiting for device';
        }
        final version = deviceData.firmwareVersion.value;
        return version.isEmpty ? '$transport connected' : version;
    }
  }

  bool get _connectionBusy =>
      _connectionActionInProgress ||
      deviceData.transportState.value.phase ==
          DeviceTransportPhase.connecting ||
      deviceData.transportState.value.phase ==
          DeviceTransportPhase.reconnecting;

  bool get _canReboot =>
      isConnected &&
      !_connectionBusy &&
      !deviceData.customResponsesDegraded.value &&
      (deviceData.isSimulated ||
          deviceData.transportState.value.transport ==
              DeviceTransportKind.dircon ||
          deviceData.customResponseReceived.value);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _statusChanges,
      builder: (context, _) => _buildHeader(context),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final advertisedName = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : widget.device.advName;
    final displayName = deviceData.preferredDeviceName(advertisedName);

    return PopupMenuButton<VoidCallback>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.16),
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.70),
              colorScheme.surfaceContainer.withValues(alpha: 0.60),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: colorScheme.onSurface.withValues(alpha: 0.06),
              blurRadius: 2,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: ValueListenableBuilder<DeviceTransportState>(
                valueListenable: deviceData.transportState,
                builder: (context, transportState, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: deviceData.rssi,
                    builder: (context, rssi, _) {
                      return _buildSignalStrengthIcon(transportState, rssi);
                    },
                  );
                },
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Tooltip(
                    message: _connectionStatus,
                    child: Text(
                      _connectionStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            isConnected &&
                                deviceData.customResponsesDegraded.value
                            ? colorScheme.error
                            : colorScheme.onSurface.withValues(alpha: 0.80),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.expand_more,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
      onSelected: (callback) => callback(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[
        PopupMenuItem<VoidCallback>(
          enabled: !_connectionBusy,
          value: isConnected ? onReconnectPressed : onConnectPressed,
          child: ListTile(
            leading: Icon(Icons.electrical_services),
            title: Text(isConnected ? 'Reconnect' : 'Connect'),
          ),
        ),
        if (isConnected && deviceData.customResponsesDegraded.value)
          PopupMenuItem<VoidCallback>(
            enabled: false,
            child: Text(
              'The connection is open, but SmartSpin2k is not answering. '
              'Reconnect to try a fresh connection.\n\n'
              'Using Grupetto on this device?\n'
              'Open SmartSpin2k Config App on a different phone or tablet '
              'and connect to SmartSpin2k over Bluetooth. In Settings → Network, '
              'connect SmartSpin2k to the same Wi-Fi network as this device. '
              'Then return here and reconnect.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        PopupMenuItem<VoidCallback>(
          enabled: isConnected && !_connectionBusy,
          value: onDiscoverServicesPressed,
          child: ListTile(leading: Icon(Icons.refresh), title: Text('Refresh')),
        ),
        PopupMenuItem<VoidCallback>(
          enabled: _canReboot,
          value: onRebootPressed,
          child: ListTile(
            enabled: _canReboot,
            leading: Icon(Icons.restart_alt),
            title: Text('Reboot SS2k'),
          ),
        ),
      ],
    );
  }
}
