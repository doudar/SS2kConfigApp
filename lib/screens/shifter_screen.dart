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
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/customcharhelpers.dart';
import '../widgets/device_header.dart';
import '../utils/bledata.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;

  const ShifterScreen({Key? key, required this.device, required this.bleData}) : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late Map c;
  String t = "Loading";
  late StreamSubscription _charSubscription;
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  @override
  void initState() {
    widget.bleData.customCharacteristic.forEach((i) => i["vName"] == shiftVname ? c = i : ());
    widget.bleData.isReadingOrWriting.addListener(_rwListner);
    startSubscription();
    super.initState();
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _charSubscription.cancel();
    widget.bleData.isReadingOrWriting.removeListener(_rwListner);
    WakelockPlus.disable();
    super.dispose();
  }

  void _rwListner() {
    if (mounted) {
      setState(() {
        t = c["value"] ?? "Loading";
      });
    }
  }

  Future startSubscription() async {
    t = c["value"] ?? "Loading";
    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      if (mounted) {
        if (state == BluetoothConnectionState.connected) {
          widget.bleData.setupConnection(widget.device);
          t = c["value"] ?? "Loading";
        } else {
          t = "Loading";
        }
        setState(() {});
      }
    });
    if (widget.bleData.charReceived.value) {
      try {
        _charSubscription = widget.bleData.getMyCharacteristic(widget.device).onValueReceived.listen((data) async {
          if (c["vName"] == shiftVname) {
            setState(() {
              t = c["value"] ?? "Loading";
            });
          }
        });
      } catch (e) {
        print("Subscription Failed, $e");
      }
    }
  }

  shift(int amount) {
    if (t != "Loading") {
      String _t = (int.parse(c["value"]) + amount).toString();
      c["value"] = _t;
      writeToSS2K(widget.bleData, widget.device, c);
    }
    WakelockPlus.enable();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
        child: Scaffold(
      backgroundColor: Color(0xffebebeb),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          "Virtual Shifter",
          style: TextStyle(
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.normal,
            fontSize: 20,
            color: Color(0xff000000),
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            DeviceHeader(device: widget.device, bleData: widget.bleData, connectOnly: true),
            Expanded(
              flex: 1,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 50, 0, 25),
                child: IconButton(
                  icon: Icon(Icons.expand_less_rounded),
                  onPressed: () {
                    shift(1);
                  },
                  color: Color(0xff000000),
                  iconSize: 200,
                ),
              ),
            ),
            Container(
              margin: EdgeInsets.all(0),
              padding: EdgeInsets.all(0),
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                color: Color(0x1f000000),
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(5.0),
                border: Border.all(color: Color(0x4d000000), width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(
                    "Gear",
                    textAlign: TextAlign.start,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.normal,
                      fontSize: 14,
                      color: Color(0xff000000),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(0, 5, 0, 0),
                    child: Text(
                      t,
                      textAlign: TextAlign.start,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.normal,
                        fontSize: 40,
                        color: Color(0xff000000),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 25, 0, 50),
                child: IconButton(
                  icon: Icon(Icons.expand_more_rounded),
                  onPressed: () {
                    shift(-1);
                  },
                  color: Color(0xff000000),
                  iconSize: 200,
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
