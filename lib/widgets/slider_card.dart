/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/snackbar.dart";
import '../utils/device_data.dart';
import '../utils/constants.dart';
import 'device_settings_style.dart';
import '../utils/workout/workout_visuals.dart';

class sliderCard extends StatefulWidget {
  const sliderCard({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<sliderCard> createState() => _sliderCardState();
}

class _sliderCardState extends State<sliderCard> {
  Map get c => this.widget.c;
  late DeviceData deviceData;
  late double _currentSliderValue = double.parse(c["value"]);
  final controller = TextEditingController();
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;
  bool _userIsInteracting = false;

  @override
  void initState() {
    super.initState();
    deviceData = DeviceDataManager.forDevice(this.widget.device);
    _charSubscription = deviceData.characteristicChanges
        .where((event) => event.vName == c["vName"])
        .listen((event) {
          if (!mounted || _userIsInteracting) return;
          final newVal = double.tryParse(c["value"]?.toString() ?? "");
          if (newVal != null && newVal != _currentSliderValue) {
            setState(() {
              _currentSliderValue = newVal;
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

  double constrainValue(double v) {
    if (v > c["max"]) v = c["max"].toDouble();
    if (v < c["min"]) v = c["min"].toDouble();
    return v;
  }

  void verifyInput(String t) {
    c["value"] = t;
    double? inputNumber = double.tryParse(c["value"]);

    if (inputNumber != null) {
      if (inputNumber < c["min"]) {
        c["value"] = c["min"].toString();
        var _min = c["min"];
        Snackbar.show(
          ABC.c,
          "Entered value is below minimum $_min",
          success: false,
        );
        controller.text = c["value"];
      } else if (inputNumber > c["max"]) {
        c["value"] = c["max"].toString();
        var _max = c["max"];
        Snackbar.show(
          ABC.c,
          "Entered value is above maximum $_max",
          success: false,
        );
        controller.text = c["value"];
      }
    }

    setState(() {});
  }

  Color _getTileColor() {
    if (c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return DeviceSettingsStyle.accent(c["settingType"] as SettingType);
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
              Text(
                (c["value"]),
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              TextField(
                controller: this.controller,
                decoration: InputDecoration(
                  labelText: 'Value',
                  helperText: '${c["min"]} – ${c["max"]}',
                  prefixIcon: Icon(Icons.edit_attributes),
                  fillColor: WorkoutVisuals.ink,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                style: TextStyle(fontSize: 24, color: Colors.white),
                textAlign: TextAlign.center,
                onSubmitted: (t) {
                  this.verifyInput(t);
                  this.deviceData.writeToSS2k(this.widget.device, this.c);
                  setState(() {});
                  return this.widget.c["value"];
                },
              ),
              const SizedBox(height: 15),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: baseColor,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: baseColor,
                  overlayColor: Colors.white.withAlpha(32),
                  valueIndicatorTextStyle: TextStyle(color: baseColor),
                ),
                child: Slider(
                  min: c["min"].toDouble(),
                  max: c["max"].toDouble(),
                  label: this._currentSliderValue.toStringAsFixed(
                    deviceData.getPrecision(c),
                  ),
                  divisions: 100,
                  value: constrainValue(this._currentSliderValue),
                  onChangeStart: (double v) {
                    _userIsInteracting = true;
                  },
                  onChanged: (double v) {
                    setState(() {
                      this._currentSliderValue = v;
                      this.widget.c["value"] = this._currentSliderValue
                          .toStringAsFixed(deviceData.getPrecision(c));
                      controller.text = this.widget.c["value"];
                    });
                  },
                  onChangeEnd: (double v) {
                    _userIsInteracting = false;
                    setState(() {
                      this._currentSliderValue = v;
                      this.widget.c["value"] = this._currentSliderValue
                          .toStringAsFixed(deviceData.getPrecision(c));
                      controller.text = this.widget.c["value"];
                      this.deviceData.writeToSS2k(this.widget.device, this.c);
                    });
                  },
                ),
              ),
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
                    onPressed: () async {
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
    );
  }
}
