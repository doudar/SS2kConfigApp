import 'dart:async';
import 'package:SS2kConfigApp/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/extra.dart';
import '../utils/customcharhelpers.dart';

class ShifterScreen extends StatefulWidget {
  final BluetoothDevice device;
  final BLEData bleData;

  const ShifterScreen({Key? key, required this.device, required this.bleData}) : super(key: key);

  @override
  State<ShifterScreen> createState() => _ShifterScreenState();
}

class _ShifterScreenState extends State<ShifterScreen> {
  late Map c;
  late StreamSubscription _charSubscription;

  @override
  void initState() {
    super.initState();
    widget.bleData.customCharacteristic.forEach((i) => i["vName"] == shiftVname ? c = i : ());

    _charSubscription = widget.bleData.myCharacteristic.onValueReceived.listen((state) async {
      if (mounted) {
        setState(() {});
      }
    });
  }

    @override
  void dispose() {
    _charSubscription.cancel();
    super.dispose();
  }

  shift(int amount) {
    String _t = (int.parse(c["value"]) + amount).toString();
    c["value"] = _t;
    writeToSS2K(widget.bleData, c);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
        child: Scaffold(
      backgroundColor: Color(0xffffffff),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          "Virtual Shifter",
          style: TextStyle(
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.normal,
            fontSize: 50,
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
                      c["value"].toString(),
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
