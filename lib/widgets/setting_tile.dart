import 'dart:async';
import 'dart:math';

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
  final controller = TextEditingController();
  late String text = this.c["value"].toString();
  late double _currentSliderValue = int.tryParse(text) != null ? int.parse(text).toDouble() : double.parse(text);
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
    controller.dispose();
  }

  BluetoothCharacteristic get char => widget.characteristic;
  Map get c => widget.c;
  String input = "";

  void verifyInput(text) {
    int? inputNumber = ((double.tryParse(text))?.round());
    inputNumber ??= int.tryParse(text);

    if (inputNumber! < c["min"]) {
      input = c["min"].toString();
      int _min = c["min"];
      Snackbar.show(ABC.c, prettyException("Entered value is below minimum $_min", e), success: false);
      controller.text = input;
    } else if (inputNumber > c["max"]) {
      input = c["max"].toString();
      int _max = c["max"];
      Snackbar.show(ABC.c, prettyException("Entered value is above maximum $_max", e), success: false);
      controller.text = input.toString();
    }
  
    setState(() {
      this.text = text;
      this._currentSliderValue = int.tryParse(text) != null ? int.parse(text).toDouble() : double.parse(text);
    });
  }

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
              side: BorderSide(color: Colors.black, width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            title: Column(
              children: <Widget>[
                Text((c["humanReadableName"]), textAlign: TextAlign.left),
                Text(
                  c["value"].toString(),
                  textAlign: TextAlign.right,
                ),
                Icon(Icons.edit_note_sharp),
              ],
            ),
            tileColor: Color.fromARGB(29, 1, 1, 242),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<Widget>(builder: (BuildContext context) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Edit Page')),
                    body: Center(
                      child: Hero(
                        tag: "inner",
                        //tag: Text(c["vName"]),
                        child: Material(
                          child: Card(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                TextField(
                                  controller: this.controller,
                                  decoration: InputDecoration(prefixIcon: Icon(Icons.edit_attributes), labelText: text),
                                  onChanged: (text) => this.verifyInput(text),
                                ),
                                Slider(
                                  min: c["min"].toDouble(),
                                  max: c["max"].toDouble(),
                                  label: _currentSliderValue.round().toString(),
                                  divisions: 100,
                                  value: _currentSliderValue,
                                  onChanged: (double v) {
                                    this.text = v.toString();
                                    setState(() {
                                      _currentSliderValue = v;
                                    });
                                  },
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      child: const Text('SAVE'),
                                      onPressed: () => writeToSS2K(char, c, text),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}
