
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:SS2kConfigApp/utils/extra.dart';

import "../utils/snackbar.dart";
import "../utils/customcharhelpers.dart";

class sliderCard extends StatefulWidget {
  const sliderCard({super.key, required this.bleData, required this.c});
  final BLEData bleData;
  final Map c;
  @override
  State<sliderCard> createState() => _sliderCardState();
}

class _sliderCardState extends State<sliderCard> {
  Map get c => widget.c;
  BluetoothCharacteristic get characteristic => widget.bleData.myCharacteristic;
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
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Colors.black,
          width: 2.0,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
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
            writeToSS2K(this.characteristic, this.c);
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
              writeToSS2K(this.characteristic, this.c);
            });
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            const SizedBox(width: 8),
            TextButton(
              child: const Text('BACK'),
              onPressed: () {
          Navigator.pop(context);
        },
            ),
            const SizedBox(width: 8),
          ],
        ),
      ]),
    );
  }
}