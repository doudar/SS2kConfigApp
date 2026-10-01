/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/device_data.dart';
import '../utils/constants.dart';
import 'device_settings_style.dart';
import 'network_settings_save.dart';
import '../utils/workout/workout_visuals.dart';

class boolCard extends StatefulWidget {
  const boolCard({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<boolCard> createState() => _boolCardState();
}

class _boolCardState extends State<boolCard> {
  late DeviceData deviceData;
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  bool _saving = false;
  late final String _initialValue;
  bool get _isNetworkSetting => widget.c['settingType'] == SettingType.network;
  String? _networkValue;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _initialValue = widget.c['value'];
    _charSubscription = deviceData.characteristicChanges
        .where((event) => event.vName == widget.c["vName"])
        .listen((event) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  Color _getTileColor() {
    if (widget.c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return DeviceSettingsStyle.accent(widget.c["settingType"] as SettingType);
  }

  @override
  Widget build(BuildContext context) {
    Color baseColor = _getTileColor();
    return Column(
      children: <Widget>[
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: WorkoutVisuals.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            decoration: DeviceSettingsStyle.panel(baseColor),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  (this.widget.c["humanReadableName"]),
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  (bool.parse(_networkValue ?? this.widget.c["value"])
                      ? "On"
                      : "Off"),
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                Switch(
                  value: bool.parse(_networkValue ?? this.widget.c["value"]),
                  activeThumbColor: WorkoutVisuals.ink,
                  activeTrackColor: baseColor,
                  inactiveThumbColor: WorkoutVisuals.muted,
                  inactiveTrackColor: Colors.black26,
                  onChanged: _saving
                      ? null
                      : (b) {
                          if (_isNetworkSetting) {
                            setState(() => _networkValue = b.toString());
                            return;
                          }
                          this.widget.c["value"] = b.toString();
                          this.deviceData.writeToSS2k(
                            this.widget.device,
                            this.widget.c,
                          );
                          setState(() {});
                          return this.widget.c["value"];
                        },
                ),
                const SizedBox(height: 15),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    TextButton(
                      child: const Text(
                        'BACK',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: WorkoutVisuals.mint,
                        foregroundColor: WorkoutVisuals.ink,
                        minimumSize: const Size(80, 48),
                      ),
                      child: const Text(
                        'SAVE',
                        style: TextStyle(
                          color: WorkoutVisuals.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: _saving
                          ? null
                          : () async {
                              if (_isNetworkSetting) {
                                setState(() => _saving = true);
                                final value =
                                    _networkValue ?? widget.c['value'];
                                final saved = await saveNetworkSettings(
                                  context: context,
                                  deviceData: deviceData,
                                  device: widget.device,
                                  settings: [
                                    {...widget.c, 'value': value},
                                  ],
                                  changed: value != _initialValue,
                                );
                                if (!mounted) return;
                                setState(() => _saving = false);
                                if (saved) Navigator.pop(context);
                                return;
                              }
                              //Find the save command and execute it
                              await this.deviceData.writeCommand(
                                this.widget.device,
                                saveVname,
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                            },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
