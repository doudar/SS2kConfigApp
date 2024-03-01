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
import '../utils/customcharhelpers.dart';
import '../utils/constants.dart';
import '../utils/bledata.dart';

/*
 * Copyright (C) 2020 Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../utils/bledata.dart';
import '../utils/snackbar.dart';
import '../utils/constants.dart';
import '../utils/extra.dart';

class DeviceHeader extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;
  final bool connectOnly;

  const DeviceHeader({Key? key, required this.device, required this.bleData, this.connectOnly = false})
      : super(key: key);

  @override
  State<DeviceHeader> createState() => _DeviceHeaderState();
}

class _DeviceHeaderState extends State<DeviceHeader> {
  bool _isExpanded = false;

  Widget _buildSignalStrengthIcon(int rssi) {
    IconData iconData;
    Color iconColor;
    if (rssi >= -60) {
      iconData = FontAwesomeIcons.signal;
      iconColor = Colors.green;
    } else if (rssi >= -70) {
      iconData = FontAwesomeIcons.signal;
      iconColor = Colors.yellow;
    } else {
      iconData = FontAwesomeIcons.signal;
      iconColor = Colors.red;
    }
    return Icon(iconData, color: iconColor);
  }

  @override
  Widget build(BuildContext context) {
    var rssiIcon = _buildSignalStrengthIcon(widget.bleData.rssi.value);

    return Column(children: <Widget>[
      ListTile(
        title: Text('Device: ${widget.device.name} (${widget.device.id})'),
        subtitle: Text('Version: ${widget.bleData.firmwareVersion}'),
        trailing: rssiIcon,
        onTap: () => setState(() => _isExpanded = !_isExpanded),
      ),
      AnimatedCrossFade(
        firstChild: Container(height: 0),
        secondChild: Column(children: <Widget>[
          _buildActionButton('Connect', FontAwesomeIcons.plug, _onConnectPressed),
          _buildActionButton('Refresh', FontAwesomeIcons.syncAlt, _onDiscoverServicesPressed),
          _buildActionButton('Reboot SS2K', FontAwesomeIcons.redo, _onRebootPressed),
          _buildActionButton('Set Defaults', FontAwesomeIcons.undo, _onResetPressed),
          _buildActionButton('Save To SS2k', FontAwesomeIcons.save, _onSaveSettingsPressed),
          _buildActionButton('Backup Settings', FontAwesomeIcons.solidSave, _onSaveLocalPressed),
          _buildActionButton('Load Backup', FontAwesomeIcons.upload, _onLoadLocalPressed),
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
        primary: Colors.white,
      ),
    );
  }

  // ... Remaining code including the methods: _onConnectPressed, _onDisconnectPressed, _onDiscoverServicesPressed, _onSaveSettingsPressed, _onSaveLocalPressed, _onLoadLocalPressed, _onRebootPressed, _onResetPressed
}

