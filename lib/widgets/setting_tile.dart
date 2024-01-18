import 'dart:async';
import 'dart:math';

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/snackbar.dart";
import "../utils/customcharhelpers.dart";
import "../widgets/slider_card.dart";
import "../widgets/plain_text_card.dart";

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

  Widget widgetPicker(){
    switch(c["type"]){
    case "int":
    case "float":
    case "long":
    return sliderCard(characteristic: characteristic, c: c);
    case "string":
    return plainTextCard(characteristic: characteristic, c: c);
    case "bool":
    return sliderCard(characteristic: characteristic, c: c);
    default:
    return plainTextCard(characteristic: characteristic, c: c);
    }
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
                Text((c["humanReadableName"]), textAlign: TextAlign.left, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  c["value"] ?? "",
                  textAlign: TextAlign.right,
                ),
                Icon(Icons.edit_note_sharp),
              ],
            ),
            tileColor: (c["value"] == noFirmSupport) ? deactiveBackgroundColor : null,
            onTap: () {
              if (c["value"] == noFirmSupport) {
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute<Widget>(builder: (BuildContext context) {
                    return Scaffold(
                      appBar: AppBar(title: const Text('Edit Page')),
                      body: Center(
                        child: widgetPicker(),
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


