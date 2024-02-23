import 'dart:async';

import 'package:SS2kConfigApp/utils/constants.dart';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import "../widgets/slider_card.dart";
import "../widgets/bool_card.dart";
import "../widgets/plain_text_card.dart";
import '../widgets/dropdown_card.dart';

import '../utils/bledata.dart';

class SettingTile extends StatefulWidget {
  final BLEData bleData;
  final BluetoothDevice device;
  final Map c;
  const SettingTile({Key? key, required this.bleData, required this.device, required this.c}) : super(key: key);

  @override
  State<SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<SettingTile> {
  late String text = this.c["value"].toString();
  late StreamSubscription<List<int>> _lastValueSubscription;

  BluetoothCharacteristic get characteristic => widget.bleData.getMyCharacteristic(widget.device);
  Map get c => widget.c;

  Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    return SingleChildScrollView(
      child: fromHeroContext.widget,
    );
  }

  @override
  void initState() {
    super.initState();
    _lastValueSubscription = widget.bleData.getMyCharacteristic(widget.device).lastValueStream.listen((value) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget widgetPicker() {
    Widget ret;
    switch (c["type"]) {
      case "int":
      case "float":
      case "long":
        ret = sliderCard(bleData: widget.bleData, device: widget.device, c: c);
      case "string":
        if ((c["vName"] == connectedHRMVname) || (c["vName"] == connectedPWRVname)) {
          ret = dropdownCard(bleData: widget.bleData, device: widget.device, c: c);
        }
        ret = plainTextCard(bleData: widget.bleData, device: widget.device, c: c);
      case "bool":
        ret = boolCard(bleData: widget.bleData, device: widget.device, c: c);
      default:
        ret = plainTextCard(bleData: widget.bleData, device: widget.device, c: c);
    }

    return Card(
      child: Column(
        children: <Widget>[
          Text(c["textDescription"]),
          SizedBox(height: 50),
          Center(
            child: Hero(
                tag: c["vName"],
                //flightShuttleBuilder: _flightShuttleBuilder,
                child: Material(
                  child: ret,
                  type: MaterialType.transparency,
                )),
          ),
          Text(
            "Settings are immediate for the current session.\nClick save on the main screen to make them persistent.",
            textAlign: TextAlign.center,
          )
        ],
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
      ),
    );
  }

  String valueFormatter() {
    String _ret = c["value"] ?? "";
    if (_ret == "true" || _ret == "false") {
      _ret = (_ret == "true") ? "On" : "Off";
    }
    _ret = (c["vName"] == passwordVname) ? "**********" : _ret;
    return _ret;
  }

  @override
  void dispose() {
    _lastValueSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizedBox(height: 10);
    return Material(
      child: Hero(
        tag: c["vName"],
        //flightShuttleBuilder: _flightShuttleBuilder,
        child: Material(
          type: MaterialType.transparency,
          child: Card(
            child: ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              title: Column(
                children: <Widget>[
                  Text((c["humanReadableName"]),
                      textAlign: TextAlign.left, style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    valueFormatter(),
                    textAlign: TextAlign.right,
                  ),
                  Icon(Icons.edit_note_sharp),
                ],
              ),
              tileColor: (c["value"] == noFirmSupport) ? deactiveBackgroundColor : null,
              onTap: () {
                if (c["value"] == noFirmSupport) {
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute<Widget>(builder: (BuildContext context) {
                      return Scaffold(
                        appBar: AppBar(title: const Text('Edit Setting')),
                        body: Center(child: widgetPicker()),
                      );
                    }),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
