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
import '../utils/extra.dart';
import '../utils/bledata.dart';
import '../utils/constants.dart';

class DeviceHeader extends StatefulWidget {
  final BluetoothDevice device;
  final bool connectOnly;
  final bool firmwareOnlyRefresh;
  final bool customRefreshEnabled;
  const DeviceHeader({Key? key, required this.device, this.connectOnly = false,
      this.firmwareOnlyRefresh = false, this.customRefreshEnabled = true})
      : super(key: key);

  @override
  State<DeviceHeader> createState() => _DeviceHeaderState();
}

class _DeviceHeaderState extends State<DeviceHeader> {
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  Timer rssiTimer = Timer(Duration(seconds: 0), () {});
  Timer setupTimer = Timer(Duration(seconds: 0), () {});
  late BLEData bleData;
  bool _isRefreshing = false;
  String _fwVersion = "";
  VoidCallback? _firmwareVersionListener;
  late final Future<void> Function() _onReconnectedCallback;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    _onReconnectedCallback = _handleReconnected;

    // Listen for firmware version changes to automatically update the UI
    _firmwareVersionListener = () {
      if (mounted) {
        setState(() {
          _fwVersion = bleData.firmwareVersion.value;
        });
      }
    };
    bleData.firmwareVersion.addListener(_firmwareVersionListener!);

    // Initialize firmware version
    _fwVersion = bleData.firmwareVersion.value.isEmpty
        ? "Connecting Please Wait..."
        : bleData.firmwareVersion.value;

    // Start the centralized auto-reconnect monitor.
    // The onReconnected callback handles UI-specific refresh after reconnecting.
    bleData.startConnectionMonitor(
      this.widget.device,
      onReconnected: _onReconnectedCallback,
    );

    // Listen for connection state changes to update UI (e.g. RSSI, services)
    _connectionStateSubscription ??=
        this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        this.bleData.rssi.value = await this.widget.device.readRssi();
        if (widget.customRefreshEnabled) {
          if (widget.firmwareOnlyRefresh) {
            await this
                .bleData
                .ensureCustomCharacteristicStream(this.widget.device);
          } else {
            await this.bleData.setupConnection(this.widget.device);
          }
          if (!_isRefreshing) {
            await _refreshDeviceInfo();
          }
        }
      } else {
        this.bleData.rssi.value = 0;
      }
      if (mounted) {
        setState(() {});
      }
    });
    startTimer();
  }

  Future<void> _refreshDeviceInfo() async {
    if (_isRefreshing) return;

    try {
      _isRefreshing = true;

      // Wait a bit for the device to stabilize after connection
      await Future.delayed(Duration(seconds: 1));

      if (widget.firmwareOnlyRefresh) {
        await bleData.ensureCustomCharacteristicStream(widget.device);
      } else {
        // A manual/full refresh also refreshes the service cache.
        this.bleData.services = await this.widget.device.discoverServices();
      }
      await bleData.requestSetting(this.widget.device, fwVname);
    } catch (e) {
      print('Error refreshing device info: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    bleData.stopConnectionMonitor(onReconnected: _onReconnectedCallback);
    rssiTimer.cancel();
    setupTimer.cancel();
    if (_firmwareVersionListener != null) {
      bleData.firmwareVersion.removeListener(_firmwareVersionListener!);
    }
    super.dispose();
  }

  Future<void> _handleReconnected() async {
    if (!mounted) return;
    this.bleData.rssi.value = await this.widget.device.readRssi();
    if (widget.customRefreshEnabled && !_isRefreshing) {
      await _refreshDeviceInfo();
    }
    if (mounted) setState(() {});
  }

  startTimer() async {
    rssiTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      print("*********UPDATE TIMER**************");
      _updateRssi();
    });
    //This timer checks to see if data has been read from the device
    setupTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      String testValue = bleData.getVnameValue(connectedPWRVname);
      if (widget.customRefreshEnabled &&
          !widget.firmwareOnlyRefresh &&
          testValue == "null" &&
          this.widget.device.isConnected) {
        await this.bleData.setupConnection(this.widget.device);
      }
      // Check FTMS health on every tick
      if (mounted && this.widget.device.isConnected) {
        await bleData.checkFtmsHealth(this.widget.device);
      }
    });
  }

  Future<void> _updateRssi() async {
    if (this.widget.device.isConnected) {
      try {
        this.bleData.rssi.value = await this.widget.device.readRssi();
        if (widget.customRefreshEnabled) {
          bleData.requestSetting(this.widget.device, fwVname);
        }
        // No need for manual setState here anymore - the listener will handle firmware version updates
      } catch (e) {
        this.bleData.rssi.value = 0;
      }
    } else {
      this.bleData.rssi.value = 0;
    }
  }

  bool get isConnected {
    return this.bleData.connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    // Reset user disconnect flag when connecting
    this.bleData.isUserDisconnect = false;

    try {
      await this.widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
      await onDiscoverServicesPressed();
    } catch (e) {
      if (e is FlutterBluePlusException &&
          e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e),
            success: false);
      }
    }
  }

  Future onDisconnectPressed() async {
    try {
      await this.widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e),
          success: false);
    }
  }

  Future onDiscoverServicesPressed() async {
    try {
      await _refreshDeviceInfo();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e),
          success: false);
    }
  }

  Future onRebootPressed() async {
    try {
      await this.bleData.reboot(this.widget.device);
      Snackbar.show(ABC.a, "SmartSpin2k is rebooting", success: true);
      await onDisconnectPressed();
      await onConnectPressed();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reboot Failed ", e),
          success: false);
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

  Widget _buildSignalStrengthIcon(int rssi) {
    IconData iconData;
    Color iconColor;

    if (this.widget.device.isConnected) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    var rssiIcon = _buildSignalStrengthIcon(this.bleData.rssi.value);

    return PopupMenuButton<VoidCallback>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: colorScheme.onSurface.withValues(alpha: 0.16)),
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
              child: rssiIcon,
            ),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  this.widget.device.platformName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_fwVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.80),
                  ),
                ),
              ],
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
          value: onConnectPressed,
          child: ListTile(
            leading: Icon(Icons.electrical_services),
            title: Text('Connect'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onDiscoverServicesPressed,
          child: ListTile(
            leading: Icon(Icons.refresh),
            title: Text('Refresh'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onRebootPressed,
          child: ListTile(
            leading: Icon(Icons.restart_alt),
            title: Text('Reboot SS2k'),
          ),
        ),
      ],
    );
  }
}
