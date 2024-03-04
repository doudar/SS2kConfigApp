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
import "../utils/customcharhelpers.dart";
import '../utils/bledata.dart';

class sliderCard extends StatefulWidget {
  const sliderCard({super.key, required this.bleData, required this.device, required this.c});
  final BLEData bleData;
  final BluetoothDevice device;
  final Map c;
  @override
  State<sliderCard> createState() => _sliderCardState();
}

class _sliderCardState extends State<sliderCard> {
  Map get c => widget.c;
  BluetoothCharacteristic get characteristic => widget.bleData.getMyCharacteristic(widget.device);
  late double _currentSliderValue = double.parse(c["value"]);
  final controller = TextEditingController();

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
    return Container(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        ListTile(
        title: Text(widget.c["textDescription"]),
        dense: true,
        ),
        //Text((c["value"]), textAlign: TextAlign.left),
        TextField(
          controller: this.controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: c["humanReadableName"],
            prefixIcon: Icon(Icons.edit_attributes),
            fillColor: Colors.white,
          ),
          textAlign: TextAlign.center,
          onSubmitted: (t) {
            this.verifyInput(t);
            writeToSS2K(widget.bleData, widget.device, this.c);
            setState(() {});
            return widget.c["value"];
          },
        ),
        const SizedBox(height: 15),
         Slider(
          min: c["min"].toDouble(),
          max: c["max"].toDouble(),
          label: this._currentSliderValue.toStringAsFixed(getPrecision(c)),
          divisions: 100,
          value: constrainValue(this._currentSliderValue),
          onChanged: (double v) {
            setState(() {
              this._currentSliderValue = v;
              widget.c["value"] = this._currentSliderValue.toStringAsFixed(getPrecision(c));
              controller.text = widget.c["value"];
            });
          },
          onChangeEnd: (double v) {
            setState(() {
              this._currentSliderValue = v;
              widget.c["value"] = this._currentSliderValue.toStringAsFixed(getPrecision(c));
              controller.text = widget.c["value"];
              writeToSS2K(widget.bleData, widget.device, this.c);
            });
          },
        ),
      ]),
    );
  }
}
