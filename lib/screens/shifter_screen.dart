import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/extra.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;

  const ShifterScreen({Key? key, required this.device, required this.bleData}) : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late BluetoothCharacteristic c;
 

  getC() {
  }
  shift(int amount) {}

  buildUpShiftButton(BuildContext context) {
    return OutlinedButton(
      child: const Text("UP", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        shift(1);
      },
    );
  }

  buildDownShiftButton(BuildContext context) {
    return OutlinedButton(
      child: const Text("DOWN", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        shift(-1);
      },
    );
  }

  buildShiftIndicator(BuildContext context) {
    int _currentShift = 0;
    return Container(
      margin: const EdgeInsets.all(15.0),
      padding: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent)),
      child: Text(_currentShift.toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Row(children: <Widget>[
                buildUpShiftButton(context),
                buildDownShiftButton(context),
                buildShiftIndicator(context),
              ], mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center),
            ],
          ),
        ),
      ),
    );
  }
}
