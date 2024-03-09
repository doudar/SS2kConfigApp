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
  Map get c => widget.c;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);
    _lastValueSubscription = this.bleData.getMyCharacteristic(widget.device).lastValueStream.listen((value) {
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
          child: sliderCard(device: widget.device, c: c),
        );
      case "string":
        if ((c["vName"] == connectedHRMVname) || (c["vName"] == connectedPWRVname)) {
          ret = SingleChildScrollView(
            child: DropdownCard(device: widget.device, c: c),
          );
        } else {
          ret = SingleChildScrollView(
            child: plainTextCard(device: widget.device, c: c),
          );
        }
      case "bool":
        ret = SingleChildScrollView(
          child: boolCard(device: widget.device, c: c),
        );
      default:
        ret = SingleChildScrollView(
          child: plainTextCard(device: widget.device, c: c),
        );
    }

    return Card(
      child: Column(
        children: <Widget>[
          Material(
            child: ret,
            type: MaterialType.transparency,
          )]),
        //crossAxisAlignment: CrossAxisAlignment.center,
        //mainAxisAlignment: MainAxisAlignment.center,
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
    return Column(children: <Widget>[
        ExpansionTile(
          title: Text(
            (c["humanReadableName"]),
            textAlign: TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
          subtitle: Text(valueFormatter()),
          children: <Widget>[
            widgetPicker(),
        ]),
    ]);
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
