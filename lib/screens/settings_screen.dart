/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/setting_tile.dart';
import '../widgets/device_header.dart';
import '../utils/snackbar.dart';

import '../utils/bledata.dart';

class SettingsScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;

  const SettingsScreen({Key? key, required this.device, required this.bleData}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      widget.bleData.isReadingOrWriting.addListener(_rwListner);
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    widget.bleData.isReadingOrWriting.removeListener(_rwListner);
    super.dispose();
  }

  bool _refreshBlocker = true;

  void _rwListner() async {
    if(_refreshBlocker){
      return;
    }
    _refreshBlocker = true;
    if (mounted) {
    await Future.delayed(Duration(microseconds: 500));
    setState(() {});
    }
    _refreshBlocker = false;
  }

//Build the settings dropdowns
  List<Widget> buildSettings(BuildContext context) {
    List<Widget> settings = [];
    if (widget.bleData.isReadingOrWriting.value) {
      Snackbar.show(ABC.c, "Data Loading, please wait ", success: true);
      setState(() {});
    } else {
      if (widget.bleData.charReceived.value) {
        try {
          // char = myCharacteristic;
        } catch (e) {}

        _newEntry(Map c) {
          if (!widget.bleData.services.isEmpty) {
            if (c["isSetting"]) {
              settings.add(SettingTile(bleData: widget.bleData, device: widget.device, c: c));
            }
          }
        }

        widget.bleData.customCharacteristic.forEach((c) => _newEntry(c));
      }
    }
    _refreshBlocker = false;
    return settings;
  }

  @override
  Widget build(BuildContext context) {
        _refreshBlocker = true;
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        backgroundColor: Color(0xffebebeb),
        appBar: AppBar(
          title: Text(widget.device.platformName),
          centerTitle: true,
        ),
        body: Column(
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            DeviceHeader(device: widget.device, bleData: widget.bleData),
            SizedBox(
              height: 500,
              child: ListWheelScrollView(
                  //child: Column(
                  clipBehavior: Clip.antiAlias,
                  itemExtent: 100,
                  children: <Widget>[
                    ...buildSettings(context),
                  ]),
              //),
            ),
          ],
        ),
      ),
    );
  }
}
