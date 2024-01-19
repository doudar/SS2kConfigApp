import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../utils/customcharhelpers.dart";

class boolCard extends StatefulWidget {
  const boolCard({super.key, required this.characteristic, required this.c});
  final BluetoothCharacteristic characteristic;
  final Map c;
  @override
  State<boolCard> createState() => _boolCardState();
}

class _boolCardState extends State<boolCard> {
  Map get c => widget.c;
  BluetoothCharacteristic get characteristic => widget.characteristic;

  @override
  void dispose() {
    super.dispose();
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
        Text((bool.parse(c["value"]) ? "On" : "Off"), style: TextStyle(fontSize: 30), textAlign: TextAlign.left),
        Switch(
          value: bool.parse(c["value"]),
          onChanged: (b) {
            c["value"] = b.toString();
            writeToSS2K(this.characteristic, this.c);
            setState(() {});
            return widget.c["value"];
          },
        ),
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
