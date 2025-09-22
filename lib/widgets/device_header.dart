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
import '../utils/power_table_management.dart';
import '../utils/presets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../utils/constants.dart';

class DeviceHeader extends StatefulWidget {
  final BluetoothDevice device;
  final bool connectOnly;
  const DeviceHeader({Key? key, required this.device, this.connectOnly = false}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);

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
    _fwVersion = bleData.firmwareVersion.value;

    // Only create subscription if it doesn't exist
    _connectionStateSubscription ??= this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        // When device connects/reconnects, update RSSI and refresh services
        this.bleData.rssi.value = await this.widget.device.readRssi();
        await this.bleData.setupConnection(this.widget.device);
        if (!_isRefreshing) {
          await _refreshDeviceInfo();
        }
      } else {
        print("*********Detected Disconnect**************");
        this.bleData.rssi.value = 0;
        await this.widget.device.connectAndUpdateStream();
        await this.bleData.setupConnection(this.widget.device);
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

      // Discover services to get new firmware version
      this.bleData.services = await this.widget.device.discoverServices();
      bleData.requestSetting(this.widget.device, fwVname);

      // No need for manual setState here anymore - the listener will handle it
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
    rssiTimer.cancel();
    setupTimer.cancel();
    if (_firmwareVersionListener != null) {
      bleData.firmwareVersion.removeListener(_firmwareVersionListener!);
    }
    super.dispose();
  }

  startTimer() async {
    rssiTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      print("*********UPDATE TIMER**************");
      _updateRssi();
    });
    //This timer checks to see if data has been read from the device
    setupTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      String testValue = bleData.getVnameValue(connectedPWRVname);
      if (testValue == "null" && this.widget.device.isConnected) {
        await this.bleData.setupConnection(this.widget.device);
      }
    });
  }

  Future<void> _updateRssi() async {
    if (this.bleData.isUpdatingFirmware || this.bleData.isReadingOrWriting.value) {
      return; // Do not check RSSI if the firmware is being updated
    }
    if (this.widget.device.isConnected) {
      try {
        this.bleData.rssi.value = await this.widget.device.readRssi();
        bleData.requestSetting(this.widget.device, fwVname);
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
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
      }
    }
  }

  Future onDisconnectPressed() async {
    try {
      await this.widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e), success: false);
    }
  }

  Future onDiscoverServicesPressed() async {
    if (mounted) {
      setState(() {
        this.bleData.isReadingOrWriting.value = true;
      });
    }
    try {
      await _refreshDeviceInfo();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
    }
    if (mounted) {
      setState(() {
        this.bleData.isReadingOrWriting.value = false;
      });
    }
  }

  Future onPowerTablePressed() async {
    await PowerTableManager.showPowerTableMenu(context, bleData, widget.device);
  }

  Future onPresetsPressed() async {
    await PresetManager.showPresetsMenu(context, bleData, widget.device);
  }

  Future onRebootPressed() async {
    try {
      await this.bleData.reboot(this.widget.device);
      Snackbar.show(ABC.a, "SmartSpin2k is rebooting", success: true);
      await onDisconnectPressed();
      await onConnectPressed();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reboot Failed ", e), success: false);
    }
  }

  Future onResetPressed() async {
    try {
      await this.bleData.resetToDefaults(this.widget.device);
      await onConnectPressed();
      Snackbar.show(ABC.c, "SmartSpin2k has been reset to defaults", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reset Failed ", e), success: false);
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

  bool _isExpanded = false;

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
    var rssiIcon = _buildSignalStrengthIcon(this.bleData.rssi.value);

    return PopupMenuButton<VoidCallback>(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            rssiIcon,
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  this.widget.device.platformName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'v${_fwVersion}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ],
        ),
      ),
      onSelected: (callback) => callback(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[
        PopupMenuItem<VoidCallback>(
          value: onConnectPressed,
          child: ListTile(
            leading: Icon(FontAwesomeIcons.plug),
            title: Text('Connect'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onDiscoverServicesPressed,
          child: ListTile(
            leading: Icon(FontAwesomeIcons.rotate),
            title: Text('Refresh'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onRebootPressed,
          child: ListTile(
            leading: Icon(FontAwesomeIcons.arrowRotateRight),
            title: Text('Reboot SS2k'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onResetPressed,
          child: ListTile(
            leading: Icon(FontAwesomeIcons.arrowRotateLeft),
            title: Text('Set Defaults'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onPowerTablePressed,
          child: ListTile(
            leading: Icon(FontAwesomeIcons.table),
            title: Text('Manage PowerTable'),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onPresetsPressed,
          child: ListTile(
            leading: Icon(FontAwesomeIcons.sliders),
            title: Text('Presets'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String text, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      icon: Icon(icon),
      label: Text(text),
      onPressed: onPressed,
    );
  }
}
