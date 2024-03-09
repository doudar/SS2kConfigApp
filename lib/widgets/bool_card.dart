/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/bledata.dart';


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
    bleData = BLEDataManager.forDevice(widget.device);
  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return SwitchListTile(
      subtitle: Text(widget.c["textDescription"]),
      value: bool.parse(widget.c["value"]),
      onChanged: (b) {
        widget.c["value"] = b.toString();
        this.bleData.writeToSS2K(widget.device, widget.c);
        setState(() {});
        return widget.c["value"];
        },
    );
  }
}
