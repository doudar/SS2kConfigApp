/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/customcharhelpers.dart";
import '../utils/bledata.dart';

class plainTextCard extends StatefulWidget {
  const plainTextCard({super.key, required this.bleData, required this.device,required this.c});
  final BLEData bleData;
  final BluetoothDevice device;
  final Map c;
  @override
  State<plainTextCard> createState() => _plainTextCardState();
}

class _plainTextCardState extends State<plainTextCard> {
  Map get c => widget.c;
  final controller = TextEditingController();
  bool passwordVisible = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void verifyInput(String t) {
    c["value"] = t.trim();
    controller.text = c["value"];

    setState(() {});
  }

  Widget passwordTextField() {
    return Container(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: TextField(
        obscureText: passwordVisible,
        decoration: InputDecoration(
          border: UnderlineInputBorder(),
          hintText: "Password",
          labelText: "Password",
          helperStyle: TextStyle(color: Colors.green),
          suffixIcon: IconButton(
            icon: Icon(passwordVisible ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(
                () {
                  passwordVisible = !passwordVisible;
                },
              );
            },
          ),
          alignLabelWithHint: false,
          filled: true,
        ),
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        onSubmitted: (t) {
          this.verifyInput(t);
          writeToSS2K(widget.bleData, widget.device, this.c);
          setState(() {});
          return widget.c["value"];
        },
      ),
    );
  }

  Widget regularTextField() {
    return Container(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: TextField(
        controller: this.controller,
        decoration: InputDecoration(
          border: OutlineInputBorder(),
          hintText: "Type Here",
          labelText: "SSID",
          hintStyle: TextStyle(fontWeight: FontWeight.w200),
          suffixIcon: Icon(Icons.edit_attributes),
          //fillColor: Colors.white,
          ),
        textAlign: TextAlign.left,
        textInputAction: TextInputAction.done,
        onSubmitted: (t) {
          this.verifyInput(t);
          writeToSS2K(widget.bleData, widget.device, this.c);
          setState(() {});
          return widget.c["value"];
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        ListTile(
          title: Text(widget.c["textDescription"]),
          dense: true,
        ),
        (c["vName"] == passwordVname)
            ? Text("**********")
            : Text((c["value"]), textAlign: TextAlign.left),
        (c["vName"] == passwordVname) ? passwordTextField() : regularTextField(),
        const SizedBox(height: 15),
      ]),
    );
  }
}
