/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

import 'package:ss2kconfigapp/utils/constants.dart';
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

  Color _getTileColor() {
    if (c["value"] == noFirmSupport) return deactiveBackgroundColor;
    return (c["settingType"] as SettingType).color;
  }

  Widget passwordTextField() {
    return TextField(
      controller: this.controller,
      obscureText: !passwordVisible,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        hintText: "Password",
        labelText: "Password",
        helperStyle: TextStyle(color: Colors.white),
        labelStyle: TextStyle(color: Colors.black54),
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
        fillColor: Colors.white,
      ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      style: TextStyle(color: Colors.black, fontSize: 24),
      onSubmitted: (t) {
        this.verifyInput(t);
        this.bleData.writeToSS2k(this.widget.device, this.c);
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
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      style: TextStyle(
        fontSize: 30,
        color: Colors.black
      ),
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: (t) {
        this.verifyInput(t);
        this.bleData.writeToSS2k(this.widget.device, this.c);
        setState(() {});
        return this.widget.c["value"];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Color baseColor = _getTileColor();
    return Card(
      elevation: 15,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor.withOpacity(0.7),
                baseColor.withOpacity(0.3),
              ],
            ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text((c["humanReadableName"]), 
              style: TextStyle(
                fontSize: 32,
                color: Colors.white,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black45)
                ]
              ), 
              textAlign: TextAlign.center
            ),
            SizedBox(height: 10),
            (c["vName"] == passwordVname)
                ? ((passwordVisible) 
                    ? Text(_currentValue + c["value"], style: TextStyle(color: Colors.white, fontSize: 18, shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black45)])) 
                    : Text(_currentValue + "**********", style: TextStyle(color: Colors.white, fontSize: 18, shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black45)])))
                : Text((c["value"]), 
                    style: TextStyle(
                      fontSize: 24, 
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black45)
                      ]
                    ), 
                    textAlign: TextAlign.center
                  ),
            SizedBox(height: 10),
            (c["vName"] == passwordVname) ? passwordTextField() : regularTextField(),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                    child: const Text('BACK', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(context);
                    }),
                const SizedBox(width: 8),
                TextButton(
                    child: const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      // Use the controller's text for validation
                      bool inputIsValid = verifyInput(controller.text);
                      print("**********************************" + controller.text);
                      if (inputIsValid) {
                        // Proceed with saving if input is valid
                        this.bleData.writeToSS2k(this.widget.device, this.widget.c);
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
        ),
      ),
    );
  }
}
