/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/bledata.dart';
import '../utils/customcharhelpers.dart';
import '../utils/constants.dart';

class DropdownCard extends StatefulWidget {
  const DropdownCard({
    Key? key,
    required this.bleData,
    required this.device,
    required this.c,
  }) : super(key: key);

  final BLEData bleData;
  final BluetoothDevice device;
  final Map c;

  @override
  State<DropdownCard> createState() => _DropdownCardState();
}

class _DropdownCardState extends State<DropdownCard> {
  List<String> ddItems = [];
  String? selectedValue;

  @override
  void initState() {
    super.initState();
    buildDevicesMap();
    selectedValue = ddItems.isNotEmpty ? ddItems[0] : null;
  }

void buildDevicesMap() {
    late List _items;
    ddItems = [widget.c["value"]];
    widget.bleData.customCharacteristic.forEach((d) => (d["vName"] == foundDevicesVname) ? _items = jsonDecode(d["value"]) : null);

    for (var d in _items) {
      for (var subd in d.values) {
        if (widget.c["vName"] == connectedPWRVname) {
          if (subd["UUID"] == '0x1818' ||
              subd["UUID"] == '0x1826' ||
              subd["UUID"] == '6e400001-b5a3-f393-e0a9-e50e24dcca9e' ||
              subd["UUID"] == '0bf669f0-45f2-11e7-9598-0800200c9a66') {
            if (subd["name"] == null) {
              ddItems.add(subd["address"]);
            } else {
              ddItems.add(subd["name"]);
            }
          }
        }
        if (widget.c["vName"] == connectedHRMVname) {
          if (subd["UUID"] == "0x180d") {
            if (subd["name"] == null) {
              ddItems.add(subd["address"]);
            } else {
              ddItems.add(subd["name"]);
            }
          }
        }
      }
    }
    //remove duplicates:
    ddItems = ddItems.toSet().toList(); // Remove duplicates
  }

  Future _changeBLEDevice(BuildContext context) async {
    setState(() {
      widget.c["value"] = selectedValue!;
      // Assuming writeToSS2K is your method to handle selection
    });
    //reconnect devices
    writeToSS2K(widget.bleData, widget.device, widget.c);
    widget.bleData.customCharacteristic
        .forEach((d) => d["vName"] == restartBLEVname ? writeToSS2K(widget.bleData, widget.device, d, s: "1") : ());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.3,
        ),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Colors.black,
              width: 2.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  widget.c["humanReadableName"],
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.left,
                ),
              ),
              SizedBox(height: 20),
              Expanded(
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 40,
                  diameterRatio: 1.5,
                  perspective: 0.001,
                  physics: FixedExtentScrollPhysics(),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: ddItems.length,
                    builder: (BuildContext context, int index) {
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: Colors.black, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        title: Text(
                          ddItems[index],
                          textAlign: TextAlign.center,
                        ),
                        titleAlignment: ListTileTitleAlignment.top,
                        onTap: () {
                          selectedValue = ddItems[index];
                          _changeBLEDevice(context);
                        },
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    child: const Text('BACK'),
                    onPressed: () => Navigator.pop(context),
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
