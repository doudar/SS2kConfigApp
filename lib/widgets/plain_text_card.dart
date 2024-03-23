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
  const plainTextCard({super.key, required this.device, required this.c});
  final BluetoothDevice device;
  final Map c;
  @override
  State<plainTextCard> createState() => _plainTextCardState();
}

class _plainTextCardState extends State<plainTextCard> {
  Map get c => this.widget.c;
  final controller = TextEditingController();
  bool passwordVisible = false;
  late BLEData bleData;
  final String _currentValue = "Current Value: ";

  @override
  void initState() {
    super.initState();
    bleData = BLEDataManager.forDevice(this.widget.device);
    controller.text = c["value"];
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool verifyInput(String t) {
    // Example validation: Ensure input is not empty
    bool isValid = t.trim().isNotEmpty;
    if (isValid) {
      c["value"] = t.trim();
      controller.text = c["value"];
      setState(() {});
    }
    return isValid;
  }

  Widget passwordTextField() {
    return TextField(
      controller: this.controller,
      obscureText: !passwordVisible,
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
        this.bleData.writeToSS2K(this.widget.device, this.c);
        setState(() {});
        return this.widget.c["value"];
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
        this.bleData.writeToSS2K(this.widget.device, this.c);
        setState(() {});
        return this.widget.c["value"];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 15,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text((c["humanReadableName"]), style: TextStyle(fontSize: 40), textAlign: TextAlign.left),
        (c["vName"] == passwordVname)
            ? ((passwordVisible) ? Text(_currentValue + c["value"]) : Text(_currentValue + "**********"))
            : Text((c["value"]), style: TextStyle(fontSize: 30), textAlign: TextAlign.left),
        (c["vName"] == passwordVname) ? passwordTextField() : regularTextField(),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
                child: const Text('BACK'),
                onPressed: () {
                  Navigator.pop(context);
                }),
            const SizedBox(width: 8),
            TextButton(
                child: const Text('SAVE'),
                onPressed: () {
                  // Use the controller's text for validation
                  bool inputIsValid = verifyInput(controller.text);
                  print("**********************************" + controller.text);
                  if (inputIsValid) {
                    // Proceed with saving if input is valid
                    this.bleData.writeToSS2K(this.widget.device, this.widget.c);
                    this
                        .bleData
                        .customCharacteristic
                        .forEach((c) => this.bleData.findNSave(this.widget.device, c, saveVname));
                    Navigator.pop(context);
                  } else {
                    // Handle invalid input, e.g., show an error message
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Invalid input! Please check your input and try again.')));
                  }
                }),
            const SizedBox(width: 8),
          ],
        ),
      ]),
    );
  }
}
