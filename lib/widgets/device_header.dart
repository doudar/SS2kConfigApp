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
  Timer rssiTimer = Timer.periodic(Duration(seconds: 30), (rssiTimer) {});
  late BLEData bleData;
  bool _isRefreshing = false;
  String _fwVersion = "";

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);

    _connectionStateSubscription = this.widget.device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        // When device connects/reconnects, update RSSI and refresh services
        this.bleData.rssi.value = await this.widget.device.readRssi();
        await this.bleData.setupConnection(this.widget.device);
        _fwVersion = this.bleData.firmwareVersion;
        if (!_isRefreshing) {
          await _refreshDeviceInfo();
        }
      } else {
        print("*********Detected Disconnect**************");
        this.bleData.rssi.value = 0;
        await this.widget.device.connectAndUpdateStream();
        await this.bleData.setupConnection(this.widget.device);
        _fwVersion = this.bleData.firmwareVersion;
      }
      if (mounted) {
        setState(() {});
      }
    });
    _startRssiTimer();
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

      if (mounted) {
        setState(() {
          _fwVersion = this.bleData.firmwareVersion;
        });
      }
    } catch (e) {
      print('Error refreshing device info: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    rssiTimer.cancel();
    super.dispose();
  }

  void _startRssiTimer() {
    rssiTimer = Timer.periodic(Duration(seconds: 20), (Timer t) {
      print("*********UPDATE TIMER**************");
      _updateRssi();
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
        if (mounted) {
          setState(() {
            _fwVersion = this.bleData.firmwareVersion;
          });
        }
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

  Future onResetPowerTablePressed() async {
    try {
      await this.bleData.resetPowerTable(this.widget.device);
      Snackbar.show(ABC.c, "The Power Table has been deleted.", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reset Power Table Failed ", e), success: false);
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

    return Column(children: <Widget>[
      ListTile(
        leading: rssiIcon,
        title: Text('Device: ${this.widget.device.platformName} (${this.widget.device.remoteId})'),
        subtitle: Text('Version: ${_fwVersion}'),
        trailing: Icon(
          _isExpanded ? Icons.expand_less : Icons.expand_more,
          size: 40,
          color: Theme.of(context).primaryColor,
        ),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
      ),
      AnimatedCrossFade(
        firstChild: Container(height: 0),
        secondChild: Column(children: <Widget>[
          _buildActionButton('Connect', FontAwesomeIcons.plug, onConnectPressed),
          _buildActionButton('Refresh', FontAwesomeIcons.rotate, onDiscoverServicesPressed),
          _buildActionButton('Reboot SS2k', FontAwesomeIcons.arrowRotateRight, onRebootPressed),
          _buildActionButton('Set Defaults', FontAwesomeIcons.arrowRotateLeft, onResetPressed),
          _buildActionButton('Clear Powertable', FontAwesomeIcons.xmark, onResetPowerTablePressed),
          _buildActionButton('Presets', FontAwesomeIcons.sliders, onPresetsPressed),
        ]),
        crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: Duration(milliseconds: 500),
      ),
      Divider(height: 5),
    ]);
  }

  Widget _buildActionButton(String text, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      icon: Icon(icon),
      label: Text(text),
      onPressed: onPressed,
    );
  }
}
