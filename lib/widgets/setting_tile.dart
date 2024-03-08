/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:SS2kConfigApp/utils/constants.dart';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../widgets/slider_card.dart";
import "../widgets/bool_card.dart";
import "../widgets/plain_text_card.dart";
import '../widgets/dropdown_card.dart';

import '../utils/bledata.dart';

class SettingTile extends StatefulWidget {
  final BluetoothDevice device;
  final Map c;
  const SettingTile({Key? key, required this.device, required this.c}) : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  late StreamSubscription<List<int>> _lastValueSubscription;
  late BLEData bleData;
  Map get c => this.widget.c;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    _lastValueSubscription = this.bleData.getMyCharacteristic(this.widget.device).lastValueStream.listen((value) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget widgetPicker() {
    Widget ret;
    switch (c["type"]) {
      case "int":
      case "float":
      case "long":
        ret = SingleChildScrollView(
          child: sliderCard(device: this.widget.device, c: c),
        );
      case "string":
        if ((c["vName"] == connectedHRMVname) || (c["vName"] == connectedPWRVname)) {
          ret = SingleChildScrollView(
            child: DropdownCard(device: this.widget.device, c: c),
          );
        } else {
          ret = SingleChildScrollView(
            child: plainTextCard(device: this.widget.device, c: c),
          );
        }
      case "bool":
        ret = SingleChildScrollView(
          child: boolCard(device: this.widget.device, c: c),
        );
      default:
        ret = SingleChildScrollView(
          child: plainTextCard(device: this.widget.device, c: c),
        );
    }

    return Card(
      color: Colors.black12,
      child: Column(
        children: <Widget>[
          Text(c["textDescription"], style: TextStyle(color: Colors.white)),
          SizedBox(height: 50),
          Center(
            child: Hero(
                tag: c["vName"],
                //flightShuttleBuilder: _flightShuttleBuilder,
                child: Material(
                  child: ret,
                  type: MaterialType.transparency,
                )),
          ),
          SizedBox(height: 50),
          Text(
              "Settings are immediate for the current session.\nClick save on the main screen to make them persistent.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white)),
        ],
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    SizedBox(height: 10);
    return Material(
      color: Color(0xffebebeb),
      child: Hero(
        tag: c["vName"],
        //flightShuttleBuilder: _flightShuttleBuilder,
        child: Material(
          type: MaterialType.transparency,
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
              tileColor: (c["value"] == noFirmSupport) ? deactiveBackgroundColor : Colors.black12,
              onTap: () {
                if (c["value"] == noFirmSupport) {
                } else {
                  Navigator.push(
                    context,
                    fadeRoute(
                      Scaffold(
                        appBar: AppBar(title: const Text('Edit Setting')),
                        body: Center(child: widgetPicker()),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

Route fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
  );
}
