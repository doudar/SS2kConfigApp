/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'dart:async';

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
  StreamSubscription<CharacteristicChangeEvent>? _charSubscription;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    _charSubscription = bleData.characteristicChanges
        .where((event) => event.vName == widget.c["vName"])
        .listen((event) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  Color _getTileColor() {
    if (widget.c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return (widget.c["settingType"] as SettingType).color;
  }

  @override
  Widget build(BuildContext context) {
    Color baseColor = _getTileColor();
    return Column(
      children: <Widget>[
        Card(
          elevation: 15,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    baseColor.withValues(alpha: 0.7),
                    baseColor.withValues(alpha: 0.3),
                  ],
                ),
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text((this.widget.c["humanReadableName"]), 
                style: TextStyle(
                  fontSize: 32, 
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black45)
                  ]
                ), 
                textAlign: TextAlign.center
              ),
              SizedBox(height: 10),
              Text(
                (bool.parse(this.widget.c["value"]) ? "On" : "Off"), 
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black45)
                  ]
                ), 
                textAlign: TextAlign.center
              ),
              Switch(
                value: bool.parse(this.widget.c["value"]),
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.white54,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.black26,
                onChanged: (b) {
                  this.widget.c["value"] = b.toString();
                  this.bleData.writeToSS2k(this.widget.device, this.widget.c);
                  setState(() {});
                  return this.widget.c["value"];
                },
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                      child: const Text('BACK', style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        Navigator.pop(context);
                      }),
                  const SizedBox(width: 8),
                  TextButton(
                      child: const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          ),
        ),
      ]);
  }
}
