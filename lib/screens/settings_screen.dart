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
  const SettingsScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late BLEData bleData;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);
    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      bleData.isReadingOrWriting.addListener(_rwListner);
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    this.bleData.isReadingOrWriting.removeListener(_rwListner);
    super.dispose();
  }

  bool _refreshBlocker = true;

  void _rwListner() async {
    if (_refreshBlocker) {
      return;
    }
    _refreshBlocker = true;
    await Future.delayed(Duration(microseconds: 500));
    if (mounted) {
      setState(() {});
    }
    _refreshBlocker = false;
  }

//Build the settings dropdowns
  List<Widget> buildSettings(BuildContext context) {
    List<Widget> settings = [];
    if (this.bleData.isReadingOrWriting.value) {
      Snackbar.show(ABC.c, "Data Loading, please wait ", success: true);
      setState(() {});
    } else {
      if (this.bleData.charReceived.value) {
        try {
          // char = myCharacteristic;
        } catch (e) {}

        _newEntry(Map c) {
          if (!this.bleData.services.isEmpty) {
            if (c["isSetting"]) {
              settings.add(SettingTile(device: widget.device, c: c));
            }
          }
        }

        this.bleData.customCharacteristic.forEach((c) => _newEntry(c));
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
            DeviceHeader(device: widget.device),
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
