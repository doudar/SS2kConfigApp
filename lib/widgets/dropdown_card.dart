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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    buildDevicesMap();
    selectedValue = ddItems.isNotEmpty ? ddItems[0] : null;
    try {
      _charSubscription = this.bleData.getMyCharacteristic(this.widget.device).onValueReceived.listen((data) async {
        if (mounted) {
          buildDevicesMap();
          setState(() {
            // Trigger rebuild
          });
        }
      });
    } catch (e) {
      print("Subscription Failed, $e");
    }
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  void buildDevicesMap() {
    List _items = [];
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
              subd["UUID"] == '0x1816' ||
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
      // Assuming writeToSS2k is your method to handle selection
    });
    //reconnect devices
    this.bleData.writeToSS2k(this.widget.device, this.widget.c);
    this
        .bleData
        .customCharacteristic
        .forEach((d) => d["vName"] == restartBLEVname ? this.bleData.writeToSS2k(this.widget.device, d, s: "1") : ());
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    this.widget.c["humanReadableName"],
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    "Current: ${this.widget.c["value"]}",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ),
                Divider(height: 24),
                Flexible(
                  child: ddItems.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(child: Text("No devices found")),
                        )
                      : ScrollbarTheme(
                          data: ScrollbarThemeData(
                            thumbColor: WidgetStatePropertyAll(Colors.blueGrey),
                            trackVisibility: WidgetStatePropertyAll(true),
                            thickness: WidgetStatePropertyAll(20.0),
                          ),
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                            controller: _scrollController,
                            shrinkWrap: true,
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            itemCount: ddItems.length,
                            separatorBuilder: (ctx, i) => SizedBox(height: 4),
                            itemBuilder: (BuildContext context, int index) {
                              final item = ddItems[index];
                              final isSelected = item == this.widget.c["value"];

                              return Material(
                                color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    selectedValue = item;
                                    _changeBLEDevice(context);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item,
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 16,
                                              color: isSelected ? Theme.of(context).primaryColor : null,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(Icons.check_circle, color: Theme.of(context).primaryColor, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                ),
                Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton.icon(
                          icon: Icon(Icons.refresh),
                          label: const Text('SCAN'),
                          onPressed: () {
                            //Find the save command and execute it
                            this
                                .bleData
                                .customCharacteristic
                                .forEach((c) => this.bleData.findNSave(this.widget.device, c, scanBLEVname));
                          }),
                      Spacer(),
                      TextButton(
                          child: const Text('BACK'),
                          onPressed: () {
                            Navigator.pop(context);
                          }),
                      const SizedBox(width: 8),
                      FilledButton(
                          child: const Text('SAVE'),
                          onPressed: () {
                            //Find the save command and execute it
                            this
                                .bleData
                                .customCharacteristic
                                .forEach((c) => this.bleData.findNSave(this.widget.device, c, saveVname));
                            Navigator.pop(context);
                          }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
