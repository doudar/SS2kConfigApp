/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/snackbar.dart";
import '../utils/bledata.dart';
import '../utils/constants.dart';

class sliderCard extends StatefulWidget {
  const sliderCard({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<sliderCard> createState() => _sliderCardState();
}

class _sliderCardState extends State<sliderCard> {
  Map get c => this.widget.c;
  late BLEData bleData;
  late double _currentSliderValue = double.parse(c["value"]);
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
  }

  @override
  void dispose() {
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
    int? inputNumber = ((double.tryParse(c["value"]))?.round());
    inputNumber ??= int.tryParse(c["value"]);

    if (inputNumber! < c["min"]) {
      c["value"] = c["min"].toString();
      int _min = c["min"];
      Snackbar.show(ABC.c, prettyException("Entered value is below minimum $_min", e), success: false);
      controller.text = c["value"];
    } else if (inputNumber > c["max"]) {
      c["value"] = c["max"].toString();
      int _max = c["max"];
      Snackbar.show(ABC.c, prettyException("Entered value is above maximum $_max", e), success: false);
      controller.text = c["value"];
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Colors.black,
          width: 2.0,
        ),
      ),
      child: Column(children: <Widget>[
        Text((c["humanReadableName"]), style: TextStyle(fontSize: 40), textAlign: TextAlign.left),
        Text((c["value"]), style: TextStyle(fontSize: 30), textAlign: TextAlign.left),
        TextField(
          controller: this.controller,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.edit_attributes),
            fillColor: Colors.white,
          ),
          style: TextStyle(
            fontSize: 30,
          ),
          textAlign: TextAlign.center,
          onSubmitted: (t) {
            this.verifyInput(t);
            this.bleData.writeToSS2K(this.widget.device, this.c);
            setState(() {});
            return this.widget.c["value"];
          },
        ),
        const SizedBox(height: 15),
        Slider(
          min: c["min"].toDouble(),
          max: c["max"].toDouble(),
          label: this._currentSliderValue.toStringAsFixed(bleData.getPrecision(c)),
          divisions: 100,
          value: constrainValue(this._currentSliderValue),
          onChanged: (double v) {
            setState(() {
              this._currentSliderValue = v;
              this.widget.c["value"] = this._currentSliderValue.toStringAsFixed(bleData.getPrecision(c));
              controller.text = this.widget.c["value"];
            });
          },
          onChangeEnd: (double v) {
            setState(() {
              this._currentSliderValue = v;
              this.widget.c["value"] = this._currentSliderValue.toStringAsFixed(bleData.getPrecision(c));
              controller.text = this.widget.c["value"];
              this.bleData.writeToSS2K(this.widget.device, this.c);
            });
          },
        ),
        TextButton(
          child: const Text('SAVE'),
          onPressed: () {
            //Find the save command and execute it
            this.bleData.customCharacteristic.forEach((c) => this.bleData.findNSave(this.widget.device, c, saveVname));
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}
