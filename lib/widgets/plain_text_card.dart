/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/bledata.dart';

class plainTextCard extends StatefulWidget {
  const plainTextCard({super.key, required this.device,required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<plainTextCard> createState() => _plainTextCardState();
}

class _plainTextCardState extends State<plainTextCard> {
  Map get c => widget.c;
  final controller = TextEditingController();
  bool passwordVisible = false;
   late BLEData bleData;

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(widget.device);
  }
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
    return TextField(
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
        this.bleData.writeToSS2K( widget.device, this.c);
        setState(() {});
        return widget.c["value"];
      },
    );
  }

  Widget regularTextField() {
    return TextField(
      controller: this.controller,
      decoration: InputDecoration(
        hintText: "Type Here",
        hintStyle: TextStyle(fontWeight: FontWeight.w200),
        prefixIcon: Icon(Icons.edit_attributes),
        fillColor: Colors.white,
      ),
      style: TextStyle(
        fontSize: 30,
      ),
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: (t) {
        this.verifyInput(t);
        this.bleData.writeToSS2K(widget.device, this.c);
        setState(() {});
        return widget.c["value"];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Colors.black,
          width: 2.0,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text((c["humanReadableName"]), style: TextStyle(fontSize: 40), textAlign: TextAlign.left),
        (c["vName"] == passwordVname)
            ? Text("**********")
            : Text((c["value"]), style: TextStyle(fontSize: 30), textAlign: TextAlign.left),
        (c["vName"] == passwordVname) ? passwordTextField() : regularTextField(),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            const SizedBox(width: 8),
            TextButton(
              child: const Text('BACK'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
      ]),
    );
  }
}
