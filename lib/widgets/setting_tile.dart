/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:ss2kconfigapp/utils/constants.dart';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import "../widgets/slider_card.dart";
import "../widgets/bool_card.dart";
import "../widgets/plain_text_card.dart";
import '../widgets/dropdown_card.dart';

import '../utils/bledata.dart';
import '../utils/stream_extensions.dart';

class SettingTile extends StatefulWidget {
  final BleDevice device;
  final Map c;
  const SettingTile({Key? key, required this.device, required this.c}) : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  StreamSubscription? _charSubscription;
  late BLEData bleData;
  Map get c => this.widget.c;
  late String _value;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forBleDevice(widget.device);
    _value = valueFormatter();
    startSubscription();
  }

  @override
  void dispose() {
    _charSubscription?.cancel();
    super.dispose();
  }

  Future startSubscription() async {
    if (this.bleData.charReceived.value) {
      try {
        // Subscribe to characteristic changes stream instead of direct onValueReceived
        _charSubscription = bleData.characteristicChanges
            .where((event) => event.vName == c["vName"])
            .listen((event) {
          if (_value != c["value"]) {
            _value = valueFormatter();
            if (mounted) {
              setState(() {});
            }
          }
        });
      } catch (e) {
        print("Subscription Failed, $e");
      }
    }
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
          SizedBox(height: 10),
          Center(
            child: Hero(
                tag: c["vName"],
                child: Material(
                  child: ret,
                  type: MaterialType.transparency,
                )),
          ),
          SizedBox(height: 10),
          Text("Settings are immediate for the current session.\nClick save to make them persistent.",
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
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

  Color _getTileColor() {
    if (c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return (c["settingType"] as SettingType).color;
  }

  @override
  Widget build(BuildContext context) {
    SizedBox(height: 10);
    Color baseColor = _getTileColor();
    
    return Hero(
      tag: c["vName"],
      child: Material(
        type: MaterialType.transparency,
        child: Card(
          margin: EdgeInsets.fromLTRB(10, 5, 10, 5),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(vertical: 25.0, horizontal: 16.0),
              shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
               ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      (c["humanReadableName"]),
                      textAlign: TextAlign.left, 
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: Offset(1.0, 1.0),
                            blurRadius: 15.0,
                            color: Colors.black45,
                          ),
                        ],
                      )
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _value,
                            style: TextStyle(
                              color: Colors.white70, 
                              fontSize: 18,
                              shadows: [
                                Shadow(
                                  offset: Offset(1.0, 1.0),
                                  blurRadius: 15.0,
                                  color: Colors.black45,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.edit, color: Colors.white54, size: 20),
                    ],
                  ),
                ],
              ),
              // tileColor property removed as we use Container decoration
              trailing: IconButton(
                icon: Icon(Icons.info_outline, color: Colors.white),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text(c["humanReadableName"]),
                        content: Text(c["textDescription"] ?? "No description available."),
                        actions: [
                          TextButton(
                            child: Text("Close"),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              onTap: () {
                if (c["value"] == noFirmSupport) {
                } else {
                  Navigator.push(
                    context,
                    fadeRoute(
                      Scaffold(
                        appBar: AppBar(title: const Text('Edit Setting')),
                        body: Center(
                          child: SingleChildScrollView(
                            child: widgetPicker(),
                          ),
                        ),
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
