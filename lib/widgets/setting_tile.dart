import 'dart:async';
import 'dart:math';

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/snackbar.dart";
import "../utils/customcharhelpers.dart";

class SettingTile extends StatefulWidget {
  final BluetoothCharacteristic characteristic;
  final Map c;
  const SettingTile({Key? key, required this.characteristic, required this.c}) : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  List<int> _value = [];
  late StreamSubscription<List<int>> _lastValueSubscription;
  @override
  void initState() {
    super.initState();
    _lastValueSubscription = widget.characteristic.lastValueStream.listen((value) {
      _value = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lastValueSubscription.cancel();
    super.dispose();
  }

  BluetoothCharacteristic get characteristic => widget.characteristic;
  Map get c => widget.c;

  @override
  Widget build(BuildContext context) {
    SizedBox(height: 10);
    return Hero(
      tag: Text(c["vName"]),
      // Wrap the ListTile in a Material widget so the ListTile has someplace
      // to draw the animated colors during the hero transition.
      child: Material(
        child: Card(
          child: ListTile(
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            title: Column(
              children: <Widget>[
                Text((c["humanReadableName"]), textAlign: TextAlign.left),
                Text(
                  c["value"] ?? "",
                  textAlign: TextAlign.right,
                ),
                Icon(Icons.edit_note_sharp),
              ],
            ),
            tileColor: (c["value"] == noFirmSupport) ? Color.fromARGB(149, 21, 21, 26) : Color.fromARGB(29, 1, 1, 242),
            onTap: () {
              if (c["value"] == noFirmSupport) {
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute<Widget>(builder: (BuildContext context) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Edit Page')),
                      body: Center(
                        child: settingCard(characteristic: characteristic, c: c),
                      ),
                    );
                  }),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

class settingCard extends StatefulWidget {
  const settingCard({super.key, required this.characteristic, required this.c});
  final BluetoothCharacteristic characteristic;
  final Map c;
  @override
  State<settingCard> createState() => _settingCardState();
}

class _settingCardState extends State<settingCard> {
  Map get c => widget.c;
  BluetoothCharacteristic get characteristic => widget.characteristic;
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
              child: const Text('SAVE'),
              onPressed: () => writeToSS2K(characteristic, c),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ]),
    );
  }
}
