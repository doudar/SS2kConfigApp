/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';
import '../utils/constants.dart';
import '../utils/bledata.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class DeviceHeader extends StatefulWidget {
  final BluetoothDevice device;
  final bool connectOnly;
  const DeviceHeader({Key? key, required this.device,this.connectOnly = false})
      : super(key: key);

  @override
  State<DeviceHeader> createState() => _DeviceHeaderState();
}

class _DeviceHeaderState extends State<DeviceHeader> {
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  Timer rssiTimer = Timer.periodic(Duration(seconds: 30), (rssiTimer) {});
late BLEData bleData;
  @override
 void initState() {
  super.initState();
  bleData = BLEDataManager.forDevice(widget.device);

  _connectionStateSubscription = widget.device.connectionState.listen((state) async {
    if (widget.device.isConnected) {
      this.bleData.rssi.value = await widget.device.readRssi();
    } else {
      this.bleData.rssi.value = 0;
    }
    if (mounted) {
      setState(() {});
    }
  });
  _startRssiTimer();
}

  @override
  void dispose() {
    _connectionStateSubscription!.cancel();
    rssiTimer.cancel();

    super.dispose();
  }

void _startRssiTimer() {
  rssiTimer = Timer.periodic(Duration(seconds: 20), (Timer t) {
    _updateRssi();
  });
}

Future<void> _updateRssi() async {
  if (this.bleData.isUpdatingFirmware || this.bleData.isReadingOrWriting.value) {
    return; // Do not check RSSI if the firmware is being updated
  }
  if (widget.device.isConnected) {
    try {
      this.bleData.rssi.value = await widget.device.readRssi();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      this.bleData.rssi.value = 0;
    }
  }
}



  bool get isConnected {
    return this.bleData.connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
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
      await widget.device.disconnectAndUpdateStream();
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
      this.bleData.services = await widget.device.discoverServices();
      //await _findChar();
      await this.bleData.updateCustomCharacter(widget.device);
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

  Future onSaveSettingsPressed() async {
    try {
      await this.bleData.saveAllSettings(widget.device);
      Snackbar.show(ABC.c, "Settings Saved", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Save Settings Failed ", e), success: false);
    }
  }

  Future onSaveLocalPressed() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user', jsonEncode(this.bleData.customCharacteristic));
      Snackbar.show(ABC.c, "Settings Saved", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Save Local Failed ", e), success: false);
    }
  }

  Future onLoadLocalPressed() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      this.bleData.customCharacteristic = jsonDecode(prefs.getString('user')!);
      Snackbar.show(ABC.c, "Settings Loaded", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Load local failed. Do you have a backup?", e), success: false);
    }
  }

  Future onRebootPressed() async {
    try {
      await this.bleData.reboot( widget.device);
      Snackbar.show(ABC.a, "SmartSpin2k is rebooting", success: true);
      await onDisconnectPressed();
      await onConnectPressed();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reboot Failed ", e), success: false);
    }
  }

  Future onResetPressed() async {
    try {
      await this.bleData.resetToDefaults(widget.device);
      await discoverServices();
      Snackbar.show(ABC.c, "SmartSpin2k has been reset to defaults", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reset Failed ", e), success: false);
    }
  }

  Future discoverServices() async {
    if (mounted) {
      setState(() {
        this.bleData.isReadingOrWriting.value = true;
      });
    }
    if (widget.device.isConnected) {
      try {
        this.bleData.services = await widget.device.discoverServices();
        //_findChar();
        await this.bleData.updateCustomCharacter(widget.device);
        Snackbar.show(ABC.c, "Discover Services: Success", success: true);
      } catch (e) {
        Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
      }
    }
    if (mounted) {
      setState(() {
        this.bleData.isReadingOrWriting.value = false;
      });
    }
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: CircularProgressIndicator(
          //backgroundColor: Colors.black12,
          //color: Colors.black26,
          ),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${widget.device.remoteId}'),
    );
  }

  bool _isExpanded = false;

  Widget _buildSignalStrengthIcon(int rssi) {
    IconData iconData;
    Color iconColor;

    if (widget.device.isConnected) {
      if (rssi >= -70) {
        iconData = Icons.signal_cellular_alt_sharp; // Assume this is 4 bars
        iconColor = Colors.green;
      } else if (rssi >= -80) {
        iconData = Icons.signal_cellular_alt_2_bar_sharp; // Assume this is 3 bars
        iconColor = Colors.yellow;
      } else if (rssi >= -90) {
        iconData = Icons.signal_cellular_alt_1_bar_sharp; // Assume this is 2 bars
        iconColor = Colors.orange;
      } else {
        iconData = Icons.signal_cellular_0_bar_sharp; // Assume this is 1 bar
        iconColor = Colors.red;
      }
    } else {
      iconData = Icons.signal_cellular_off_sharp; // Assume this is 1 bar
      iconColor = Colors.red;
    }

    return Icon(iconData, color: iconColor);
  }

  @override
  Widget build(BuildContext context) {
    var rssiIcon = _buildSignalStrengthIcon(this.bleData.rssi.value);

    return Column(children: <Widget>[
      ListTile(
        title: Text('Device: ${widget.device.name} (${widget.device.id})'),
        subtitle: Text('Version: ${this.bleData.firmwareVersion}'),
        trailing: rssiIcon,
        onTap: () => setState(() => _isExpanded = !_isExpanded),
      ),
      AnimatedCrossFade(
        firstChild: Container(height: 0),
        secondChild: Column(children: <Widget>[
          _buildActionButton('Connect', FontAwesomeIcons.plug, onConnectPressed),
          _buildActionButton('Refresh', FontAwesomeIcons.rotate, onDiscoverServicesPressed),
          _buildActionButton('Reboot SS2K', FontAwesomeIcons.arrowRotateRight, onRebootPressed),
          _buildActionButton('Set Defaults', FontAwesomeIcons.arrowRotateLeft, onResetPressed),
          _buildActionButton('Save To SS2k', FontAwesomeIcons.floppyDisk, onSaveSettingsPressed),
          _buildActionButton('Backup Settings', FontAwesomeIcons.solidFloppyDisk, onSaveLocalPressed),
          _buildActionButton('Load Backup', FontAwesomeIcons.upload, onLoadLocalPressed),
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
      style: OutlinedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.secondary,
        foregroundColor: Colors.white,
      ),
    );
  }

  // ... Remaining code including the methods: _onConnectPressed, _onDisconnectPressed, _onDiscoverServicesPressed, _onSaveSettingsPressed, _onSaveLocalPressed, _onLoadLocalPressed, _onRebootPressed, _onResetPressed
}
