/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/bledata.dart';
import '../utils/constants.dart';


class boolCard extends StatefulWidget {
  const boolCard({super.key, required this.device,required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<boolCard> createState() => _boolCardState();
}

class _boolCardState extends State<boolCard> {
late BLEData bleData;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Column(
      children: <Widget>[Card(
        elevation: 15,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text((this.widget.c["humanReadableName"]), style: TextStyle(fontSize: 40), textAlign: TextAlign.left),
        Text((bool.parse(this.widget.c["value"]) ? "On" : "Off"), style: TextStyle(fontSize: 30), textAlign: TextAlign.left),
        Switch(
          value: bool.parse(this.widget.c["value"]),
          onChanged: (b) {
            this.widget.c["value"] = b.toString();
            this.bleData.writeToSS2K(this.widget.device, this.widget.c);
            setState(() {});
            return this.widget.c["value"];
          },
        ),
        const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
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
      ]),
    ),]);
  }
}
