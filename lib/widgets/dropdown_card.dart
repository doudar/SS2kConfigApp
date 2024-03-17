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
import '../utils/constants.dart';
import 'dart:async';

class DropdownCard extends StatefulWidget {
  const DropdownCard({
    Key? key,
    required this.device,
    required this.c,
  }) : super(key: key);

  final BluetoothDevice device;
  final Map c;

  @override
  State<DropdownCard> createState() => _DropdownCardState();
}

class _DropdownCardState extends State<DropdownCard> {
  List<String> ddItems = [];
  String? selectedValue;
  late BLEData bleData;
  StreamSubscription? _charSubscription;
  double _wheelVisibility = 0.0;
  Timer _wheelVisibilityTimer = Timer.periodic(Duration(milliseconds: 500), (_wheelVisibilityTimer) {});

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    buildDevicesMap();
    selectedValue = ddItems.isNotEmpty ? ddItems[0] : null;
    _wheelVisibilityTimer = Timer.periodic(Duration(milliseconds: 500), (_wheelVisibilityTimer) {
      _wheelVisibility = 1;
      if (mounted) setState(() {});
    });
    try {
      _charSubscription = this.bleData.getMyCharacteristic(this.widget.device).onValueReceived.listen((data) async {
        if (mounted) {
          buildDevicesMap();
          setState(() {
            ddItems;
          });
        }
      });
    } catch (e) {
      print("Subscription Failed, $e");
    }
  }

  @override
  void dispose() {
    super.dispose();
    _charSubscription?.cancel();
    _wheelVisibilityTimer.cancel();
  }

  void buildDevicesMap() {
    late List _items;
    ddItems = [this.widget.c["value"]];
    this
        .bleData
        .customCharacteristic
        .forEach((d) => (d["vName"] == foundDevicesVname) ? _items = jsonDecode(d["value"]) : null);

    for (var d in _items) {
      for (var subd in d.values) {
        if (this.widget.c["vName"] == connectedPWRVname) {
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
        if (this.widget.c["vName"] == connectedHRMVname) {
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
      this.widget.c["value"] = selectedValue!;
      // Assuming writeToSS2K is your method to handle selection
    });
    //reconnect devices
    this.bleData.writeToSS2K(this.widget.device, this.widget.c);
    this
        .bleData
        .customCharacteristic
        .forEach((d) => d["vName"] == restartBLEVname ? this.bleData.writeToSS2K(this.widget.device, d, s: "1") : ());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.3,
        ),
        child: Card(
          elevation: 15,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  this.widget.c["humanReadableName"],
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.left,
                ),
              ),
              Text(this.widget.c["value"]),
              SizedBox(height: 20),
              Expanded(
                child: AnimatedOpacity(
                  opacity: _wheelVisibility,
                  duration: const Duration(seconds: 1),
                  child: ListWheelScrollView.useDelegate(
                    itemExtent: 40,
                    diameterRatio: 1.5,
                    perspective: 0.003,
                    physics: FixedExtentScrollPhysics(),
                    controller: FixedExtentScrollController(initialItem: ddItems.length),
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: ddItems.length,
                      builder: (BuildContext context, int index) {
                        return SizedBox(
                          width: MediaQuery.of(context).size.width * 0.65,
                          child: ListTile(
                            enableFeedback: true,
                            shape: RoundedRectangleBorder(
                              //side: BorderSide(color: Colors.black, width: 2),
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
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                      child: const Text('SCAN'),
                      onPressed: () {
                        //Find the save command and execute it
                        this
                            .bleData
                            .customCharacteristic
                            .forEach((c) => this.bleData.findNSave(this.widget.device, c, scanBLEVname));
                      }),
                  const SizedBox(width: 8),
                  TextButton(
                      child: const Text('BACK'),
                      onPressed: () {
                        Navigator.pop(context);
                      }),
                  const SizedBox(width: 8),
                  TextButton(
                      child: const Text('SAVE'),
                      onPressed: () {
                        //Find the save command and execute it
                        this
                            .bleData
                            .customCharacteristic
                            .forEach((c) => this.bleData.findNSave(this.widget.device, c, saveVname));
                        Navigator.pop(context);
                      }),
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
