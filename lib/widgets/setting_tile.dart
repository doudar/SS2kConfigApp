import 'dart:async';

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:SS2kConfigApp/utils/extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../widgets/slider_card.dart";
import "../widgets/bool_card.dart";
import "../widgets/plain_text_card.dart";
import '../widgets/dropdown_card.dart';

class SettingTile extends StatefulWidget {
  final BLEData bleData;
  final Map c;
  const SettingTile({Key? key, required this.bleData, required this.c}) : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  late StreamSubscription<List<int>> _lastValueSubscription;
  @override
  void initState() {
    super.initState();
    _lastValueSubscription = widget.bleData.myCharacteristic.lastValueStream.listen((value) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget widgetPicker() {
    switch (c["type"]) {
      case "int":
      case "float":
      case "long":
        return sliderCard(bleData: widget.bleData, c: c);
      case "string":
        if ((c["vName"] == connectedHRMVname) || (c["vName"] == connectedPWRVname)) {
          return dropdownCard(bleData: widget.bleData, c: c);
        }
        return plainTextCard(bleData: widget.bleData, c: c);
      case "bool":
        return boolCard(bleData: widget.bleData, c: c);
      default:
        return plainTextCard(bleData: widget.bleData, c: c);
    }
  }

  String valueFormatter() {
    String _ret = c["value"] ?? "";
    if (_ret == "true" || _ret == "false") {
      _ret = (_ret == "true") ? "On" : "Off";
    }
    _ret = (c["vName"] == passwordVname) ? "**********" : _ret;
    return _ret;
  }

  @override
  void dispose() {
    _lastValueSubscription.cancel();
    super.dispose();
  }

  BluetoothCharacteristic get characteristic => widget.bleData.myCharacteristic;
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
                Text((c["humanReadableName"]),
                    textAlign: TextAlign.left, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  valueFormatter(),
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
                      appBar: AppBar(title: const Text('Edit Setting')),
                      body: Center(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            widgetPicker(),
                            Text(
                              "Settings are immediate for the current session.\nClick save on the main screen to make them persistent.",
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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
