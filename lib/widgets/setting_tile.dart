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
  final BLEData bleData;
  final BluetoothDevice device;
  final Map c;
  const SettingTile({Key? key, required this.bleData, required this.device, required this.c}) : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  late StreamSubscription<List<int>> _lastValueSubscription;

  BluetoothCharacteristic get characteristic =>
      widget.bleData.getMyCharacteristic(widget.device);

  Map get c => widget.c;


  @override
  void initState() {
    super.initState();
    _lastValueSubscription = widget.bleData
        .getMyCharacteristic(widget.device)
        .lastValueStream
        .listen((value) {
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
          child: sliderCard(
              bleData: widget.bleData, device: widget.device, c: c),
        );
      case "string":
        if ((c["vName"] == connectedHRMVname) ||
            (c["vName"] == connectedPWRVname)) {
          ret = SingleChildScrollView(
            child: DropdownCard(
                bleData: widget.bleData, device: widget.device, c: c),
          );
        } else {
          ret = SingleChildScrollView(
            child: plainTextCard(
                bleData: widget.bleData, device: widget.device, c: c),
          );
        }
      case "bool":
        ret = SingleChildScrollView(
          child: boolCard(bleData: widget.bleData, device: widget.device, c: c), // boolCard
        );
      default:
        ret = SingleChildScrollView(
          child: plainTextCard(
              bleData: widget.bleData, device: widget.device, c: c),
        );
    }

    return Card(
      color: Colors.black12,

      child: Column(
        mainAxisSize: MainAxisSize.min,
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
    return Hero(
      tag: c["vName"],
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              fadeRoute(
                Scaffold(
                  appBar: AppBar(title: const Text('Edit Setting')),
                  body: Center(child: widgetPicker()),
                  // ... other Scaffold content
                ),
              ),
            );
          },
          child: Material(
            //type: MaterialType.transparency,

            child: Card(
              //tag: c["vName"],
              margin: EdgeInsets.fromLTRB(0, 0, 0, 16),
              color: Color(0xffffffff),
              shadowColor: Color(0x4d939393),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4.0),
                side: BorderSide(color: Color(0x4d9e9e9e), width: 1),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              (c["humanReadableName"]),
                              textAlign: TextAlign.start,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontStyle: FontStyle.normal,
                                fontSize: 16,
                                color: Color(0xff000000),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(0, 4, 0, 0),
                              child: Text(
                                valueFormatter(),
                                textAlign: TextAlign.start,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontStyle: FontStyle.normal,
                                  fontSize: 14,
                                  color: Color(0xff6c6c6c),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Color(0xff212435),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

}
