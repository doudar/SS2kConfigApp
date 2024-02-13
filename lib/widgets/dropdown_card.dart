import 'dart:convert';

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:SS2kConfigApp/utils/extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/customcharhelpers.dart";

class dropdownCard extends StatefulWidget {
  const dropdownCard({super.key, required this.bleData, required this.c});
  final BLEData bleData;
  final Map c;
  @override
  State<dropdownCard> createState() => _dropdownCardState();
}

class _dropdownCardState extends State<dropdownCard> {
  List<String> DDItems = [];
  @override
  void dispose() {
    super.dispose();
  }

  void buildDevicesMap() {
    late List _items;
    DDItems = [widget.c["value"]];
    // widget.bleData.customCharacteristic.forEach((d) => (d["vName"] == foundDevicesVname) ? print(d["value"]) : null);
    widget.bleData.customCharacteristic.forEach((d) => (d["vName"] == foundDevicesVname) ? _items = jsonDecode(d["value"]) : null);

    for (var d in _items) {
      for (var subd in d.values) {
        if (widget.c["vName"] == connectedPWRVname) {
          if (subd["UUID"] == '0x1818' ||
              subd["UUID"] == '0x1826' ||
              subd["UUID"] == '6e400001-b5a3-f393-e0a9-e50e24dcca9e' ||
              subd["UUID"] == '0bf669f0-45f2-11e7-9598-0800200c9a66') {   
            DDItems.add(subd["name"] ?? subd["address"]);
          }
        }
        if (widget.c["vName"] == connectedHRMVname) {
          if (subd["UUID"] == "0x180d") {
            DDItems.add(subd["name"] ?? subd["address"]);
          }
        }
      }
    }
    //remove duplicates:
    var seen = Set<String>();
    DDItems = DDItems.where((device) => seen.add(device)).toList();
  }

  void verifyInput(dd) {}

  @override
  Widget build(BuildContext context) {
    buildDevicesMap();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Colors.black,
          width: 2.0,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text((widget.c["humanReadableName"]), style: TextStyle(fontSize: 40), textAlign: TextAlign.left),
        Text(widget.c["value"], style: TextStyle(fontSize: 30), textAlign: TextAlign.left),
        DropdownButton(
          hint: Text(widget.c["value"]),
          items: DDItems.map((String items) {
            return DropdownMenuItem<String>(
              value: items,
              child: Text(items),
            );
          }).toList(),
          onChanged: (String? value) {
            // This is called when the user selects an item.
            setState(() {
              widget.c["value"] = value!;
              writeToSS2K(widget.bleData, widget.c);
            });
          },
        ),
        const SizedBox(height: 15),
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
