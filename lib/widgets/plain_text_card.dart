/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

import 'package:ss2kconfigapp/utils/constants.dart';
import 'device_settings_style.dart';
import 'network_settings_save.dart';
import '../utils/workout/workout_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/device_data.dart';

class plainTextCard extends StatefulWidget {
  const plainTextCard({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<plainTextCard> createState() => _plainTextCardState();
}

class _plainTextCardState extends State<plainTextCard> {
  Map get c => this.widget.c;
  final controller = TextEditingController();
  bool passwordVisible = false;
  late DeviceData deviceData;
  final String _currentValue = "Current Value: ";
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  bool _saving = false;
  late final String _initialValue;
  bool get _isNetworkSetting => c['settingType'] == SettingType.network;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    controller.text = c["value"];
    _initialValue = controller.text;
    _charSubscription = deviceData.characteristicChanges
        .where((event) => event.vName == c["vName"])
        .listen((event) {
          if (mounted) {
            setState(() {
              // Update the text field only if the user hasn't modified it
              if (controller.text == c["value"]) return;
              controller.text = c["value"];
            });
          }
        });
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  bool verifyInput(String t) {
    // Example validation: Ensure input is not empty
    bool isValid = t.trim().isNotEmpty;
    if (isValid) {
      c["value"] = t.trim();
      controller.text = c["value"];
      setState(() {});
    }
    return isValid;
  }

  Future<void> _saveNetworkSetting() async {
    if (_saving) return;
    final value = controller.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid input! Please check your input and try again.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final saved = await saveNetworkSettings(
      context: context,
      deviceData: deviceData,
      device: widget.device,
      settings: [
        {...c, 'value': value},
      ],
      changed: value != _initialValue,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }

  Color _getTileColor() {
    if (c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return DeviceSettingsStyle.accent(c["settingType"] as SettingType);
  }

  Widget passwordTextField() {
    return TextField(
      controller: this.controller,
      enabled: !_saving,
      obscureText: !passwordVisible,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        hintText: "Password",
        labelText: "Password",
        helperStyle: TextStyle(color: Colors.white),
        labelStyle: TextStyle(color: WorkoutVisuals.muted),
        suffixIcon: IconButton(
          tooltip: passwordVisible ? 'Hide password' : 'Show password',
          icon: Icon(
            passwordVisible ? Icons.visibility : Icons.visibility_off,
            color: WorkoutVisuals.muted,
          ),
          onPressed: () {
            setState(() {
              passwordVisible = !passwordVisible;
            });
          },
        ),
        alignLabelWithHint: false,
        filled: true,
        fillColor: WorkoutVisuals.ink,
      ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      style: TextStyle(color: Colors.white, fontSize: 24),
      onSubmitted: (t) {
        if (_isNetworkSetting) {
          unawaited(_saveNetworkSetting());
          return;
        }
        this.verifyInput(t);
        this.deviceData.writeToSS2k(this.widget.device, this.c);
        setState(() {});
        return this.widget.c["value"];
      },
    );
  }

  Widget regularTextField() {
    return TextField(
      controller: this.controller,
      enabled: !_saving,
      decoration: InputDecoration(
        hintText: "Type Here",
        hintStyle: TextStyle(fontWeight: FontWeight.w200),
        prefixIcon: Icon(Icons.edit_attributes),
        fillColor: WorkoutVisuals.ink,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      style: TextStyle(fontSize: 24, color: Colors.white),
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: (t) {
        if (_isNetworkSetting) {
          unawaited(_saveNetworkSetting());
          return;
        }
        this.verifyInput(t);
        this.deviceData.writeToSS2k(this.widget.device, this.c);
        setState(() {});
        return this.widget.c["value"];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Color baseColor = _getTileColor();
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: WorkoutVisuals.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: DeviceSettingsStyle.panel(baseColor),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                (c["humanReadableName"]),
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              (c["vName"] == passwordVname)
                  ? ((passwordVisible)
                        ? Text(
                            _currentValue + c["value"],
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          )
                        : Text(
                            _currentValue + "**********",
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ))
                  : Text(
                      (c["value"]),
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
              SizedBox(height: 10),
              (c["vName"] == passwordVname)
                  ? passwordTextField()
                  : regularTextField(),
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
                              await _saveNetworkSetting();
                              return;
                            }
                            // Use the controller's text for validation
                            bool inputIsValid = verifyInput(controller.text);
                            if (inputIsValid) {
                              // Proceed with saving if input is valid
                              await this.deviceData.writeToSS2k(
                                this.widget.device,
                                this.widget.c,
                              );
                              await this.deviceData.writeCommand(
                                this.widget.device,
                                saveVname,
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                            } else {
                              // Handle invalid input, e.g., show an error message
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Invalid input! Please check your input and try again.',
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
